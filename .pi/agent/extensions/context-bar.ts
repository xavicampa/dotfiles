/**
 * context-bar — Visual context usage bar + last call timing in the footer status line.
 *
 * Renders a compact progress bar and timing metrics using ctx.ui.setStatus().
 * Colors come from the active theme (success/warning/error tokens, resolved for the
 * terminal's color mode), so the bar stays readable on light and dark themes alike.
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
 *
 * The bar spans the whole window by default; STATUS_RESERVE leaves room for
 * other extensions' statuses, which share this line and get truncated. Peers can
 * instead publish text on the "status-bar:text" bus channel and it is drawn
 * inside the bar (see PEER_STATUS_CHANNEL). Non-TUI modes (RPC) get the same
 * information as plain text instead of ANSI.
 */

import type { AssistantMessage } from "@earendil-works/pi-ai";
import type { ExtensionAPI, ExtensionContext, Theme } from "@earendil-works/pi-coding-agent";
import {
  backgroundAnsi,
  colorToRgb,
  foregroundAnsi,
  mixColors,
  rgbColor,
  type Color,
} from "@earendil-works/pi-tui";

const STATUS_KEY = "context-bar";

/**
 * Columns left free at the right end of the status line. The footer joins every
 * extension's status on one line and truncates it to the terminal width, so a
 * full-width bar leaves no room for the others (e.g. "Refreshing models...").
 * 0 = the bar spans the whole window.
 */
const STATUS_RESERVE = 0;
const MIN_BAR_COLUMNS = 12;

/** Which third of the green → yellow → red ramp the bar is in. */
type UsageState = "ok" | "warn" | "high";

/**
 * Precomputed escape sequences for one render. Both halves of the bar are
 * painted solid (fg = bg) so the block glyph disappears into the color: a shade
 * glyph like ░ renders as a dithered band that is far noisier than the track it
 * is meant to be. Every cell re-states its own background — SGR backgrounds
 * persist across cells, so a fill that stops mid-line would otherwise bleed its
 * color across the rest of the bar.
 */
interface Palette {
  fillFg: string;
  fillBg: string;
  trackFg: string;
  trackBg: string;
  textOnFill: string;
  dimOnFill: string;
  textOnTrack: string;
  dimOnTrack: string;
}

const BLACK = rgbColor(0, 0, 0);
const WHITE = rgbColor(255, 255, 255);

/** WCAG relative luminance: the sRGB channels have to be linearized first. */
function luminance(color: Color): number {
  const { r, g, b } = colorToRgb(color);
  const lin = (v: number) => {
    const s = v / 255;
    return s <= 0.04045 ? s / 12.92 : ((s + 0.055) / 1.055) ** 2.4;
  };
  return 0.2126 * lin(r) + 0.7152 * lin(g) + 0.0722 * lin(b);
}

/** WCAG contrast ratio, 1 (identical) to 21 (black on white). */
function contrast(a: Color, b: Color): number {
  const la = luminance(a);
  const lb = luminance(b);
  return (Math.max(la, lb) + 0.05) / (Math.min(la, lb) + 0.05);
}

/** Push `text` away from `bg` until it clears `min` contrast. */
function ensureContrast(text: Color, bg: Color, min: number): Color {
  let out = text;
  const sink = luminance(bg) > 0.4 ? BLACK : WHITE;
  for (let i = 0; i < 12 && contrast(out, bg) < min; i++) out = mixColors(out, sink, 0.1);
  return out;
}

function palette(theme: Theme, state: UsageState): Palette {
  const mode = theme.getColorMode();
  const base = theme.colors[state === "high" ? "error" : state === "warn" ? "warning" : "success"];
  const dark = theme.appearance !== "light";
  // Stand-in for the terminal's own background, which the theme is tuned against.
  const page = dark ? BLACK : WHITE;
  // The bar is a background element, so mute both halves toward the page: the
  // raw tokens are mid-tones that swallow any number drawn on top of them.
  const fill = mixColors(base, page, 0.55);
  const track = mixColors(theme.colors.borderMuted, page, 0.5);
  // Everything on the bar is quiet footer text, not a headline: the theme's own
  // muted/dim tokens match how pi styles the stats line above it. Muted carries
  // the settled values, dim marks the provisional in-flight ones.
  const onFill = ensureContrast(theme.colors.muted, fill, 4.5);
  const onTrack = ensureContrast(theme.colors.muted, track, 4.5);
  return {
    fillFg: foregroundAnsi(fill, mode),
    fillBg: backgroundAnsi(fill, mode),
    trackFg: foregroundAnsi(track, mode),
    trackBg: backgroundAnsi(track, mode),
    textOnFill: foregroundAnsi(onFill, mode),
    // Darker tokens rather than SGR 2: faint is not universally supported and
    // would leave the text at full brightness where it is ignored.
    dimOnFill: foregroundAnsi(ensureContrast(theme.colors.dim, fill, 3), mode),
    textOnTrack: foregroundAnsi(onTrack, mode),
    dimOnTrack: foregroundAnsi(ensureContrast(theme.colors.dim, track, 3), mode),
  };
}

/** A run of overlay text; `dim` greys it out while the turn is still running. */
interface OverlaySegment {
  text: string;
  dim?: boolean;
}

function barColumns(): number {
  return Math.max(MIN_BAR_COLUMNS, (process.stdout.columns ?? 80) - STATUS_RESERVE);
}

/** Drop the least important segments until the overlay fits the bar. */
function fitSegments(segments: OverlaySegment[], barLen: number): OverlaySegment[] {
  const kept = [...segments];
  while (kept.length > 1 && kept.reduce((n, s) => n + s.text.length, 0) > barLen) kept.pop();
  return kept;
}

function render(pct: number, segments: OverlaySegment[], theme: Theme, barLen: number): string {
  const p = palette(theme, pct > 90 ? "high" : pct > 70 ? "warn" : "ok");
  // pct < 0 = unknown (post-compaction): render an empty bar.
  const filled = Math.round((Math.max(0, pct) / 100) * barLen);

  const overlay = fitSegments(segments, barLen);
  const overlayText = overlay.map((s) => s.text).join("");
  // Per-character dim flags keyed by visible position (no escape codes).
  const dimAt: boolean[] = [];
  for (const seg of overlay) {
    for (let i = 0; i < seg.text.length; i++) dimAt.push(!!seg.dim);
  }

  // Center the overlay in the row
  const overlayStart = Math.max(0, Math.floor((barLen - overlayText.length) / 2));

  let out = "";
  for (let i = 0; i < barLen; i++) {
    const inOverlay = i >= overlayStart && i < overlayStart + overlayText.length;
    const isFill = i < filled;
    if (inOverlay) {
      const j = i - overlayStart;
      const fg = isFill ? (dimAt[j] ? p.dimOnFill : p.textOnFill) : dimAt[j] ? p.dimOnTrack : p.textOnTrack;
      out += (isFill ? p.fillBg : p.trackBg) + fg + overlayText[j];
    } else if (isFill) {
      out += p.fillBg + p.fillFg + "█";
    } else {
      out += p.trackBg + p.trackFg + "█";
    }
  }

  return out + "\x1b[0m";
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
 * Last streamed partial, kept so a cancelled request can report what was on
 * screen. Held by reference only — estimating tokens from it is done once at
 * message_end, never per streamed token.
 */
let lastPartial: AssistantMessage | null = null;
let messageStartTime = 0;
let firstTokenTime = 0; // 0 = no streamed token seen yet for the current message
let lastStreamUpdate = 0;
const STREAM_UPDATE_INTERVAL_MS = 250;

function fmtMs(ms: number): string {
  return ms < 1000 ? `${ms}ms` : `${(ms / 1000).toFixed(2)}s`;
}

// Mirror pi's internal estimate (chars/4) for an in-flight assistant message.
// pi does not include the partial response in getContextUsage() until message_end,
// so we add it ourselves while streaming. Called only on throttled renders and at
// message_end: per streamed token this would re-stringify the growing tool-call
// arguments and turn a single large write into quadratic work.
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

/**
 * Rebuild the last-call metrics from the session, so the idle bar is not blank
 * after a start/resume/reload or a branch switch until the next response runs.
 * An assistant message's own timestamp is when its stream started; the entry's
 * timestamp is when it was written, i.e. message_end — the pair gives the same
 * wall-clock window the live view measured. TTFT is not recoverable from
 * history, so the rate is computed over the whole window, which is slightly
 * conservative next to a live measurement.
 */
function restoreMetrics(ctx: ExtensionContext): void {
  metrics = null;
  const branch = ctx.sessionManager.getBranch();
  for (let i = branch.length - 1; i >= 0; i--) {
    const entry = branch[i];
    // Anything older than a compaction lives inside the summary now.
    if (entry.type === "compaction") return;
    if (entry.type !== "message" || entry.message.role !== "assistant") continue;
    const msg = entry.message;
    const output = msg.usage?.output ?? 0;
    if (output <= 0) continue; // aborted/error turns report zeroed usage
    const start = msg.timestamp;
    const end = Date.parse(entry.timestamp);
    if (!Number.isFinite(start) || !Number.isFinite(end) || end < start) continue;
    const durationMs = end - start;
    metrics = {
      durationMs,
      outputTokens: output,
      outputTokensPerSecond: durationMs > 0 ? output / (durationMs / 1000) : 0,
    };
    return;
  }
}

/**
 * Text other extensions publish on the shared bus so it can ride inside the bar.
 * The footer puts every setStatus() value on one line and truncates it, and this
 * bar owns that line, so a peer's setStatus() text would be cut off (or push a
 * dim "…" over the end of the bar). Data: { key, text } — empty text clears it.
 */
const PEER_STATUS_CHANNEL = "status-bar:text";
const peerStatuses = new Map<string, string>();
/** Most recent handler context, so a bus event can trigger a re-render. */
let lastCtx: ExtensionContext | null = null;

/** Peer text sits just after the percentage: it is transient, so it outranks timing. */
function peerSegments(): OverlaySegment[] {
  return [...peerStatuses.values()].map((text) => ({ text: ` • ${text}` }));
}

/**
 * Overlay segments, most important first: fitSegments() drops from the end when
 * the terminal is too narrow, so the rate goes before the token count.
 */
function liveSegments(pctKnown: boolean, pct: number, live: LastCallMetrics): OverlaySegment[] {
  return [
    { text: pctKnown ? `${pct.toFixed(1)}%` : "?" },
    ...peerSegments(),
    { text: ` • ${fmtMs(live.durationMs)}` },
    { text: ` • ${live.outputTokens} tok` },
    { text: ` • ${live.outputTokensPerSecond.toFixed(1)} tok/s`, dim: true },
  ];
}

function settledSegments(pct: number): OverlaySegment[] {
  const head: OverlaySegment[] = [{ text: `${pct.toFixed(1)}%` }, ...peerSegments()];
  if (!metrics) return head;
  return [
    ...head,
    { text: ` • ${fmtMs(metrics.durationMs)}` },
    { text: ` • ${metrics.outputTokens} tok` },
    { text: ` • ${metrics.outputTokensPerSecond.toFixed(1)} tok/s` },
  ];
}

function update(ctx: ExtensionContext, streaming?: AssistantMessage): void {
  lastCtx = ctx;
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

  let segments: OverlaySegment[];
  if (streaming) {
    // Live view while the turn is running: the percentage includes the
    // estimated partial response, and the time/token numbers tick along with
    // it. The rate is still provisional, so it stays greyed out until
    // message_end snaps in the exact usage-based values.
    if (pctKnown && usage.tokens !== null) {
      const estTokens = estimateStreamingTokens(streaming);
      pct = Math.min(100, ((usage.tokens + estTokens) / usage.contextWindow) * 100);
    }
    segments = liveSegments(pctKnown, pct, liveMetricsFor(streaming));
  } else if (!pctKnown) {
    segments = [{ text: "?" }];
  } else {
    segments = settledSegments(pct);
  }

  // RPC and other non-terminal clients get the text, not an ANSI picture.
  const text =
    ctx.mode === "tui"
      ? render(pct, segments, ctx.ui.theme, barColumns())
      : segments.map((s) => s.text).join("");
  ctx.ui.setStatus(STATUS_KEY, text);
}

export default function (pi: ExtensionAPI) {
  // Peer text arrives outside the event lifecycle, so redraw from the last
  // context we were handed. A replaced session invalidates that context; pi
  // reports handler errors, but the bar would stay stale, so guard it.
  pi.events.on(PEER_STATUS_CHANNEL, (data) => {
    const { key, text } = (data ?? {}) as { key?: unknown; text?: unknown };
    if (typeof key !== "string" || !key) return;
    if (typeof text === "string" && text.trim()) peerStatuses.set(key, text.trim());
    else peerStatuses.delete(key);
    const ctx = lastCtx;
    if (!ctx) return;
    try {
      update(ctx);
    } catch {
      lastCtx = null;
    }
  });

  // message_update fires per token with the cumulative partial message. The
  // partial is NOT in the session's message list yet (pi only finalizes it into
  // state.messages at message_end), so estimate its tokens and add them to the
  // baseline; message_end then snaps to the exact usage-based value.
  pi.on("message_update", (event, ctx) => {
    if (event.message.role !== "assistant") return;
    // Capture first-token time before throttling so it reflects the actual
    // first streamed token, not the first throttled render.
    if (firstTokenTime === 0) firstTokenTime = Date.now();
    // Keep the latest partial for the cancel path by reference only: the token
    // estimate is paid on throttled renders, never per streamed token.
    lastPartial = event.message;
    const now = Date.now();
    if (now - lastStreamUpdate < STREAM_UPDATE_INTERVAL_MS) return;
    lastStreamUpdate = now;
    update(ctx, event.message);
  });

  pi.on("message_start", (event, ctx) => {
    if (event.message.role === "assistant") {
      messageStartTime = Date.now();
      lastStreamUpdate = messageStartTime;
      firstTokenTime = 0;
      lastPartial = event.message;
      // Show the in-flight state (greyed rate) right away, even before the
      // first token arrives (TTFT).
      update(ctx, event.message);
    }
  });

  pi.on("message_end", async (event, ctx) => {
    if (event.message.role === "assistant") {
      const msg = event.message;
      const now = Date.now();
      if (msg.stopReason === "aborted") {
        // Cancelled (Esc): the provider's usage for an aborted stream is
        // zeroed, so keep the live values instead of snapping to zero. The
        // aborted message still carries the partial content, so recompute the
        // live metrics once, here.
        if (msg.content.length > 0) {
          metrics = liveMetricsFor(msg, now);
        } else if (lastPartial && lastPartial.content.length > 0) {
          // A fresh empty failure message stands in for the cancelled one
          // (its message_start already reset the timing state): keep the
          // values from the partial that was on screen just before the cancel.
          metrics = liveMetricsFor(lastPartial, now);
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
        const durationMs = messageStartTime > 0 ? now - messageStartTime : 0;
        const generationMs = genStart > 0 ? now - genStart : 0;
        const usage = msg.usage;
        // When a stream fails before generation starts, pi emits message_start
        // immediately before message_end, so that window is not a measurement.
        if (messageStartTime === 0 || (durationMs < 50 && usage.output === 0)) {
          metrics = null;
        } else {
          metrics = {
            durationMs,
            outputTokens: usage.output,
            outputTokensPerSecond: generationMs > 0 ? usage.output / (generationMs / 1000) : 0,
          };
        }
      }
      lastPartial = null;
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
    const segments: OverlaySegment[] = [{ text: "compacting…", dim: true }];
    ctx.ui.setStatus(
      STATUS_KEY,
      ctx.mode === "tui" ? render(-1, segments, ctx.ui.theme, barColumns()) : "compacting…",
    );
  });

  pi.on("session_compact", (_e, ctx) => {
    // The last call's metrics are stale: that message is inside the summary
    // now. Re-render the post-compaction "?" state.
    metrics = null;
    lastPartial = null;
    update(ctx);
  });

  pi.on("session_compact_failed", (_e, ctx) => {
    // Context is unchanged; drop the "compacting…" state.
    update(ctx);
  });

  // Context limits and the projection both change outside a run: a new model
  // has a different window, and branch navigation changes which messages count.
  // Nothing else re-renders while the agent is idle, so refresh here.
  pi.on("model_select", (_e, ctx) => update(ctx));
  pi.on("session_tree", (_e, ctx) => {
    // A different branch has a different last response.
    restoreMetrics(ctx);
    update(ctx);
  });

  pi.on("session_start", (_e, ctx) => {
    lastPartial = null;
    messageStartTime = 0;
    firstTokenTime = 0;
    lastStreamUpdate = 0;
    restoreMetrics(ctx);
    update(ctx);
  });
  pi.on("agent_settled", (_e, ctx) => update(ctx));
  pi.on("session_shutdown", (_e, ctx) => {
    peerStatuses.clear();
    lastCtx = null;
    if (!ctx.hasUI) return;
    ctx.ui.setStatus(STATUS_KEY, undefined);
  });
}
