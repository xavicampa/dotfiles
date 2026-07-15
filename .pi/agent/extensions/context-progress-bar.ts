/**
 * Context Progress Bar Footer
 *
 * Replaces the default footer with a progress bar for context usage.
 * Layout: [progress bar]  branch(+~?)  model
 *
 * Enabled automatically on session start.
 * Use /contextbar to toggle on/off.
 */

import { execSync } from "node:child_process";
import type { AssistantMessage } from "@earendil-works/pi-ai";
import type { ExtensionAPI, ExtensionContext } from "@earendil-works/pi-coding-agent";
import { truncateToWidth, visibleWidth } from "@earendil-works/pi-tui";

let cachedGitStatus: string | undefined;
let cachedGitCwd: string | undefined;
let cachedGitTime = 0;
const GIT_CACHE_MS = 3_000;

function getGitStatus(cwd: string): string {
	if (cachedGitStatus !== undefined && cachedGitCwd === cwd && Date.now() - cachedGitTime < GIT_CACHE_MS) {
		return cachedGitStatus;
	}

	try {
		const out = execSync("git status --porcelain", { cwd, encoding: "utf8", timeout: 2000, stdio: "pipe" }).trim();
		if (!out) {
			cachedGitStatus = "";
			cachedGitCwd = cwd;
			cachedGitTime = Date.now();
			return "";
		}

		let staged = 0, modified = 0, untracked = 0;
		for (const line of out.split("\n")) {
			const x = line[0];
			if (x === "A" || x === "M" || x === "D" || x === "R" || x === "C" || x === "T" || x === "U") staged++;
			else if (line[2] === "M" || line[2] === "D") modified++;
			else if (x === "?" || x === "!") untracked++;
		}

		const parts: string[] = [];
		if (staged > 0) parts.push(`+${staged}`);
		if (modified > 0) parts.push(`~${modified}`);
		if (untracked > 0) parts.push(`?${untracked}`);

		cachedGitStatus = parts.length > 0 ? `(${parts.join("")})` : "";
		cachedGitCwd = cwd;
		cachedGitTime = Date.now();
		return cachedGitStatus;
	} catch {
		cachedGitStatus = "";
		cachedGitCwd = cwd;
		cachedGitTime = Date.now();
		return "";
	}
}

const BAR_WIDTH = 20;
const BLOCK_FULL = "\u2588";
const BLOCK_THREE_QUARTERS = "\u2587";
const BLOCK_HALF = "\u2586";
const BLOCK_ONE_QUARTER = "\u2585";
const BLOCK_EMPTY = "\u2591";

function setContextFooter(ctx: ExtensionContext) {
	ctx.ui.setFooter((tui, theme, footerData) => {
		const unsub = footerData.onBranchChange(() => tui.requestRender());

		return {
			dispose: unsub,
			invalidate() {},
			render(width: number): string[] {
				const usage = ctx.getContextUsage();
				const model = ctx.model;
				const contextWindow = model?.contextWindow;

				const fmt = (n: number) => (n < 1000 ? `${n}` : `${(n / 1000).toFixed(1)}k`);

				let barStr = "";
				let percent = 0;

				if (usage && contextWindow) {
					percent = Math.min((usage.tokens / contextWindow) * 100, 100);

					const colorFg = percent < 60
						? (s: string) => "\x1b[38;2;78;201;114m" + s + "\x1b[39m"
						: percent < 85
							? (s: string) => "\x1b[38;2;241;250;140m" + s + "\x1b[39m"
							: (s: string) => "\x1b[38;2;255;85;85m" + s + "\x1b[39m";

					let bar = "";
					for (let i = 0; i < BAR_WIDTH; i++) {
						const fill = (percent / 100) * BAR_WIDTH;
						const idx = i;
						if (idx < Math.floor(fill)) {
							bar += BLOCK_FULL;
						} else if (idx === Math.floor(fill)) {
							const frac = fill - idx;
							if (frac >= 0.875) bar += BLOCK_FULL;
							else if (frac >= 0.625) bar += BLOCK_THREE_QUARTERS;
							else if (frac >= 0.375) bar += BLOCK_HALF;
							else if (frac >= 0.125) bar += BLOCK_ONE_QUARTER;
							else bar += BLOCK_EMPTY;
						} else {
							bar += BLOCK_EMPTY;
						}
					}
					barStr = colorFg(`[${bar}] `) + colorFg(`${Math.round(percent)}%`) + theme.fg("dim", ` ${fmt(contextWindow)}`);
				} else {
					barStr = theme.fg("dim", `[${BLOCK_EMPTY.repeat(BAR_WIDTH)}] --%`);
				}

				let input = 0, output = 0;
				for (const e of ctx.sessionManager.getBranch()) {
					if (e.type === "message" && e.message.role === "assistant") {
						const m = e.message as AssistantMessage;
						input += m.usage.input;
						output += m.usage.output;
					}
				}

				const tokenStr = theme.fg("dim", ` ↑${fmt(input)} ↓${fmt(output)}`);
				const contextStr = barStr + tokenStr;

				const branch = footerData.getGitBranch();
				const status = getGitStatus(ctx.cwd);
				const center = branch ? theme.fg("accent", theme.bold(branch) + (status ? " " + status : "")) : "";
				const modelId = model?.id || "no-model";
				const right = theme.fg("dim", modelId);

				const totalPad = Math.max(1, width - visibleWidth(contextStr) - visibleWidth(center) - visibleWidth(right));
				const leftPad = " ".repeat(Math.floor(totalPad / 2));
				const rightPad = " ".repeat(totalPad - Math.floor(totalPad / 2));
				return [truncateToWidth(contextStr + leftPad + center + rightPad + right, width)];
			},
		};
	});
}

export default function (pi: ExtensionAPI) {
	let enabled = true;

	pi.on("session_start", async (_event, ctx) => {
		if (enabled) setContextFooter(ctx);
	});

	pi.registerCommand("contextbar", {
		description: "Toggle context progress bar footer",
		handler: async (_args, ctx) => {
			enabled = !enabled;

			if (enabled) {
				setContextFooter(ctx);
				ctx.ui.notify("Context progress bar enabled", "info");
			} else {
				ctx.ui.setFooter(undefined);
				ctx.ui.notify("Default footer restored", "info");
			}
		},
	});
}
