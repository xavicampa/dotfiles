/**
 * context-bar — Visual context usage bar + last call timing in the footer status line.
 *
 * Renders a compact progress bar and timing metrics using ctx.ui.setStatus().
 * Green → yellow → red as context fills, matching the default footer thresholds (70/90%).
 * Updates on turn boundaries, message end, session compaction, and agent settlement.
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

function render(pct: number, overlay: string): string {
  const barLen = process.stdout.columns ?? 80;
  const filled = Math.round((pct / 100) * barLen);

  // Center the overlay in the row
  const overlayStart = Math.max(0, Math.floor((barLen - overlay.length) / 2));

  // Match built-in footer thresholds: 70% warning, 90% error
  const barColor = pct > 90 ? RED : pct > 70 ? YELLOW : GREEN;
  const textColor = pct > 70 && pct <= 90 ? TEXT_DARK : TEXT_LIGHT;

  let out = "";
  for (let i = 0; i < barLen; i++) {
    const inOverlay = i >= overlayStart && i < overlayStart + overlay.length;
    const bg = i < filled ? barColor : UNFILLED;
    if (inOverlay) {
      out += bg + textColor + overlay[i - overlayStart];
    } else {
      out += bg + (i < filled ? "█" : "░");
    }
  }

  return out + RESET;
}

// --- Timing metrics ---

interface LastCallMetrics {
  durationMs: number;
  outputTokens: number;
  outputTokensPerSecond: number;
}

let metrics: LastCallMetrics | null = null;
let messageStartTime = 0;

function fmtMs(ms: number): string {
  return ms < 1000 ? `${ms}ms` : `${(ms / 1000).toFixed(2)}s`;
}

function renderTiming(): string {
  if (!metrics) return "";
  return `${fmtMs(metrics.durationMs)} • ${metrics.outputTokens} tok • ${metrics.outputTokensPerSecond.toFixed(1)} tok/s`;
}

function update(ctx: ExtensionContext): void {
  if (!ctx.hasUI) return;
  const usage = ctx.getContextUsage();
  if (!usage || usage.percent === null) {
    ctx.ui.setStatus(STATUS_KEY, undefined);
    return;
  }
  const timing = renderTiming();
  ctx.ui.setStatus(STATUS_KEY, render(usage.percent, timing));
}

export default function (pi: ExtensionAPI) {
  pi.on("message_start", async (event, _ctx) => {
    if (event.message.role === "assistant") {
      messageStartTime = Date.now();
    }
  });

  pi.on("message_end", async (event, ctx) => {
    if (event.message.role === "assistant") {
      const msg = event.message as AssistantMessage;
      const durationMs = Date.now() - messageStartTime;
      const usage = msg.usage;
      const outputTokensPerSecond =
        durationMs > 0 ? usage.output / (durationMs / 1000) : 0;

      metrics = {
        durationMs,
        outputTokens: usage.output,
        outputTokensPerSecond,
      };
    }
    update(ctx);
  });

  pi.on("turn_end", (_e, ctx) => update(ctx));
  pi.on("session_compact", (_e, ctx) => update(ctx));
  pi.on("session_start", (_e, ctx) => {
    metrics = null;
    messageStartTime = 0;
    update(ctx);
  });
  pi.on("agent_settled", (_e, ctx) => update(ctx));
  pi.on("session_shutdown", (_e, ctx) => {
    if (!ctx.hasUI) return;
    ctx.ui.setStatus(STATUS_KEY, undefined);
  });
}
