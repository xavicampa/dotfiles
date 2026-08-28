import type { ExtensionAPI } from "@earendil-works/pi-coding-agent";
import { execSync, spawn } from "node:child_process";

export default function (pi: ExtensionAPI) {
  type Secret = { opPath: string; envVar: string; label: string };

  const SECRETS: Secret[] = [
    { opPath: "op://dev/BRAVE_API_KEY/credential", envVar: "BRAVE_API_KEY", label: "Brave API key" },
    { opPath: "op://dev/HF_TOKEN/credential", envVar: "HF_TOKEN", label: "HF token" },
    { opPath: "op://Private/portainer-rpi-ai-user/notesPlain", envVar: "PORTAINER_API_KEY", label: "Portainer API key" },
  ];

  type State = "pending" | "loaded" | "failed";
  const state = new Map<string, State>();
  const loading = new Map<string, Promise<void>>();
  for (const s of SECRETS) state.set(s.envVar, "pending");

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

  function doLoad(secret: Secret, ctx: Context): Promise<void> {
    if (!is1PasswordRunning()) {
      state.set(secret.envVar, "failed");
      ctx.ui.notify("1Password desktop app is not running", "error");
      return Promise.resolve();
    }
    try {
      const value = execSync(`op read ${secret.opPath}`, {
        encoding: "utf-8",
        timeout: 120_000,
      }).trim();
      if (value) {
        process.env[secret.envVar] = value;
        state.set(secret.envVar, "loaded");
        ctx.ui.notify(`${secret.label} loaded`, "info");
      } else {
        state.set(secret.envVar, "failed");
      }
    } catch (err) {
      state.set(secret.envVar, "failed");
      const message = err instanceof Error ? err.message : String(err);
      ctx.ui.notify(`Failed to load ${secret.label}: ${message}`, "error");
    }
    return Promise.resolve();
  }

  async function loadSecrets(ctx: Context, envVars: string[]): Promise<void> {
    for (const secret of SECRETS.filter((s) => envVars.includes(s.envVar))) {
      if (state.get(secret.envVar) === "loaded") continue;
      const inFlight = loading.get(secret.envVar);
      if (inFlight) {
        await inFlight;
        continue;
      }
      const p = doLoad(secret, ctx);
      loading.set(secret.envVar, p);
      try {
        await p;
      } finally {
        loading.delete(secret.envVar);
      }
    }
  }

  async function forceReload(ctx: Context): Promise<void> {
    for (const s of SECRETS) state.set(s.envVar, "pending");
    await loadSecrets(ctx, SECRETS.map((s) => s.envVar));
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

  // Auto-load on first use (no retry after failure)
  const HF_CMD = /\bhf\s+(download|cache|auth|models|env|cp|version|whoami)\b/;
  const PORTAINER_CMD = /portainer[\\/]scripts[\\/]portainer|rpi:9443/;
  pi.on("tool_call", async (event, ctx) => {
    if (event.toolName === "web_search") {
      await loadSecrets(ctx, ["BRAVE_API_KEY"]);
    } else if (event.toolName === "read" && /skills[\\/]portainer[\\/]SKILL\.md$/.test(String(event.input?.path ?? ""))) {
      await loadSecrets(ctx, ["PORTAINER_API_KEY"]);
    } else if (event.toolName === "bash" && typeof event.input?.command === "string") {
      const cmd = event.input.command;
      const vars: string[] = [];
      if (HF_CMD.test(cmd)) vars.push("HF_TOKEN");
      if (PORTAINER_CMD.test(cmd)) vars.push("PORTAINER_API_KEY");
      if (vars.length > 0) await loadSecrets(ctx, vars);
    }
  });
}
