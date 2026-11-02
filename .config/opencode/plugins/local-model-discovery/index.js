/**
 * Auto-discover models from a local OpenAI-compatible API.
 *
 * Written for the OpenCode 2.2 (V2) plugin API:
 *  - the default export is `Plugin.define({ id, setup(ctx) })`, imported from
 *    the host-provided `@opencode/plugin` module. The SDK is served by the
 *    OpenCode server itself; the old `@opencode-ai/plugin/v2/promise` alpha
 *    specifier does not resolve and fails the whole plugin load ("Cannot find
 *    package '@opencode-ai/plugin'") before any discovery runs;
 *  - models are published through `ctx.provider.transform(...)` and
 *    `ctx.provider.reload()`.
 *
 * OpenCode ships built-in discovery for Ollama, LM Studio and vLLM only.
 * llama.cpp / llama-swap / Splash (MLX) are not auto-discovered, so this
 * plugin reads `${baseURL}/models` and publishes the result as the
 * provider's catalog.
 */
import { Plugin } from "@opencode/plugin";

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

/** Read the input modalities advertised by a local model record. */
function extractInputTypes(model) {
  // llama.cpp nests modalities under `architecture`; Splash (MLX), llama-swap
  // and vLLM report them at the top level, sometimes only via a `vision` flag.
  const modalities =
    model?.architecture?.input_modalities ?? model?.input_modalities;
  if (Array.isArray(modalities) && modalities.length > 0) {
    return modalities.filter((m) => m === "text" || m === "image");
  }
  if (model?.vision === true) return ["text", "image"];
  return ["text"];
}

/**
 * Map a local model's advertised reasoning to the V2 `compatibility` block.
 * Splash (MLX OpenAI-compatible) advertises reasoning via a top-level
 * `reasoning: { thinks: true, ... }` record and streams it in
 * `delta.reasoning_content`, so point the OpenAI-Chat reasoning field there.
 * Returns undefined for models that do not advertise reasoning.
 */
function extractCompatibility(model) {
  if (model?.reasoning && model.reasoning.thinks === true) {
    return { reasoningField: "reasoning_content" };
  }
  return undefined;
}

/** Turn one /v1/models entry into an OpenCode V2 model record. */
function toModelInfo(providerID, providerPackage, raw) {
  const context = extractContextSize(raw);
  const compatibility = extractCompatibility(raw);
  return {
    id: raw.id,
    modelID: raw.id,
    providerID,
    name: raw.name ?? raw.id,
    // `package` is only set when we resolved the provider's own SDK package.
    // Omitting it lets OpenCode inherit the provider's package (e.g.
    // `@opencode/ai/providers/openai-compatible`), which is what actually
    // exports `model(modelID, settings)`. Hardcoding the legacy
    // `@ai-sdk/openai-compatible` here breaks model initialisation.
    ...(providerPackage !== undefined && { package: providerPackage }),
    capabilities: {
      tools: true,
      input: extractInputTypes(raw),
      output: ["text"],
    },
    ...(compatibility !== undefined && { compatibility }),
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

export default Plugin.define({
  id: "local-model-discovery",

  async setup(ctx) {
    const providerID = ctx.options?.providerId ?? DEFAULT_PROVIDER_ID;

    // Explicit endpoint override from the plugin options in opencode.json:
    //   { "package": "./plugins/local-model-discovery",
    //     "options": { "baseUrl": "http://host:port/v1" } }
    // This is the reliable way to target a non-default endpoint. At plugin
    // setup time a provider declared in opencode.json is not yet in the
    // runtime registry, so `ctx.provider.get()` throws "Provider not found"
    // and the config-declared baseURL is not readable yet.
    const optionBaseURL =
      typeof ctx.options?.baseUrl === "string" && ctx.options.baseUrl.length > 0
        ? ctx.options.baseUrl
        : undefined;

    // Best effort: if the provider is already registered (later reloads),
    // read its endpoint and SDK package. ctx.provider.get() returns
    // `{ location, data: ProviderInfo }`; the endpoint and package live on
    // the data record.
    let info;
    try {
      const provider = await ctx.provider.get({ providerID });
      info = provider?.data ?? provider;
    } catch {
      info = undefined;
    }

    const baseURL =
      optionBaseURL ??
      info?.settings?.baseURL ??
      info?.options?.baseURL ??
      DEFAULT_BASE_URL;
    // When the provider's package can't be read, leave it undefined so the
    // model record omits `package` and OpenCode inherits the provider's own
    // SDK package (the one that exports `model(modelID, settings)`).
    const providerPackage = info?.package ?? info?.api?.package;

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
