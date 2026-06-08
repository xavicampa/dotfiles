/**
 * Auto-discover models from the RPI OpenAI-compatible API.
 * Replaces the static "rpi" provider definition in models.json.
 */

import type { ExtensionAPI } from "@earendil-works/pi-coding-agent";

const BASE_URL = "http://rpi:20128/v1";
const API_KEY = "sk-c9886c14389ac861-b2bf08-374cb9fb";

interface RpiModelRaw {
  id: string;
  name?: string;
  context_length?: number;
  max_output_tokens?: number;
  max_input_tokens?: number;
  capabilities?: {
    vision?: boolean;
    tool_calling?: boolean;
    reasoning?: boolean;
    thinking?: boolean;
  };
  input_modalities?: string[];
  output_modalities?: string[];
  parent?: string; // alias models point to their root
  type?: string; // e.g. "video"
  custom?: boolean;
}

/** Filter out aliases (have a parent) and non-chat models (e.g. video). */
function isRootChatModel(model: RpiModelRaw): boolean {
  if (model.parent) return false; // alias
  if (model.type === "video") return false; // video generation, not chat
  return true;
}

function extractInputTypes(model: RpiModelRaw): ("text" | "image")[] {
  const modalities = model.input_modalities;
  if (Array.isArray(modalities) && modalities.length > 0) {
    return modalities.filter((m) => m === "text" || m === "image") as ("text" | "image")[];
  }
  // If capabilities.vision is set, assume image support
  if (model.capabilities?.vision) {
    return ["text", "image"];
  }
  return ["text"];
}

async function discoverAndRegister(pi: ExtensionAPI): Promise<number> {
  const MAX_RETRIES = 3;
  const RETRY_DELAY_MS = 2000;

  for (let attempt = 0; attempt < MAX_RETRIES; attempt++) {
    try {
      const response = await fetch(`${BASE_URL}/models`, {
        headers: { Authorization: `Bearer ${API_KEY}` },
      });

      if (!response.ok) {
        console.error(
          `[rpi-model-discovery] Failed to fetch models (attempt ${attempt + 1}/${MAX_RETRIES}): ${response.status} ${response.statusText}`,
        );
        await new Promise((r) => setTimeout(r, RETRY_DELAY_MS * (attempt + 1)));
        continue;
      }

      const payload = (await response.json()) as {
        data: RpiModelRaw[];
      };

      const rootModels = payload.data.filter(isRootChatModel);

      const models = rootModels.map((model) => {
        const reasoning = model.capabilities?.reasoning ?? false;
        const maxTokens = model.max_output_tokens;
        const contextWindow = model.context_length ?? 200000;

        return {
          id: model.id,
          name: model.name ?? model.id,
          reasoning,
          input: extractInputTypes(model),
          cost: { input: 0, output: 0, cacheRead: 0, cacheWrite: 0 },
          contextWindow,
          ...(maxTokens && { maxTokens }),
          compat: {
            supportsDeveloperRole: true,
            supportsReasoningEffort: false,
          },
        };
      });

      pi.registerProvider("rpi", {
        baseUrl: BASE_URL,
        apiKey: API_KEY,
        api: "openai-completions",
        compat: {
          supportsDeveloperRole: true,
          supportsReasoningEffort: false,
        },
        models,
      });

      console.log(
        `[rpi-model-discovery] Registered ${models.length} models from ${BASE_URL} (${payload.data.length} total, ${payload.data.length - rootModels.length} filtered)`,
      );
      return models.length;
    } catch (err) {
      console.error(
        `[rpi-model-discovery] Error discovering models (attempt ${attempt + 1}/${MAX_RETRIES}):`,
        err,
      );
      await new Promise((r) => setTimeout(r, RETRY_DELAY_MS * (attempt + 1)));
    }
  }

  console.error(`[rpi-model-discovery] Failed after ${MAX_RETRIES} attempts`);
  return -1;
}

export default async function (pi: ExtensionAPI) {
  // Register a command to refresh the model list at runtime
  pi.registerCommand("refresh-rpi-models", {
    description: "Re-discover and refresh models from the RPI API",
    handler: async (_args, ctx) => {
      ctx.ui.setStatus("rpi-models", "Refreshing models...");
      pi.unregisterProvider("rpi");
      const count = await discoverAndRegister(pi);
      if (count > 0) {
        ctx.ui.notify(`Refreshed ${count} RPI models`, "info");
      } else {
        ctx.ui.notify("Failed to refresh RPI models", "error");
      }
      ctx.ui.setStatus("rpi-models", "");
    },
  });

  const count = await discoverAndRegister(pi);
  if (count < 0) {
    console.error("[rpi-model-discovery] Startup failed");
  }
}
