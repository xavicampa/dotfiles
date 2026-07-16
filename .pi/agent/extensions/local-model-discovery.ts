/**
 * Auto-discover models from local OpenAI-compatible APIs.
 * Registers the "local" (localhost:8080) and "rpi" (rpi:20128) providers.
 */

import type { ExtensionAPI } from "@earendil-works/pi-coding-agent";
import { readFileSync } from "fs";
import { resolve, dirname } from "path";
import { fileURLToPath } from "url";

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
      console.log(`[local-model-discovery] Loaded overrides for ${overrides.size} models`);
    }
  } catch (err) {
    if ((err as NodeJS.ErrnoException)?.code !== "ENOENT") {
      console.error(`[local-model-discovery] Failed to read overrides: ${(err as Error)?.message ?? err}`);
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
    return model.input_modalities.filter((m) => m === "text" || m === "image") as ("text" | "image")[];
  }
  if (model.capabilities?.vision) return ["text", "image"];
  return ["text"];
}

// ---------------------------------------------------------------------------
// Generic discovery
// ---------------------------------------------------------------------------

type Confirm = (title: string, message: string) => Promise<boolean>;

function buildModels(provider: ProviderConfig, data: any[]): any[] {
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

async function discoverAndRegister(
  pi: ExtensionAPI,
  provider: ProviderConfig,
  confirm?: Confirm,
  maxRetries = 3,
): Promise<{ count: number; reason?: string }> {
  const tag = `[${provider.id}-model-discovery]`;
  const RETRY_DELAY_MS = 2000;
  let lastReason: string | undefined;

  for (let attempt = 0; attempt < maxRetries; attempt++) {
    try {
      const response = await fetch(`${provider.baseUrl}/models`, {
        headers: provider.apiKey !== "not-needed"
          ? { Authorization: `Bearer ${provider.apiKey}` }
          : {},
      });

      if (!response.ok) {
        lastReason = `${response.status} ${response.statusText}`;
        console.error(`${tag} Failed to fetch models (attempt ${attempt + 1}/${maxRetries}): ${lastReason}`);
        if (confirm) {
          const retry = await confirm(`${provider.label} model discovery failed`, `${provider.baseUrl}: ${lastReason} — retry?`);
          if (!retry) return { count: -1, reason: lastReason };
        } else {
          await new Promise((r) => setTimeout(r, RETRY_DELAY_MS * (attempt + 1)));
        }
        continue;
      }

      const payload = (await response.json()) as { data: any[] };
      const models = buildModels(provider, payload.data);

      pi.registerProvider(provider.id, {
        baseUrl: provider.baseUrl,
        apiKey: provider.apiKey,
        api: "openai-completions",
        compat: { supportsDeveloperRole: true, supportsReasoningEffort: false },
        models,
      });

      console.log(`${tag} Registered ${models.length} models from ${provider.baseUrl}`);
      return { count: models.length };
    } catch (err) {
      lastReason = (err as Error)?.message ?? String(err);
      console.error(`${tag} Error discovering models (attempt ${attempt + 1}/${maxRetries}): ${lastReason}`);
      if (confirm) {
        const retry = await confirm(`${provider.label} model discovery failed`, `${provider.baseUrl}: ${lastReason} — retry?`);
        if (!retry) return { count: -1, reason: lastReason };
      } else {
        await new Promise((r) => setTimeout(r, RETRY_DELAY_MS * (attempt + 1)));
      }
    }
  }

  console.error(`${tag} Failed after ${maxRetries} attempts`);
  return { count: -1, reason: lastReason };
}

async function discoverWithFallback(
  pi: ExtensionAPI,
  provider: ProviderConfig,
  onFailure: (p: ProviderConfig, reason: string) => void,
): Promise<void> {
  const { count, reason } = await discoverAndRegister(pi, provider, /* confirm */ undefined, 1);
  if (count <= 0) {
    console.error(`[${provider.id}-model-discovery] Startup failed, will prompt on session_start`);
    onFailure(provider, reason ?? "connection failed");
  }
}

// ---------------------------------------------------------------------------
// Entry point
// ---------------------------------------------------------------------------

export default async function (pi: ExtensionAPI) {
  const failedProviders: Array<{ provider: ProviderConfig; reason: string }> = [];

  // Refresh command
  pi.registerCommand("refresh-local-models", {
    description: "Re-discover and refresh models from all local APIs",
    handler: async (_args, ctx) => {
      ctx.ui.setStatus("local-models", "Refreshing models...");
      for (const provider of PROVIDERS) {
        pi.unregisterProvider(provider.id);
        const { count } = await discoverAndRegister(pi, provider, (title, msg) => ctx.ui.confirm(title, msg));
        if (count > 0) {
          ctx.ui.notify(`Refreshed ${count} ${provider.label} models`, "info");
        } else {
          ctx.ui.notify(`Failed to refresh ${provider.label} models`, "error");
        }
      }
      ctx.ui.setStatus("local-models", "");
    },
  });

  // Single attempt per provider at startup (no UI yet)
  await Promise.all(
    PROVIDERS.map((provider) => discoverWithFallback(pi, provider, (p, r) => failedProviders.push({ provider: p, reason: r }))),
  );

  // For any that failed, prompt once the TUI is up
  if (failedProviders.length > 0) {
    pi.on("session_start", async (_event, ctx) => {
      if (!ctx.hasUI) return;
      for (const { provider, reason } of failedProviders) {
        const retry = await ctx.ui.confirm(
          `${provider.label} model discovery failed`,
          `${provider.baseUrl}: ${reason} — retry?`,
        );
        if (!retry) continue;
        const { count } = await discoverAndRegister(pi, provider, (title, msg) => ctx.ui.confirm(title, msg));
        if (count > 0) {
          ctx.ui.notify(`Registered ${count} ${provider.label} models`, "info");
        } else {
          ctx.ui.notify(`${provider.label} model discovery failed`, "error");
        }
      }
    });
  }
}
