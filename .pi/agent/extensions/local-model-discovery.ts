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
 */

import type { ExtensionAPI, ProviderModelConfig } from "@earendil-works/pi-coding-agent";
import { appendFileSync, readFileSync } from "fs";
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

function loadModelOverrides(): Map<string, ModelOverride> {
  const overrides = new Map<string, ModelOverride>();
  const __dirname = dirname(fileURLToPath(import.meta.url));
  const configPath = resolve(__dirname, "local-models.json");

  try {
    const raw = readFileSync(configPath, "utf-8");
    const parsed = JSON.parse(raw) as Record<string, ModelOverride>;
    for (const [id, cfg] of Object.entries(parsed)) {
      overrides.set(id, cfg);
    }
    if (overrides.size > 0) {
      log(`Loaded overrides for ${overrides.size} models`);
    }
  } catch (err) {
    if ((err as NodeJS.ErrnoException)?.code !== "ENOENT") {
      log(`Failed to read overrides: ${(err as Error)?.message ?? err}`);
    }
  }

  return overrides;
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
    const overrides = loadModelOverrides();
    return data.map((model) => {
      const override = overrides.get(model.id) ?? {};
      const thinkingFormat = override.thinkingFormat;
      return {
        id: model.id,
        name: model.name ?? model.id,
        reasoning: override.reasoning ?? true,
        input: extractLocalInputTypes(model.architecture ?? {}),
        cost: { input: 0, output: 0, cacheRead: 0, cacheWrite: 0 },
        contextWindow: extractContextSize(model.status ?? {}),
        maxTokens: override.maxTokens ?? 16384,
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
