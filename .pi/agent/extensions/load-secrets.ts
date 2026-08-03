import type { ExtensionAPI } from "@earendil-works/pi-coding-agent";
import { execSync, spawn } from "node:child_process";
import { existsSync } from "node:fs";

export default function (pi: ExtensionAPI) {
  const OP_PATH = "op://dev/BRAVE_API_KEY/credential";

  let keyState: "pending" | "loaded" | "failed" = "pending";
  let loadPromise: Promise<void> | null = null;

  type Context = Parameters<Parameters<typeof pi.on>[1]>[1];

  function is1PasswordRunning(): boolean {
    try {
      execSync("pgrep -f '1password'", { timeout: 5_000 });
      return true;
    } catch {
      return false;
    }
  }

  function open1Password(): void {
    if (is1PasswordRunning()) return;
    const child = spawn("xdg-open", ["onepassword://"], { detached: true, stdio: "ignore" });
    child.on("error", (err) => {
      console.error("[load-secrets] Failed to launch 1Password:", err.message);
    });
    child.unref();
  }

  function doLoad(ctx: Context): Promise<void> {
    if (!is1PasswordRunning()) {
      keyState = "failed";
      ctx.ui.notify("1Password desktop app is not running", "error");
      return;
    }
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

  // Open 1Password on startup if not running
  pi.on("session_start", async (_event, _ctx) => {
    open1Password();
  });

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
