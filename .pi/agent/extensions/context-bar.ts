/**
 * context-bar — Visual context usage bar in the footer status line.
 *
 * Renders a compact progress bar on the third footer line using ctx.ui.setStatus().
 * Green → yellow → red as context fills, matching the default footer thresholds (70/90%).
 */

import type { ExtensionAPI, ExtensionContext } from "@earendil-works/pi-coding-agent";

const STATUS_KEY = "context-bar";
const BAR_LEN = 20;

const rgb = (r: number, g: number, b: number) => `\x1b[38;2;${r};${g};${b}m`;
const reset = "\x1b[39m";

// Same colors as context-progress-bar.ts
const GREEN = rgb(78, 201, 114);
const YELLOW = rgb(241, 250, 140);
const RED = rgb(255, 85, 85);

function render(pct: number, tokens: number, window: number): string {
  const filled = Math.round((pct / 100) * BAR_LEN);

  const color =
    pct > 85 ? RED : pct > 60 ? YELLOW : GREEN;

  let bar = "";
  for (let i = 0; i < BAR_LEN; i++) {
    if (i < filled) {
      bar += color + "█";
    } else {
      bar += "\x1b[38;5;240m" + "░";
    }
  }

  const fmt = (n: number) =>
    n < 1000 ? `${n}` : n < 1000000 ? `${Math.round(n / 1000)}k` : `${Math.round(n / 1000000)}M`;

  return `${bar}${reset} ${color}${Math.round(pct)}%${reset} ${reset}${fmt(tokens)}/${fmt(window)}`;
}

function update(ctx: ExtensionContext): void {
  if (!ctx.hasUI) return;
  const usage = ctx.getContextUsage();
  if (!usage || usage.percent === null) {
    ctx.ui.setStatus(STATUS_KEY, undefined);
    return;
  }
  const win = usage.contextWindow ?? 0;
  ctx.ui.setStatus(STATUS_KEY, render(usage.percent, usage.tokens, win));
}

export default function (pi: ExtensionAPI) {
  pi.on("turn_end", (_e, ctx) => update(ctx));
  pi.on("session_compact", (_e, ctx) => update(ctx));
  pi.on("session_start", (_e, ctx) => update(ctx));
  pi.on("agent_end", (_e, ctx) => update(ctx));
}
