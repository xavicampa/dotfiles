/**
 * Auto-discover models from a local OpenAI-compatible LLM server.
 *
 * The provider is called `local` on purpose: the endpoint can be llama.cpp,
 * llama-swap, Splash (MLX), vLLM, Kobold, LM Studio — any server speaking the
 * OpenAI chat-completions API. OpenCode only ships discovery for Ollama, LM
 * Studio and vLLM, so this plugin reads `${baseURL}/models` and publishes the
 * result as the provider's catalog.
 *
 * Notes on the OpenCode 2.2 plugin API:
 *  - `import { Plugin } from "@opencode/plugin"` — the SDK is served by the
 *    OpenCode server itself. The old `@opencode-ai/plugin/v2/promise` alpha
 *    specifier does not resolve and fails the whole plugin load ("Cannot find
 *    package '@opencode-ai/plugin'") before any discovery runs.
 *  - the export is `Plugin.define({ id, setup(ctx) })`; models are published
 *    with `ctx.provider.transform(...)` + `ctx.provider.reload()`.
 *  - a config-declared custom provider is NOT visible to plugin transforms:
 *    `editor.get("local")` returns nothing while `editor.list()` holds the 233
 *    bundled catalog providers. `ctx.provider.get()` throws "Provider not
 *    found" at setup. So the endpoint is taken from plugin options, then from
 *    opencode.json read directly, then the default — and it is written into
 *    every published model's `settings.baseURL`, which is what the request
 *    layer actually uses, so discovery and requests cannot diverge.
 *  - setup() returns a cleanup and the catalog is re-read on a timer, because
 *    a local server swaps its resident model while OpenCode keeps running.
 *    OpenCode's own local-provider plugins do the same: 30s poll, publish on
 *    change only.
 *
 * Configuration (all optional):
 *   "plugin": [{ "package": "./plugins/local-model-discovery",
 *                "options": { "providerId": "local",
 *                             "baseUrl": "http://localhost:8080/v1",
 *                             "refreshMs": 30000 } }]
 * The endpoint may instead live in the provider entry of opencode.json
 * (`settings.baseURL`, or the older `options.baseURL`).
 */
import { Plugin } from "@opencode/plugin";
import fs from "node:fs";
import os from "node:os";
import path from "node:path";

const DEFAULT_PROVIDER_ID = "local";
const DEFAULT_BASE_URL = "http://localhost:8080/v1";
// The provider package that exports `model(modelID, settings)` for
// OpenAI-compatible chat endpoints. The legacy `@ai-sdk/openai-compatible`
// does not, and using it fails model initialisation.
const DEFAULT_PACKAGE = "@opencode/ai/providers/openai-compatible";
const DEFAULT_CONTEXT = 131072;
const MAX_OUTPUT_TOKENS = 65536;
const FETCH_TIMEOUT_MS = 10000;
// Poll the endpoint: a local server can swap the resident model, load another
// one or change its context window at any time. 0 disables polling.
const DEFAULT_REFRESH_MS = 30000;

/**
 * The endpoint declared for the provider in opencode.json: v2
 * `settings.baseURL`, or the older `options.baseURL`. Returns undefined when
 * the config has nothing usable.
 */
function providerBaseURLFromConfig(providerID) {
  const configHome =
    process.env.XDG_CONFIG_HOME ?? path.join(os.homedir(), ".config");
  for (const file of [
    process.env.OPENCODE_CONFIG,
    path.join(configHome, "opencode", "opencode.json"),
  ]) {
    if (!file) continue;
    try {
      // opencode.json may carry JSONC comments.
      const json = fs
        .readFileSync(file, "utf8")
        .replace(/\/\*[\s\S]*?\*\//g, "")
        .replace(/^\s*\/\/.*$/gm, "");
      const provider = JSON.parse(json)?.provider?.[providerID];
      for (const candidate of [provider?.settings?.baseURL, provider?.options?.baseURL]) {
        if (typeof candidate === "string" && candidate.length > 0) return candidate;
      }
    } catch {
      // Missing or unreadable config: fall through to the next candidate.
    }
  }
  return undefined;
}

/** Read the served context window from a local model record. */
function extractContextSize(model) {
  const status = model?.status ?? {};

  // `meta.n_ctx` sits at the top level of the /v1/models entry, but some
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

  // llama-swap / Splash / vLLM spellings.
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
  // llama.cpp nests modalities under `architecture`; Splash, llama-swap and
  // vLLM report them at the top level, sometimes only via a `vision` flag.
  const modalities =
    model?.architecture?.input_modalities ?? model?.input_modalities;
  if (Array.isArray(modalities) && modalities.length > 0) {
    return modalities.filter((m) => m === "text" || m === "image");
  }
  if (model?.vision === true) return ["text", "image"];
  return ["text"];
}

/**
 * The reasoning a local model advertises: `{ thinks: true, efforts, default }`
 * (Splash), a bare `true`, or nothing at all. Returns undefined when the model
 * does not advertise reasoning.
 */
function extractReasoning(model) {
  const reasoning = model?.reasoning;
  if (reasoning === true) return [];
  if (reasoning && reasoning.thinks === true) {
    return Array.isArray(reasoning.efforts)
      ? reasoning.efforts.filter((effort) => typeof effort === "string")
      : [];
  }
  return undefined;
}

/** Turn one /v1/models entry into an OpenCode V2 model record. */
function toModelInfo(providerID, options, raw) {
  const context = extractContextSize(raw);
  const efforts = extractReasoning(raw);

  return {
    id: raw.id,
    modelID: raw.id,
    providerID,
    name: raw.name ?? raw.id,
    package: options.package,
    // The endpoint that served this record, so the request layer cannot pick a
    // different one than discovery used.
    settings: { baseURL: options.baseURL },
    capabilities: {
      tools: true,
      input: extractInputTypes(raw),
      output: ["text"],
      ...(efforts !== undefined && {
        reasoning: { supported: true, effort: efforts },
      }),
    },
    // Reasoning streams in the OpenAI Chat `delta.reasoning_content` field.
    ...(efforts !== undefined && {
      compatibility: { reasoningField: "reasoning_content" },
    }),
    // One variant per advertised thinking effort: `local/<model>@low`, …
    variants: efforts?.map((effort) => ({
      id: effort,
      settings: { reasoningEffort: effort },
    })) ?? [],
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

/** Identity of a catalog, so a poll that changed nothing publishes nothing. */
function fingerprint(models) {
  return models
    .map((model) =>
      [
        model.id,
        model.limit.context,
        model.limit.output,
        (model.capabilities.input ?? []).join(","),
        (model.variants ?? []).map((variant) => variant.id).join(","),
        JSON.stringify(model.compatibility ?? null),
      ].join("~"),
    )
    .sort()
    .join("|");
}

async function discoverModels(baseURL, providerID, options) {
  const response = await fetch(`${baseURL.replace(/\/+$/, "")}/models`, {
    signal: AbortSignal.timeout(FETCH_TIMEOUT_MS),
  });

  if (!response.ok) {
    throw new Error(`${response.status} ${response.statusText}`);
  }

  const payload = await response.json();
  return (Array.isArray(payload?.data) ? payload.data : [])
    .filter((model) => typeof model?.id === "string" && model.id.length > 0)
    .map((model) => toModelInfo(providerID, options, model));
}

export default Plugin.define({
  id: "local-model-discovery",

  async setup(ctx) {
    const providerID =
      typeof ctx.options?.providerId === "string" && ctx.options.providerId.length > 0
        ? ctx.options.providerId
        : DEFAULT_PROVIDER_ID;
    const refreshMs =
      typeof ctx.options?.refreshMs === "number"
        ? ctx.options.refreshMs
        : DEFAULT_REFRESH_MS;

    // Endpoint priority, re-resolved on every cycle so editing opencode.json
    // takes effect: plugin options, then opencode.json, then the default.
    const resolveBaseURL = () =>
      (typeof ctx.options?.baseUrl === "string" && ctx.options.baseUrl.length > 0
        ? ctx.options.baseUrl
        : undefined) ??
      providerBaseURLFromConfig(providerID) ??
      DEFAULT_BASE_URL;

    let published;
    const refresh = async () => {
      const baseURL = resolveBaseURL();
      const options = {
        baseURL,
        package:
          typeof ctx.options?.package === "string" && ctx.options.package.length > 0
            ? ctx.options.package
            : DEFAULT_PACKAGE,
      };

      let models;
      try {
        models = await discoverModels(baseURL, providerID, options);
      } catch (error) {
        console.warn(
          `[local-model-discovery] could not read models from ${baseURL}: ${
            error?.message ?? error
          }`,
        );
        return;
      }
      if (models.length === 0) return;

      const next = `${baseURL}\u0000${fingerprint(models)}`;
      if (next === published) return;
      published = next;

      await ctx.provider.transform((editor) => {
        editor.models.set(providerID, models);
      });
      await ctx.provider.reload();
    };

    await refresh();

    // setup() runs once per process while the server keeps swapping models, so
    // poll and re-publish on change. Returning a cleanup is honoured by the
    // plugin host, which keeps it to one timer per plugin instance across the
    // repeated "plugin reconciliation" runs.
    const timer =
      refreshMs > 0
        ? setInterval(() => {
            refresh().catch(() => {});
          }, refreshMs)
        : undefined;

    // An endpoint change should not have to wait for the next poll — this is
    // how OpenCode's own local-provider plugins pick up config edits.
    const abort = new AbortController();
    const watching = (async () => {
      for await (const _ of ctx.event.subscribe({
        types: ["config.updated"],
        signal: abort.signal,
      })) {
        await refresh().catch(() => {});
      }
    })().catch(() => {});

    return () => {
      if (timer !== undefined) clearInterval(timer);
      abort.abort();
      void watching;
    };
  },
});
