/**
 * context-bar — Visual context usage bar + last call timing in the footer status line.
 *
 * Renders a compact progress bar and timing metrics using ctx.ui.setStatus().
 * Green → yellow → red as context fills, matching the default footer thresholds (70/90%).
 * While the assistant is streaming, the percentage, elapsed time, and output tokens
 * update live (throttled, tokens estimated) with the tok/s rate greyed out; when the
 * message ends the exact metrics snap in with clear text. A cancelled request
 * (Esc) keeps the live values from the moment of the cancel instead of the
 * zeroed usage the provider reports for aborted streams.
 *
 * Compaction (manual, threshold, or overflow recovery) is shown as
 * "compacting…" while the summary call runs. Afterward the context size is
 * unknown until the next provider response, so the bar shows "?" (matching
 * pi's own footer) — still with live time/tokens while the next response
 * streams — until its usage snaps the percentage back in.
 */

import type { AssistantMessage } from "@earendil-works/pi-ai";
import type { ExtensionAPI, ExtensionContext } from "@earendil-works/pi-coding-agent";

const STATUS_KEY = "context-bar";

// Paired fg+bg codes for solid bar cells (dimmed shades)
const GREEN = `\x1b[38;2;40;100;58;48;2;40;100;58m`;
const YELLOW = `\x1b[38;2;120;125;70;48;2;120;125;70m`;
const RED = `\x1b[38;2;130;45;45;48;2;130;45;45m`;
const UNFILLED = `\x1b[38;5;236;48;5;236m`;
const RESET = `\x1b[0m`;

// Text colors for overlay on colored bar (dimmed)
const TEXT_LIGHT = `\x1b[38;2;160;160;160m`;   // grey on green/red
const TEXT_DARK = `\x1b[38;2;60;60;60m`;        // dark grey on yellow

// Faint on/off: greys out in-flight metrics. The terminal keeps faint across
// characters, so it must be set explicitly for every overlay character.
const DIM = `\x1b[2m`;
const NORMAL = `\x1b[22m`;

/** A run of overlay text; `dim` greys it out while the turn is still running. */
interface OverlaySegment {
  text: string;
  dim?: boolean;
}

function render(pct: number, segments: OverlaySegment[]): string {
  const barLen = process.stdout.columns ?? 80;
  // pct < 0 = unknown (post-compaction): render an empty bar.
  const filled = Math.round((Math.max(0, pct) / 100) * barLen);

  const overlayText = segments.map((s) => s.text).join("");
  // Per-character dim flags keyed by visible position (no escape codes).
  const dimAt: boolean[] = [];
  for (const seg of segments) {
    for (let i = 0; i < seg.text.length; i++) dimAt.push(!!seg.dim);
  }

  // Center the overlay in the row
  const overlayStart = Math.max(0, Math.floor((barLen - overlayText.length) / 2));

  // Match built-in footer thresholds: 70% warning, 90% error
  const barColor = pct > 90 ? RED : pct > 70 ? YELLOW : GREEN;
  const textColor = pct > 70 && pct <= 90 ? TEXT_DARK : TEXT_LIGHT;

  let out = "";
  for (let i = 0; i < barLen; i++) {
    const inOverlay = i >= overlayStart && i < overlayStart + overlayText.length;
    const bg = i < filled ? barColor : UNFILLED;
    if (inOverlay) {
      const j = i - overlayStart;
      out += bg + textColor + (dimAt[j] ? DIM : NORMAL) + overlayText[j];
    } else {
      out += bg + NORMAL + (i < filled ? "█" : "░");
    }
  }

  return out + RESET;
}

// --- Timing metrics ---

interface LastCallMetrics {
  /** Total wall time: message_start → message_end (includes TTFT). */
  durationMs: number;
  outputTokens: number;
  /** Pure generation rate: first streamed token → message_end (TTFT excluded). */
  outputTokensPerSecond: number;
}

let metrics: LastCallMetrics | null = null;
/**
 * Last rendered live values, kept so a cancelled request can display what was
 * on screen. Invalidated whenever a message completes (any stop reason), so a
 * non-null value always belongs to the still-in-flight message.
 */
let lastLiveMetrics: LastCallMetrics | null = null;
let messageStartTime = 0;
let firstTokenTime = 0; // 0 = no streamed token seen yet for the current message
let lastStreamUpdate = 0;
const STREAM_UPDATE_INTERVAL_MS = 250;

function fmtMs(ms: number): string {
  return ms < 1000 ? `${ms}ms` : `${(ms / 1000).toFixed(2)}s`;
}

function renderTiming(): string {
  if (!metrics) return "";
  return `${fmtMs(metrics.durationMs)} • ${metrics.outputTokens} tok • ${metrics.outputTokensPerSecond.toFixed(1)} tok/s`;
}

// Mirror pi's internal estimate (chars/4) for an in-flight assistant message.
// pi does not include the partial response in getContextUsage() until message_end,
// so we add it ourselves while streaming.
function estimateStreamingTokens(msg: AssistantMessage): number {
  let chars = 0;
  for (const block of msg.content) {
    if (block.type === "text") chars += block.text.length;
    else if (block.type === "thinking") chars += block.thinking.length;
    else if (block.type === "toolCall")
      chars += block.name.length + JSON.stringify(block.arguments ?? {}).length;
  }
  return Math.ceil(chars / 4);
}

/** Live timing values for the in-flight message (estimated, wall clock). */
function liveMetricsFor(msg: AssistantMessage, now = Date.now()): LastCallMetrics {
  const outputTokens = estimateStreamingTokens(msg);
  const elapsedMs = messageStartTime > 0 ? now - messageStartTime : 0;
  const genStart = firstTokenTime > 0 ? firstTokenTime : messageStartTime;
  const genMs = genStart > 0 ? now - genStart : 0;
  return {
    durationMs: elapsedMs,
    outputTokens,
    outputTokensPerSecond: genMs > 0 ? outputTokens / (genMs / 1000) : 0,
  };
}

function update(ctx: ExtensionContext, streaming?: AssistantMessage): void {
  if (!ctx.hasUI) return;
  const usage = ctx.getContextUsage();
  // Only clear when pi itself can't compute usage (no model selected).
  if (!usage || usage.contextWindow <= 0) {
    ctx.ui.setStatus(STATUS_KEY, undefined);
    return;
  }
  // After compaction, pi reports percent === null until an assistant
  // responds again (pre-compaction usage is not trustworthy, and a pure
  // estimate would miss the system prompt/tools). Show "?" like pi's own
  // footer does for the same window; render() treats pct < 0 as unknown.
  const percent = usage.percent;
  const pctKnown = percent !== null;
  let pct: number = -1;
  if (pctKnown) pct = percent;
  if (streaming) {
    // Live view while the turn is running: the percentage includes the
    // estimated partial response, and the time/token numbers tick along with
    // it. The rate is still provisional, so it stays greyed out until
    // message_end snaps in the exact usage-based values.
    let estTokens = 0;
    if (pctKnown && usage.tokens !== null && usage.contextWindow > 0) {
      estTokens = estimateStreamingTokens(streaming);
      pct = Math.min(
        100,
        ((usage.tokens + estTokens) / usage.contextWindow) * 100,
      );
    }
    const live = liveMetricsFor(streaming);
    const segments: OverlaySegment[] = [
      { text: pctKnown ? `${pct.toFixed(1)}%` : "?" },
      { text: ` • ${fmtMs(live.durationMs)} • ${live.outputTokens} tok` },
      { text: ` • ${live.outputTokensPerSecond.toFixed(1)} tok/s`, dim: true },
    ];
    ctx.ui.setStatus(STATUS_KEY, render(pct, segments));
    return;
  }
  if (!pctKnown) {
    ctx.ui.setStatus(STATUS_KEY, render(pct, [{ text: "?" }]));
    return;
  }
  const timing = renderTiming();
  const overlay = timing ? `${pct.toFixed(1)}% • ${timing}` : `${pct.toFixed(1)}%`;
  ctx.ui.setStatus(STATUS_KEY, render(pct, [{ text: overlay }]));
}

export default function (pi: ExtensionAPI) {
  // message_update fires per token with the cumulative partial message. The
  // partial is NOT in the session's message list yet (pi only finalizes it into
  // state.messages at message_end), so estimate its tokens and add them to the
  // baseline; message_end then snaps to the exact usage-based value.
  pi.on("message_update", (event, ctx) => {
    if (event.message.role !== "assistant") return;
    // Capture first-token time before throttling so it reflects the actual
    // first streamed token, not the first throttled render.
    if (firstTokenTime === 0) firstTokenTime = Date.now();
    // Refresh the live snapshot on every update (not just throttled renders)
    // so a cancelled request keeps the values that were just on screen.
    lastLiveMetrics = liveMetricsFor(event.message as AssistantMessage);
    const now = Date.now();
    if (now - lastStreamUpdate < STREAM_UPDATE_INTERVAL_MS) return;
    lastStreamUpdate = now;
    update(ctx, event.message as AssistantMessage);
  });

  pi.on("message_start", (event, ctx) => {
    if (event.message.role === "assistant") {
      messageStartTime = Date.now();
      firstTokenTime = 0;
      // Show the in-flight state (greyed rate) right away, even before the
      // first token arrives (TTFT).
      update(ctx, event.message as AssistantMessage);
    }
  });

  pi.on("message_end", async (event, ctx) => {
    if (event.message.role === "assistant") {
      const msg = event.message as AssistantMessage;
      const now = Date.now();
      if (msg.stopReason === "aborted") {
        // Cancelled (Esc): the provider's usage for an aborted stream is
        // zeroed, so keep the live values instead of snapping to zero. The
        // aborted message still carries the partial content, so recompute
        // the live metrics at the moment of the cancel.
        if (msg.content.length > 0) {
          metrics = liveMetricsFor(msg, now);
        } else if (lastLiveMetrics) {
          // A fresh empty failure message stands in for the cancelled one
          // (its message_start already reset the timing state): keep the
          // live values it was showing just before the cancel.
          metrics = lastLiveMetrics;
        } else {
          metrics = {
            durationMs: messageStartTime > 0 ? now - messageStartTime : 0,
            outputTokens: 0,
            outputTokensPerSecond: 0,
          };
        }
      } else {
        // No streamed tokens (e.g. empty or error response): fall back to the
        // message_start time so the rate degrades to the total window.
        const genStart = firstTokenTime > 0 ? firstTokenTime : messageStartTime;
        const durationMs = now - messageStartTime;
        const generationMs = now - genStart;
        const usage = msg.usage;
        const outputTokensPerSecond =
          generationMs > 0 ? usage.output / (generationMs / 1000) : 0;

        metrics = {
          durationMs,
          outputTokens: usage.output,
          outputTokensPerSecond,
        };
      }
      lastLiveMetrics = null;
      firstTokenTime = 0;
    }
    update(ctx);
  });

  pi.on("turn_end", (_e, ctx) => update(ctx));

  // Compaction (manual /compact, threshold, overflow recovery) replaces the
  // context. The summary call takes seconds — show it instead of leaving a
  // stale pre-compaction bar on screen.
  pi.on("session_before_compact", (_e, ctx) => {
    if (!ctx.hasUI) return;
    ctx.ui.setStatus(STATUS_KEY, render(-1, [{ text: "compacting…", dim: true }]));
  });

  pi.on("session_compact", (_e, ctx) => {
    // The last call's metrics are stale: that message is inside the summary
    // now. Re-render the post-compaction "?" state.
    metrics = null;
    lastLiveMetrics = null;
    update(ctx);
  });

  pi.on("session_compact_failed", (_e, ctx) => {
    // Context is unchanged; drop the "compacting…" state.
    update(ctx);
  });
  pi.on("session_start", (_e, ctx) => {
    metrics = null;
    lastLiveMetrics = null;
    messageStartTime = 0;
    firstTokenTime = 0;
    update(ctx);
  });
  pi.on("agent_settled", (_e, ctx) => update(ctx));
  pi.on("session_shutdown", (_e, ctx) => {
    if (!ctx.hasUI) return;
    ctx.ui.setStatus(STATUS_KEY, undefined);
  });
}
