/**
 * Auto-discover models from local OpenAI-compatible APIs.
 * Registers the "local" (localhost:8080) and "rpi" (rpi:20128) providers.
 *
 * Startup discovery happens in the (async) extension factory: pi awaits the
 * factory before it continues startup (offline model refresh + initial model
 * resolution), so the default model can be selected immediately. Each fetch
 * is bounded by a local deadline, so an unresponsive host degrades to an
 * empty initial catalog within seconds instead of hanging startup — live
 * discovery still runs later via `refreshModels` (network phase) and the
 * manual /refresh-local-models command.
 *
 * Pi invokes refreshModels twice per refresh cycle: an offline cached-state
 * phase (allowNetwork: false, never touches the network) and a network
 * phase. Failures are surfaced by pi ("Could not refresh <provider>; showing
 * cached models") instead of dialogs.
 *
 * VRAM-based local default: on a fresh session (startup or /new) where pi's
 * configured default resolved to the "local" provider, the session model is
 * switched to the tier model from local-models.json (`_vram.tiers`) that fits
 * this machine's GPUs (VRAM from all GPUs is summed; largest tier whose
 * nominal minVramGiB the detected usable VRAM satisfies, with a tolerance
 * for driver loss; falls back to the model the router currently has loaded).
 * Sessions that already contain a conversation are left untouched.
 */

import type { ExtensionAPI, ProviderModelConfig } from "@earendil-works/pi-coding-agent";
import { execFileSync } from "node:child_process";
import { appendFileSync, existsSync, readdirSync, readFileSync } from "fs";
import { homedir } from "os";
import { resolve, dirname, join } from "path";
import { fileURLToPath } from "url";

// Never use console.log/console.error from extension code in TUI mode: raw
// stdout writes interleave with the TUI's ANSI rendering and corrupt the
// screen. refreshModels is invoked by pi multiple times per session (startup
// flush, background refreshes, model-picker opens), so any log line there
// fires repeatedly. Diagnostics go to a file instead.
const LOG_FILE = join(homedir(), ".pi", "agent", "logs", "local-model-discovery.log");

function log(message: string): void {
  try {
    appendFileSync(LOG_FILE, `${new Date().toISOString()} ${message}\n`);
  } catch {
    // Logging must never break discovery.
  }
}

interface ProviderConfig {
  id: string;
  label: string;
  baseUrl: string;
  apiKey: string;
}

const PROVIDERS: ProviderConfig[] = [
  {
    id: "local",
    label: "local",
    baseUrl: "http://localhost:8080/v1",
    apiKey: "not-needed",
  },
  {
    id: "rpi",
    label: "RPI",
    baseUrl: "http://rpi:20128/v1",
    apiKey: "sk-c9886c14389ac861-b2bf08-374cb9fb",
  },
];

// Deadline for the manual /refresh-local-models command.
const MANUAL_REFRESH_TIMEOUT_MS = 15_000;

// pi calls refreshModels twice per refresh cycle: an offline
// "restore cached state" phase (allowNetwork: false) and a network phase.
// pi's internal refresh signals are unbounded, so a blackholed host would
// otherwise hang the fetch for minutes — including on the startup refresh,
// which pi awaits. Add our own deadline for the network phase.
const FETCH_TIMEOUT_MS = 10_000;

// Deadline for the startup fetch inside the async factory. Pi awaits the
// factory before startup continues, so keep this short; failures just mean
// the initial catalog is empty until the next background refresh succeeds.
const STARTUP_FETCH_TIMEOUT_MS = 4_000;

// ---------------------------------------------------------------------------
// Local-provider helpers (llama.cpp-style metadata)
// ---------------------------------------------------------------------------

interface ModelOverride {
  reasoning?: boolean;
  maxTokens?: number;
  thinkingFormat?: "qwen-chat-template" | null;
  supportsReasoningEffort?: boolean;
}

/** VRAM tier: minimum VRAM (GiB) needed to comfortably run the model. */
interface VramTier {
  minVramGiB: number;
  model: string;
}

interface LocalModelsConfig {
  overrides: Map<string, ModelOverride>;
  vramTiers: VramTier[];
}

// Reserved local-models.json key holding the VRAM tier list.
const VRAM_CONFIG_KEY = "_vram";

function loadLocalModelsConfig(): LocalModelsConfig {
  const overrides = new Map<string, ModelOverride>();
  let vramTiers: VramTier[] = [];
  const __dirname = dirname(fileURLToPath(import.meta.url));
  const configPath = resolve(__dirname, "local-models.json");

  try {
    const raw = readFileSync(configPath, "utf-8");
    const parsed = JSON.parse(raw) as Record<string, unknown>;
    const vram = parsed[VRAM_CONFIG_KEY] as { tiers?: unknown } | undefined;
    if (vram && Array.isArray(vram.tiers)) {
      vramTiers = (vram.tiers as unknown[]).filter(
        (tier): tier is VramTier =>
          typeof tier === "object" &&
          tier !== null &&
          typeof (tier as VramTier).minVramGiB === "number" &&
          typeof (tier as VramTier).model === "string",
      );
    }
    for (const [id, cfg] of Object.entries(parsed)) {
      if (id === VRAM_CONFIG_KEY) continue;
      overrides.set(id, cfg as ModelOverride);
    }
    if (overrides.size > 0 || vramTiers.length > 0) {
      log(`Loaded local-models.json: ${overrides.size} overrides, ${vramTiers.length} VRAM tiers`);
    }
  } catch (err) {
    if ((err as NodeJS.ErrnoException)?.code !== "ENOENT") {
      log(`Failed to read local-models.json: ${(err as Error)?.message ?? err}`);
    }
  }

  return { overrides, vramTiers };
}

function extractContextSize(status: Record<string, unknown>): number {
  const meta = (status as any)?.meta;
  if (typeof meta?.n_ctx === "number") return meta.n_ctx;

  const args = (status as any)?.args as string[] | undefined;
  if (Array.isArray(args)) {
    const ctxSizeArg = args.find((a: string) => a.startsWith("--ctx-size="));
    if (ctxSizeArg) {
      const parsed = parseInt(ctxSizeArg.split("=")[1], 10);
      if (!isNaN(parsed)) return parsed;
    }
    const idx = args.indexOf("--ctx-size");
    if (idx >= 0 && idx + 1 < args.length) {
      const parsed = parseInt(args[idx + 1], 10);
      if (!isNaN(parsed)) return parsed;
    }
  }

  return 128000;
}

function extractLocalInputTypes(architecture: Record<string, unknown>): ("text" | "image")[] {
  const modalities = (architecture as any)?.input_modalities as string[] | undefined;
  if (Array.isArray(modalities) && modalities.length > 0) {
    return modalities.filter((m: string) => m === "text" || m === "image") as ("text" | "image")[];
  }
  return ["text"];
}

// ---------------------------------------------------------------------------
// RPI-provider helpers (OpenRouter-style metadata)
// ---------------------------------------------------------------------------

interface RpiModelRaw {
  id: string;
  name?: string;
  context_length?: number;
  max_output_tokens?: number;
  input_modalities?: string[];
  capabilities?: { vision?: boolean; reasoning?: boolean };
  parent?: string;
  type?: string;
}

function isRootChatModel(model: RpiModelRaw): boolean {
  if (model.parent) return false;
  if (model.type === "video") return false;
  return true;
}

function extractRpiInputTypes(model: RpiModelRaw): ("text" | "image")[] {
  if (Array.isArray(model.input_modalities) && model.input_modalities.length > 0) {
    return model.input_modalities.filter((m: string) => m === "text" || m === "image") as ("text" | "image")[];
  }
  if (model.capabilities?.vision) return ["text", "image"];
  return ["text"];
}

// ---------------------------------------------------------------------------
// Discovery
// ---------------------------------------------------------------------------

function buildModels(provider: ProviderConfig, data: any[]): ProviderModelConfig[] {
  if (provider.id === "local") {
    const { overrides } = loadLocalModelsConfig();
    const loaded = (data as { id?: string; status?: { value?: string } }[]).find(
      (model) => model.status?.value === "loaded",
    );
    if (loaded?.id) lastLoadedLocalModelId = loaded.id;
    return data.map((model) => {
      const override = overrides.get(model.id) ?? {};
      const thinkingFormat = override.thinkingFormat;
      const contextWindow = extractContextSize(model.status ?? {});
      // Output-token cap: half the context window (so long prompts stay
      // usable), capped so huge contexts don't imply absurdly long outputs.
      const maxTokens = override.maxTokens ?? Math.min(Math.floor(contextWindow / 2), 65536);
      return {
        id: model.id,
        name: model.name ?? model.id,
        reasoning: override.reasoning ?? true,
        input: extractLocalInputTypes(model.architecture ?? {}),
        cost: { input: 0, output: 0, cacheRead: 0, cacheWrite: 0 },
        contextWindow,
        maxTokens,
        compat: {
          supportsDeveloperRole: true,
          supportsReasoningEffort: override.supportsReasoningEffort ?? false,
          ...(thinkingFormat !== undefined && { thinkingFormat }),
        },
      };
    });
  }

  if (provider.id === "rpi") {
    const rootModels = (data as RpiModelRaw[]).filter(isRootChatModel);
    return rootModels.map((model) => ({
      id: model.id,
      name: model.name ?? model.id,
      reasoning: model.capabilities?.reasoning ?? false,
      input: extractRpiInputTypes(model),
      cost: { input: 0, output: 0, cacheRead: 0, cacheWrite: 0 },
      contextWindow: model.context_length ?? 200000,
      ...(model.max_output_tokens && { maxTokens: model.max_output_tokens }),
      compat: { supportsDeveloperRole: true, supportsReasoningEffort: false },
    }));
  }

  return [];
}

/** Single network attempt. The caller's signal bounds and can cancel it. */
async function fetchModels(
  provider: ProviderConfig,
  signal: AbortSignal,
): Promise<ProviderModelConfig[]> {
  return fetchModelsImpl(provider, signal);
}

async function fetchModelsImpl(
  provider: ProviderConfig,
  signal: AbortSignal,
): Promise<ProviderModelConfig[]> {
  const tag = `[${provider.id}-model-discovery]`;
  const response = await fetch(`${provider.baseUrl}/models`, {
    signal,
    headers: provider.apiKey !== "not-needed"
      ? { Authorization: `Bearer ${provider.apiKey}` }
      : {},
  });

  if (!response.ok) {
    throw new Error(`${provider.baseUrl}: ${response.status} ${response.statusText}`);
  }

  const payload = (await response.json()) as { data: any[] };
  const models = buildModels(provider, payload.data);
  log(`${tag} Discovered ${models.length} models from ${provider.baseUrl}`);
  return models;
}

// ---------------------------------------------------------------------------
// Entry point
// ---------------------------------------------------------------------------

// Last successfully discovered catalog per provider. The offline refresh
// phase (allowNetwork: false) runs *after* startup registration and its
// returned list replaces the provider catalog, so it must serve the last
// known-good models instead of an empty list — otherwise the startup
// discovery done in the factory would be wiped before initial model
// resolution.
const lastDiscovered = new Map<string, ProviderModelConfig[]>();

// Model the llama.cpp router currently has loaded, from its /v1/models
// status. Fallback default when the VRAM tier's model is not in the catalog.
let lastLoadedLocalModelId: string | undefined;

// ---------------------------------------------------------------------------
// VRAM-based local default
// ---------------------------------------------------------------------------

let cachedVramGiB: number | undefined;

// Nominal card sizes lose some VRAM to the driver (a 16 GB card reports
// ~15.9 GiB, a 40 GB card a similar fraction less), so tier thresholds are
// compared against usable VRAM plus this tolerance.
const VRAM_TOLERANCE_GIB = 1;

/**
 * Detect this machine's local GPU VRAM in GiB (cached). nvidia-smi is the
 * primary source; the DRM sysfs file is the fallback. All GPUs are summed:
 * the router can split models across cards, so the total pool is what
 * matters. Returns undefined when no GPU is detectable.
 */
function detectLocalVramGiB(): number | undefined {
  if (cachedVramGiB !== undefined) return cachedVramGiB;
  try {
    const out = execFileSync(
      "nvidia-smi",
      ["--query-gpu=memory.total", "--format=csv,noheader,nounits"],
      { timeout: 3_000, stdio: ["ignore", "pipe", "ignore"] },
    ).toString();
    const values = out
      .split("\n")
      .map((line) => parseInt(line.trim(), 10))
      .filter((n) => Number.isFinite(n) && n > 0);
    if (values.length > 0) {
      cachedVramGiB = Math.round(values.reduce((sum, n) => sum + n, 0) / 1024);
      log(`Detected ${cachedVramGiB} GiB VRAM (${values.length} GPU${values.length > 1 ? "s" : ""}, nvidia-smi)`);
      return cachedVramGiB;
    }
  } catch {
    // No nvidia-smi or no NVIDIA GPU; fall through to sysfs.
  }
  try {
    let totalBytes = 0;
    for (const card of readdirSync("/sys/class/drm")) {
      if (!card.startsWith("card")) continue;
      const path = join("/sys/class/drm", card, "device", "mem_info_vram_total");
      if (!existsSync(path)) continue;
      const bytes = parseInt(readFileSync(path, "utf-8").trim(), 10);
      if (Number.isFinite(bytes) && bytes > 0) totalBytes += bytes;
    }
    if (totalBytes > 0) {
      cachedVramGiB = Math.round(totalBytes / 1024 / 1024);
      log(`Detected ${cachedVramGiB} GiB VRAM (sysfs)`);
      return cachedVramGiB;
    }
  } catch {
    // No sysfs access; leave undefined.
  }
  log("Could not detect local VRAM (no nvidia-smi result, no /sys/class/drm)");
  return undefined;
}

/**
 * Pick the default local model for this GPU: the tier with the largest
 * nominal minVramGiB the detected usable VRAM satisfies (with driver-loss
 * tolerance). Falls back to the model the router currently has loaded;
 * undefined when nothing fits.
 */
function resolvePreferredLocalModel(): string | undefined {
  const vramGiB = detectLocalVramGiB();
  if (vramGiB === undefined) return undefined;
  const { vramTiers } = loadLocalModelsConfig();
  const eligible = vramTiers.filter(
    (tier) => vramGiB + VRAM_TOLERANCE_GIB >= tier.minVramGiB,
  );
  if (eligible.length === 0) return undefined;
  const best = eligible.reduce((a, b) => (b.minVramGiB > a.minVramGiB ? b : a));
  const catalog = lastDiscovered.get("local") ?? [];
  if (catalog.some((model) => model.id === best.model)) return best.model;
  if (lastLoadedLocalModelId && catalog.some((model) => model.id === lastLoadedLocalModelId)) {
    log(`VRAM tier model ${best.model} not in local catalog; using loaded model`);
    return lastLoadedLocalModelId;
  }
  log(`VRAM tier model ${best.model} not in local catalog`);
  return undefined;
}

export default async function (pi: ExtensionAPI) {
  // Discover at startup, bounded: pi awaits the factory before the offline
  // model refresh and initial model resolution, so the configured default
  // model (e.g. local/unsloth/...) is resolvable on first launch. All
  // providers are fetched in parallel; a dead host contributes nothing
  // instead of blocking startup.
  const startupSignal = AbortSignal.timeout(STARTUP_FETCH_TIMEOUT_MS);
  const discovered = await Promise.all(
    PROVIDERS.map(async (provider) => {
      try {
        const models = await fetchModels(provider, startupSignal);
        lastDiscovered.set(provider.id, models);
        return models;
      } catch (err) {
        log(
          `[${provider.id}-model-discovery] startup discovery failed: ` +
            `${(err as Error)?.message ?? err}`,
        );
        return [];
      }
    }),
  );

  for (const [index, provider] of PROVIDERS.entries()) {
    pi.registerProvider(provider.id, {
      name: provider.label,
      baseUrl: provider.baseUrl,
      apiKey: provider.apiKey,
      api: "openai-completions",
      models: discovered[index],
      compat: { supportsDeveloperRole: true, supportsReasoningEffort: false },
      async refreshModels({ allowNetwork, stored, signal }) {
        // Offline phase: never touch the network. Serve the last known-good
        // catalog (stale is fine). Never return [] here: the returned list
        // replaces the provider catalog, and the offline phase runs after
        // startup registration.
        if (!allowNetwork) {
          return lastDiscovered.get(provider.id) ?? stored?.models ?? [];
        }
        const models = await fetchModels(
          provider,
          AbortSignal.any([signal, AbortSignal.timeout(FETCH_TIMEOUT_MS)]),
        );
        lastDiscovered.set(provider.id, models);
        return models;
      },
    });
  }

  // VRAM-based local default. Pi resolves the configured defaultModel before
  // session_start and records it as the session's initial model_change (even
  // on fresh sessions), so model_change entries can't distinguish a
  // user-picked model from the default. Instead: only swap when the session
  // has no conversation yet — continuing, resumed, and forked sessions keep
  // their own model (including any model the user picked in them).
  pi.on("session_start", async (event, ctx) => {
    const preferredId = resolvePreferredLocalModel();
    if (!preferredId) return;
    const current = ctx.model;
    if (!current || current.provider !== "local" || current.id === preferredId) return;
    const hasConversation = ctx.sessionManager
      .getBranch()
      .some((entry) => entry.type === "message");
    if (hasConversation) return;
    const model = ctx.modelRegistry.find("local", preferredId);
    if (!model) {
      log(`Preferred local model ${preferredId} not found in registry; keeping ${current.id}`);
      return;
    }
    const ok = await pi.setModel(model);
    log(
      `Session ${event.reason}: local default ${current.id} -> ${preferredId} ` +
        `(${detectLocalVramGiB()} GiB VRAM)${ok ? "" : " [setModel rejected]"}`,
    );
  });

  // Manual refresh with an explicit deadline (pi's background refreshes are
  // already bounded; this public entry point is unbounded unless signalled).
  pi.registerCommand("refresh-local-models", {
    description: "Re-discover and refresh models from all local APIs",
    handler: async (_args, ctx) => {
      ctx.ui.setStatus("local-models", "Refreshing models...");
      try {
        const result = await ctx.modelRegistry.refresh({
          allowNetwork: true,
          force: true,
          providers: PROVIDERS.map((p) => p.id),
          signal: AbortSignal.timeout(MANUAL_REFRESH_TIMEOUT_MS),
        });
        if (result.aborted) {
          ctx.ui.notify("Model refresh timed out", "error");
          return;
        }
        for (const provider of PROVIDERS) {
          const error = result.errors.get(provider.id);
          if (error) {
            ctx.ui.notify(`${provider.label} model refresh failed: ${error.message}`, "error");
          } else {
            ctx.ui.notify(`Refreshed ${provider.label} models`, "info");
          }
        }
      } catch (err) {
        ctx.ui.notify(`Model refresh failed: ${(err as Error)?.message ?? err}`, "error");
      } finally {
        ctx.ui.setStatus("local-models", "");
      }
    },
  });
}
