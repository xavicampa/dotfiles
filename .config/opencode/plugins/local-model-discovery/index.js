/**
 * Auto-discover models from a local OpenAI-compatible API.
 *
 * Ported to the OpenCode 2.x (V2) plugin API:
 *  - the default export is a plugin definition with an `id` and a `setup(ctx)`
 *    function. The V1 shape (`export default async (ctx) => ({ hooks })`) is
 *    rejected at load time by V2 with
 *    "Plugin must export a default definition with an id and an effect or setup
 *    function" / SchemaError(Expected object at ["default"]);
 *  - models are published through `ctx.provider.transform(...)` instead of
 *    mutating a config object from a V1 `config` hook.
 *
 * OpenCode ships built-in discovery for Ollama, LM Studio and vLLM only.
 * llama.cpp / llama-swap are not auto-discovered, so this plugin reads
 * `${baseURL}/models` and publishes the result as the provider's catalog.
 */
import { define } from "@opencode-ai/plugin/v2/promise";

const DEFAULT_PROVIDER_ID = "llamacpp";
const DEFAULT_BASE_URL = "http://localhost:8080/v1";
const DEFAULT_CONTEXT = 131072;
const MAX_OUTPUT_TOKENS = 65536;
const FETCH_TIMEOUT_MS = 10000;

/** Read the served context window from a llama.cpp-style model record. */
function extractContextSize(model) {
  const status = model?.status ?? {};

  // `meta.n_ctx` lives at the top level of the /v1/models entry, but some
  // routers nest it under `status`.
  for (const meta of [model?.meta, status?.meta]) {
    if (typeof meta?.n_ctx === "number") return meta.n_ctx;
  }

  // llama.cpp launch-args fallback.
  const args = model?.args ?? status?.args;
  if (Array.isArray(args)) {
    const withEquals = args.find(
      (arg) => typeof arg === "string" && arg.startsWith("--ctx-size="),
    );
    if (withEquals) {
      const parsed = parseInt(withEquals.split("=")[1], 10);
      if (!Number.isNaN(parsed)) return parsed;
    }
    const index = args.indexOf("--ctx-size");
    if (index >= 0 && index + 1 < args.length) {
      const parsed = parseInt(args[index + 1], 10);
      if (!Number.isNaN(parsed)) return parsed;
    }
  }

  // llama-swap / vLLM spellings.
  for (const field of ["context_length", "max_model_len", "n_ctx"]) {
    for (const source of [model, status]) {
      const value = source?.[field];
      if (typeof value === "number" && Number.isInteger(value) && value > 0) {
        return value;
      }
    }
  }

  return DEFAULT_CONTEXT;
}

/** Read the input modalities advertised by a llama.cpp-style model record. */
function extractInputTypes(model) {
  const modalities = model?.architecture?.input_modalities;
  if (Array.isArray(modalities) && modalities.length > 0) {
    return modalities.filter((m) => m === "text" || m === "image");
  }
  return ["text"];
}

/** Turn one /v1/models entry into an OpenCode V2 model definition. */
function toModelInfo(providerID, providerPackage, raw) {
  const context = extractContextSize(raw);
  return {
    id: raw.id,
    modelID: raw.id,
    providerID,
    name: raw.name ?? raw.id,
    api: {
      id: "openai-completions",
      type: "aisdk",
      package: providerPackage,
      settings: {},
    },
    capabilities: {
      tools: true,
      input: extractInputTypes(raw),
      output: ["text"],
    },
    request: { headers: {}, body: {} },
    variants: [],
    time: { released: 0 },
    cost: [],
    status: "active",
    enabled: true,
    limit: {
      context,
      output: Math.min(Math.floor(context / 2), MAX_OUTPUT_TOKENS),
    },
  };
}

async function discoverModels(baseURL, providerID, providerPackage) {
  const response = await fetch(`${baseURL.replace(/\/+$/, "")}/models`, {
    signal: AbortSignal.timeout(FETCH_TIMEOUT_MS),
  });

  if (!response.ok) {
    throw new Error(`${baseURL}: ${response.status} ${response.statusText}`);
  }

  const payload = await response.json();
  const data = Array.isArray(payload?.data) ? payload.data : [];

  return data
    .filter((model) => typeof model?.id === "string" && model.id.length > 0)
    .map((model) => toModelInfo(providerID, providerPackage, model));
}

export default define({
  id: "local-model-discovery",

  async setup(ctx) {
    const providerID = ctx.options?.providerId ?? DEFAULT_PROVIDER_ID;

    // The provider itself stays declared in opencode.json; this plugin only
    // fills in its model inventory. Read the endpoint from the provider so a
    // non-default baseURL keeps working.
    let provider;
    try {
      provider = await ctx.provider.get({ providerID });
    } catch {
      provider = undefined;
    }

    const baseURL =
      provider?.settings?.baseURL ??
      provider?.api?.settings?.baseURL ??
      DEFAULT_BASE_URL;
    const providerPackage =
      provider?.package ??
      provider?.api?.package ??
      "@ai-sdk/openai-compatible";

    let models;
    try {
      models = await discoverModels(baseURL, providerID, providerPackage);
    } catch (error) {
      console.warn(
        `[local-model-discovery] could not discover models at ${baseURL}: ${
          error?.message ?? error
        }`,
      );
      return;
    }

    if (models.length === 0) return;

    await ctx.provider.transform((editor) => {
      editor.models.set(providerID, models);
    });
    await ctx.provider.reload();
  },
});
