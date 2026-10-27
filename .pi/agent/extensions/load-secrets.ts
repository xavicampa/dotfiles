import type { ExtensionAPI } from "@earendil-works/pi-coding-agent";
import { spawn } from "node:child_process";

export default function (pi: ExtensionAPI) {
  type Secret = { opPath: string; envVar: string; label: string };

  const SECRETS: Secret[] = [
    { opPath: "op://dev/BRAVE_API_KEY/credential", envVar: "BRAVE_API_KEY", label: "Brave API key" },
    { opPath: "op://dev/EXA_API_KEY/credential", envVar: "EXA_API_KEY", label: "Exa API key" },
    { opPath: "op://dev/HF_TOKEN/credential", envVar: "HF_TOKEN", label: "HF token" },
    { opPath: "op://Private/portainer-rpi-ai-user/notesPlain", envVar: "PORTAINER_API_KEY", label: "Portainer API key" },
    // rpi/omniroute gateway key for .pi/agent/extensions/local-model-discovery.ts.
    // The previous key was hardcoded in that extension and is public in git
    // history — treat it as burned and rotate it on the gateway when convenient.
    { opPath: "op://dev/OMNIROUTE_API_KEY/credential", envVar: "OMNIROUTE_API_KEY", label: "omniroute API key" },
  ];

  type State = "pending" | "loaded" | "failed";
  /** One `op read` outcome, before the secret it belongs to is attached. */
  type LoadOutcome = { label: string; ok: boolean; reason?: string; cancelled?: boolean };
  type LoadResult = LoadOutcome & { envVar: string };
  const state = new Map<string, State>();
  const loading = new Map<string, Promise<LoadResult>>();
  /** When each secret last failed, so the automatic path can back off. */
  const failedAt = new Map<string, number>();
  /** Auto-load retries a failed secret at most once per window; /load-secrets retries immediately. */
  const RETRY_COOLDOWN_MS = 60_000;
  for (const s of SECRETS) state.set(s.envVar, "pending");

  function markLoaded(envVar: string): void {
    state.set(envVar, "loaded");
    failedAt.delete(envVar);
  }

  function markFailed(envVar: string): void {
    state.set(envVar, "failed");
    failedAt.set(envVar, Date.now());
  }

  function inCooldown(envVar: string, now: number): boolean {
    if (state.get(envVar) !== "failed") return false;
    const at = failedAt.get(envVar);
    return at !== undefined && now - at < RETRY_COOLDOWN_MS;
  }

  type Context = Parameters<Parameters<typeof pi.on>[1]>[1];

  const OP_READ_TIMEOUT_MS = 120_000;
  const PROBE_TIMEOUT_MS = 5_000;

  function firstLine(text: string): string {
    return text.trim().split("\n")[0] ?? "";
  }

  function notify(ctx: Context, message: string, level: "info" | "warning" | "error"): void {
    try {
      ctx.ui?.notify(message, level);
    } catch {
      // No UI in print/JSON mode; a status message must never break a tool call.
    }
  }

  /**
   * Stand-in context for loads no handler owns (the event-bus path). No signal:
   * there is no turn to cancel against, so the op read is bounded by
   * OP_READ_TIMEOUT_MS alone. No ui: that path loads with silent: true.
   */
  const busCtx = { signal: undefined, ui: undefined } as unknown as Context;

  // Everything below runs through pi.exec (async spawn, no shell, honours timeout and the
  // turn's abort signal). execSync would freeze the whole Pi process — UI, other extensions,
  // and Ctrl+C — for as long as 1Password takes to answer.
  async function is1PasswordRunning(): Promise<boolean> {
    try {
      // -x matches the process name exactly (comm is "1password"), -i ignores case; no shell
      // wrapper is spawned, so nothing here can match the probe against itself.
      const res = await pi.exec("pgrep", ["-x", "-i", "1password"], { timeout: PROBE_TIMEOUT_MS });
      return res.code === 0 && !res.killed;
    } catch {
      return false;
    }
  }

  async function open1Password(): Promise<void> {
    if (await is1PasswordRunning()) return;
    const child = spawn("xdg-open", ["onepassword://"], { detached: true, stdio: "ignore" });
    child.on("error", (err) => {
      console.error("[load-secrets] Failed to launch 1Password:", err.message);
    });
    child.unref();
  }

  async function doLoad(secret: Secret, ctx: Context): Promise<LoadOutcome> {
    const { label, envVar, opPath } = secret;
    if (!(await is1PasswordRunning())) {
      // Cold start: launch the app and let `op read` wait on its unlock prompt
      // rather than failing the load outright. Nothing warms 1Password up in
      // advance anymore, so every trigger path has to be able to start it.
      await open1Password();
    }
    const res = await pi.exec("op", ["read", opPath], { timeout: OP_READ_TIMEOUT_MS, signal: ctx.signal });
    if (ctx.signal?.aborted) {
      // Interrupted, not proven impossible: stay pending so the next call retries without backoff.
      return { label, ok: false, cancelled: true };
    }
    // killed must be checked before code: a SIGTERM'd child resolves with code 0 here.
    if (res.killed) {
      markFailed(envVar);
      return { label, ok: false, reason: `op read timed out after ${OP_READ_TIMEOUT_MS / 1000}s` };
    }
    if (res.code !== 0) {
      markFailed(envVar);
      return { label, ok: false, reason: firstLine(res.stderr) || `op read failed (exit ${res.code}; is the op CLI on PATH?)` };
    }
    const value = res.stdout.trim();
    if (!value) {
      markFailed(envVar);
      return { label, ok: false, reason: "empty value from 1Password" };
    }
    process.env[envVar] = value;
    markLoaded(envVar);
    return { label, ok: true };
  }

  /** Deduplicated load of one secret. Never rejects: a blocked tool call is worse than a failed load. */
  function loadOne(secret: Secret, ctx: Context): Promise<LoadResult> {
    const inFlight = loading.get(secret.envVar);
    if (inFlight) return inFlight; // join a running attempt, keeping its outcome and reason
    const p = doLoad(secret, ctx)
      .catch((err: unknown): LoadOutcome => {
        markFailed(secret.envVar);
        return { label: secret.label, ok: false, reason: err instanceof Error ? err.message : String(err) };
      })
      .then((outcome): LoadResult => ({ ...outcome, envVar: secret.envVar }))
      .finally(() => {
        if (loading.get(secret.envVar) === p) loading.delete(secret.envVar);
      });
    loading.set(secret.envVar, p);
    return p;
  }

  /**
   * @param opts.force retry immediately, ignoring the failure back-off — the
   *   caller asked explicitly (/load-secrets, or a provider refresh).
   * @param opts.silent skip notify(): the caller reports the outcome itself.
   *   Used by the event-bus path, where the requesting extension owns the UI.
   */
  async function loadSecrets(
    ctx: Context,
    envVars: string[],
    opts: { force?: boolean; silent?: boolean } = {},
  ): Promise<LoadResult[]> {
    const now = Date.now();
    const wanted = SECRETS.filter((s) => envVars.includes(s.envVar)
      && state.get(s.envVar) !== "loaded"
      // Back off after a failure instead of retrying on every matching tool call: each attempt can
      // wait minutes on 1Password. /load-secrets passes force to retry right away.
      && (opts.force === true || !inCooldown(s.envVar, now)));
    if (wanted.length === 0) return [];
    // Concurrent: several `op read` calls waiting on the app at once cost one wait, not several.
    const results = await Promise.all(wanted.map((s) => loadOne(s, ctx)));
    const settled = results.filter((r) => !r.cancelled);
    if (!opts.silent && settled.length > 0) {
      const failed = settled.filter((r) => !r.ok);
      if (failed.length > 0) {
        const details = failed.map((r) => (r.reason ? `${r.label}: ${r.reason}` : r.label)).join("; ");
        notify(ctx, `Secret load failed — ${details}. Retry with /load-secrets.`, "error");
      } else {
        notify(ctx, `${settled.map((r) => r.label).join(", ")} loaded`, "info");
      }
    }
    return results;
  }

  async function forceReload(ctx: Context): Promise<void> {
    for (const s of SECRETS) {
      state.set(s.envVar, "pending");
      failedAt.delete(s.envVar);
    }
    await loadSecrets(ctx, SECRETS.map((s) => s.envVar), { force: true });
  }

  // Warm 1Password up on startup so the first load (triggered later by a
  // matching tool call or by a provider refresh) does not also pay for the app
  // launch. No secret is fetched here: the rpi provider catalog went on-demand
  // (see local-model-discovery.ts), so nothing 1Password-backed is needed
  // before the first turn. Not awaited — a cold app start must never hold up
  // startup; doLoad also starts the app when a load arrives with it closed.
  pi.on("session_start", async () => {
    await open1Password();
  });

  // On-demand via command (allows retry after failure)
  pi.registerCommand("load-secrets", {
    description: "Load secrets from 1Password",
    handler: async (_args, ctx) => {
      await forceReload(ctx);
    },
  });

  // Auto-load on first use; a failure backs off for RETRY_COOLDOWN_MS, /load-secrets retries immediately
  const HF_CMD = /\bhf\s+(download|cache|auth|models|env|cp|version|whoami)\b/;
  const PORTAINER_CMD = /portainer[\\/]scripts[\\/]portainer|rpi:9443/;
  // Direct hits against the omniroute gateway (curl /v1/models, debug probes).
  const OMNIROUTE_CMD = /rpi:20128|OMNIROUTE_API_KEY/;
  pi.on("tool_call", async (event, ctx) => {
    if (event.toolName === "web_search") {
      await loadSecrets(ctx, ["BRAVE_API_KEY", "EXA_API_KEY"]);
    } else if (event.toolName === "read" && /skills[\\/]portainer[\\/]SKILL\.md$/.test(String(event.input?.path ?? ""))) {
      await loadSecrets(ctx, ["PORTAINER_API_KEY"]);
    } else if (event.toolName === "bash" && typeof event.input?.command === "string") {
      const cmd = event.input.command;
      const vars: string[] = [];
      if (HF_CMD.test(cmd)) vars.push("HF_TOKEN");
      if (PORTAINER_CMD.test(cmd)) vars.push("PORTAINER_API_KEY");
      if (OMNIROUTE_CMD.test(cmd)) vars.push("OMNIROUTE_API_KEY");
      if (vars.length > 0) await loadSecrets(ctx, vars);
    }
  });

  // On-demand key requests from other extensions. pi's event bus is
  // fire-and-forget — emit() returns void and handlers are never awaited — so
  // the requester subscribes to the reply channel before it emits, and the
  // answer comes back there once the loads settle.
  //
  // This is what replaced the startup load of OMNIROUTE_API_KEY: that key backs
  // the deferred "rpi" provider in local-model-discovery.ts, whose registered
  // api key is `$OMNIROUTE_API_KEY` — pi resolves it from process.env at
  // refresh/request time, so the var only has to be filled when a refresh
  // command actually runs. force: the request is always user-initiated, so a
  // stale failure must not be swallowed by the back-off; silent: the requester
  // reports the outcome in its own command UX.
  pi.events.on("secrets:ensure", async (data) => {
    const requested = (data as { envVars?: unknown } | undefined)?.envVars;
    if (!Array.isArray(requested)) return;
    const envVars = requested.filter((v): v is string => typeof v === "string");
    if (envVars.length === 0) return;
    const results = await loadSecrets(busCtx, envVars, { force: true, silent: true });
    pi.events.emit("secrets:ensured", {
      envVars,
      failed: results.filter((r) => !r.ok).map((r) => ({ envVar: r.envVar, reason: r.reason })),
    });
  });
}
