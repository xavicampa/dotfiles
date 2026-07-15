import type { ExtensionAPI } from "@earendil-works/pi-coding-agent";
import { execSync } from "node:child_process";

export default function (pi: ExtensionAPI) {
  const OP_PATH = "op://dev/BRAVE_API_KEY/credential";

  let keyState: "pending" | "loaded" | "failed" = "pending";
  let loadPromise: Promise<void> | null = null;

  type Context = Parameters<Parameters<typeof pi.on>[1]>[1];

  function doLoad(ctx: Context): Promise<void> {
    try {
      const key = execSync(`op read ${OP_PATH}`, {
        encoding: "utf-8",
        timeout: 120_000,
      }).trim();
      if (key) {
        process.env.BRAVE_API_KEY = key;
        keyState = "loaded";
        ctx.ui.notify("Brave API key loaded", "info");
      } else {
        keyState = "failed";
      }
    } catch (err) {
      keyState = "failed";
      const message = err instanceof Error ? err.message : String(err);
      ctx.ui.notify(`Failed to load Brave API key: ${message}`, "error");
    }
  }

  async function loadKey(ctx: Context): Promise<void> {
    if (keyState === "loaded") return;
    if (loadPromise) return loadPromise;
    loadPromise = doLoad(ctx);
    try {
      await loadPromise;
    } finally {
      loadPromise = null;
    }
  }

  async function forceReload(ctx: Context): Promise<void> {
    if (keyState === "loaded" && !loadPromise) {
      keyState = "pending";
    }
    await loadKey(ctx);
  }

  // On-demand via command (allows retry after failure)
  pi.registerCommand("load-secrets", {
    description: "Load secrets from 1Password",
    handler: async (_args, ctx) => {
      await forceReload(ctx);
    },
  });

  // Auto-load on first web_search (no retry after failure)
  pi.on("tool_call", async (event, ctx) => {
    if (event.toolName === "web_search" && keyState === "pending") {
      await loadKey(ctx);
    }
  });
}
