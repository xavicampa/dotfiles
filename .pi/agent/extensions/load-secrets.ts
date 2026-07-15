import type { ExtensionAPI } from "@earendil-works/pi-coding-agent";
import { execSync } from "node:child_process";

export default function (pi: ExtensionAPI) {
  let keyLoaded = false;

  async function loadKey(
    ctx: Parameters<Parameters<typeof pi.on>[1]>[1],
  ) {
    if (keyLoaded) return;
    try {
      const key = execSync("op read op://dev/BRAVE_API_KEY/credential", {
        encoding: "utf-8",
        timeout: 120_000,
      }).trim();
      if (key) {
        process.env.BRAVE_API_KEY = key;
        keyLoaded = true;
        ctx.ui.notify("Brave API key loaded", "info");
      }
    } catch (err) {
      const message = err instanceof Error ? err.message : String(err);
      ctx.ui.notify(`Failed to load Brave API key: ${message}`, "error");
    }
  }

  // On-demand via command
  pi.registerCommand("load-secrets", {
    description: "Load secrets from 1Password",
    handler: async (_args, ctx) => {
      await loadKey(ctx);
    },
  });

  // Auto-load on first web_search
  pi.on("tool_call", async (event, ctx) => {
    if (event.toolName === "web_search" && !keyLoaded) {
      await loadKey(ctx);
    }
  });
}
