/**
 * Auto-discover models from the local OpenAI-compatible API.
 * Replaces the static "local" provider definition in models.json.
 */

import type { ExtensionAPI } from "@earendil-works/pi-coding-agent";
import { readFileSync } from "fs";
import { resolve, dirname } from "path";
import { fileURLToPath } from "url";

const BASE_URL = "http://localhost:8080/v1";

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
    console.log(`[local-model-discovery] Loaded overrides for ${overrides.size} models`);
  } catch (err) {
    // No config file — use defaults
    if ((err as NodeJS.ErrnoException)?.code !== "ENOENT") {
      console.error(`[local-model-discovery] Failed to read overrides:`, err);
    }
  }

  return overrides;
}

function extractContextSize(status: Record<string, unknown>): number {
  // Try meta.n_ctx first (available for loaded models)
  const meta = (status as any)?.meta;
  if (typeof meta?.n_ctx === "number") return meta.n_ctx;

  // Fall back to parsing --ctx-size from status args
  const args = (status as any)?.args as string[] | undefined;
  if (Array.isArray(args)) {
    const idx = args.indexOf("--ctx-size");
    if (idx >= 0 && idx + 1 < args.length) {
      const parsed = parseInt(args[idx + 1], 10);
      if (!isNaN(parsed)) return parsed;
    }
  }

  return 128000; // sensible default for GGUF models
}

function extractInputTypes(architecture: Record<string, unknown>): ("text" | "image")[] {
  const modalities = (architecture as any)?.input_modalities as string[] | undefined;
  if (Array.isArray(modalities) && modalities.length > 0) {
    return modalities.filter((m: string) => m === "text" || m === "image") as ("text" | "image")[];
  }
  return ["text"];
}

export default async function (pi: ExtensionAPI) {
  try {
    const response = await fetch(`${BASE_URL}/models`);
    if (!response.ok) {
      console.error(`[local-model-discovery] Failed to fetch models: ${response.status} ${response.statusText}`);
      return;
    }

    const payload = (await response.json()) as {
      data: Array<{
        id: string;
        name?: string;
        status?: Record<string, unknown>;
        architecture?: Record<string, unknown>;
        meta?: Record<string, unknown>;
      }>;
    };

    const overrides = loadModelOverrides();

    const models = payload.data.map((model) => {
      const override = overrides.get(model.id) ?? {};
      const reasoning = override.reasoning ?? true;
      const maxTokens = override.maxTokens ?? 16384;
      const thinkingFormat = override.thinkingFormat ?? "qwen-chat-template";
      const supportsReasoningEffort = override.supportsReasoningEffort ?? false;

      return {
        id: model.id,
        name: model.name ?? model.id,
        reasoning,
        input: extractInputTypes(model.architecture ?? {}),
        cost: { input: 0, output: 0, cacheRead: 0, cacheWrite: 0 },
        contextWindow: extractContextSize(model.status ?? {}),
        maxTokens,
        compat: {
          supportsDeveloperRole: true,
          supportsReasoningEffort,
          thinkingFormat: thinkingFormat ?? undefined,
        },
      };
    });

    pi.registerProvider("local", {
      baseUrl: BASE_URL,
      apiKey: "not-needed",
      api: "openai-completions",
      compat: {
        supportsDeveloperRole: true,
        supportsReasoningEffort: false,
      },
      models,
    });

    console.log(`[local-model-discovery] Registered ${models.length} models from ${BASE_URL}`);
  } catch (err) {
    console.error(`[local-model-discovery] Error discovering models:`, err);
  }
}
