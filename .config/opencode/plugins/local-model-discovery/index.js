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
 *  - the catalog is fetched ONCE, in setup() at startup. No polling: the
 *    endpoint is only queried when OpenCode starts. (The server may swap its
 *    resident model afterwards; the published catalog stays as discovered.)
 *  - reasoning levels: llama-swap never advertises them on its own — its
 *    `capabilities` block has no reasoning key — so they are declared in the
 *    homepc config as a per-model `metadata:` block and read back from
 *    `meta.llamaswap.reasoning` (see ~/.config/nixos/homepc/NOTES.md
 *    § llama-swap/reasoning). Editing this file reloads the plugin, which
 *    re-fetches the catalog: after a llama-swap config change, touch a comment
 *    here (or /reload) to pick up the new advertisement.
 *
 * Configuration (all optional):
 *   "plugin": [{ "package": "./plugins/local-model-discovery",
 *                "options": { "providerId": "local",
 *                             "baseUrl": "http://localhost:8080/v1" } }]
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

/**
 * Discovery writes its own trail: OpenCode forwards plugin `console.*` output
 * nowhere — verified 2026-11-20, the `efforts.map` crash that emptied the whole
 * provider produced zero lines in ~/.local/share/opencode/log/opencode.log and
 * zero on stderr. Same habit as the pi twin
 * (~/.pi/agent/extensions/local-model-discovery.ts).
 */
const LOG_FILE = path.join(
  process.env.XDG_STATE_HOME ?? path.join(os.homedir(), ".local", "state"),
  "opencode",
  "logs",
  "local-model-discovery.log",
);

function log(message) {
  try {
    fs.mkdirSync(path.dirname(LOG_FILE), { recursive: true });
    fs.appendFileSync(LOG_FILE, `${new Date().toISOString()} ${message}\n`);
  } catch {
    // Logging must never be the reason discovery fails.
  }
}

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
 * (Splash) either on the record itself or — for llama-swap — inside
 * `meta.llamaswap`, where the server copies the per-model `metadata:` block
 * verbatim (homepc declares `reasoning = { thinks, efforts, default }` there
 * in ~/.config/nixos/homepc/configuration.nix), a bare `true`, or nothing at
 * all. Returns `{ efforts, defaultEffort }`, or undefined when the model does
 * not advertise reasoning.
 */
function extractReasoning(model) {
  const reasoning = model?.meta?.llamaswap?.reasoning ?? model?.reasoning;
  if (reasoning === true) return { efforts: [], defaultEffort: undefined };
  if (reasoning && reasoning.thinks === true) {
    return {
      efforts: Array.isArray(reasoning.efforts)
        ? reasoning.efforts.filter((effort) => typeof effort === "string")
        : [],
      defaultEffort:
        typeof reasoning.default === "string" ? reasoning.default : undefined,
    };
  }
  return undefined;
}

/** Turn one /v1/models entry into an OpenCode V2 model record. */
function toModelInfo(providerID, options, raw) {
  const context = extractContextSize(raw);
  // `reasoning` is `{ efforts, defaultEffort }` (or undefined); `efforts` is the
  // array of level names. Kept apart on purpose: the 2026-11-20 "xhigh default"
  // change made extractReasoning return an object while these call sites still
  // treated it as the array, so `efforts.map(...)` threw inside discoverModels,
  // the catch in setup() swallowed it, and NOTHING was published — the provider
  // went empty rather than failing loudly.
  const reasoning = extractReasoning(raw);
  const efforts = reasoning?.efforts ?? [];

  return {
    id: raw.id,
    modelID: raw.id,
    providerID,
    name: raw.name ?? raw.id,
    package: options.package,
    // The endpoint that served this record, so the request layer cannot pick a
    // different one than discovery used. `reasoningEffort` here is the model
    // default applied to every request unless a variant overrides it: the
    // openai-compatible package flattens it to `reasoning_effort` in the body
    // (shape fixed in OpenCode 2.0 — anomalyco/opencode#48183).
    settings: {
      baseURL: options.baseURL,
      ...(reasoning?.defaultEffort !== undefined && {
        reasoningEffort: reasoning.defaultEffort,
      }),
    },
    capabilities: {
      tools: true,
      input: extractInputTypes(raw),
      output: ["text"],
      // No `reasoning` key here: it is a *config* shape (Config.Model.Reasoning,
      // which OpenCode expands into variants itself), not a field of
      // Model.Capabilities — publishing it would be stripped by the schema.
      // The variants below are what make `/variant` offer the levels.
    },
    // Reasoning streams in the OpenAI Chat `delta.reasoning_content` field.
    ...(reasoning !== undefined && {
      compatibility: { reasoningField: "reasoning_content" },
    }),
    // One variant per advertised thinking effort: `local/<model>#low`, …
    variants: efforts.map((effort) => ({
      id: effort,
      settings: { reasoningEffort: effort },
    })),
    // Models are listed ordered by release date; `0` would pin locals dead-last in
    // pickers. Use the server-advertised `created` (epoch seconds, OpenAI
    // convention) or the discovery time.
    time: {
      released:
        typeof raw.created === "number" && raw.created > 0 ? raw.created * 1000 : Date.now(),
    },
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

/**
 * Fetch + map, keeping the two failure kinds apart:
 *  - the endpoint being down/unreadable is normal operation (llama-swap may not
 *    be up yet), so it returns undefined and the caller keeps the old catalog.
 *  - a failure while mapping the records is a bug in this file. Rethrowing it
 *    out of setup() makes OpenCode log a plugin error; swallowing it instead
 *    empties the provider silently, which is how the 2026-11-20 regressions
 *    looked like "the local models disappeared" with nothing in the log.
 */
async function tryDiscover(baseURL, providerID, options) {
  let payload;
  try {
    const response = await fetch(`${baseURL.replace(/\/+$/, "")}/models`, {
      signal: AbortSignal.timeout(FETCH_TIMEOUT_MS),
    });
    if (!response.ok) {
      throw new Error(`${response.status} ${response.statusText}`);
    }
    payload = await response.json();
  } catch (error) {
    log(
      `could not read models from ${baseURL}: ${error?.message ?? error}`,
    );
    return undefined;
  }

  const records = (Array.isArray(payload?.data) ? payload.data : []).filter(
    (model) => typeof model?.id === "string" && model.id.length > 0,
  );
  try {
    return records.map((model) => toModelInfo(providerID, options, model));
  } catch (error) {
    log(
      `BUG: failed to map ${records.length} record(s) from ${baseURL}: ${
        error?.stack ?? error
      }`,
    );
    console.error(
      `[local-model-discovery] failed to map ${records.length} record(s) from ${baseURL}: ${
        error?.stack ?? error
      }`,
    );
    throw error;
  }
}

export default Plugin.define({
  id: "local-model-discovery",

  async setup(ctx) {
    const providerID =
      typeof ctx.options?.providerId === "string" && ctx.options.providerId.length > 0
        ? ctx.options.providerId
        : DEFAULT_PROVIDER_ID;

    // Endpoint priority: plugin options, then opencode.json, then the default.
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
        models = await tryDiscover(baseURL, providerID, options);
      } catch (error) {
        // Already reported by tryDiscover; leave the provider untouched.
        return;
      }
      if (models === undefined || models.length === 0) return;

      const next = `${baseURL}\u0000${fingerprint(models)}`;
      if (next === published) return;
      published = next;

      await ctx.provider.transform((editor) => {
        editor.models.set(providerID, models);
      });
      await ctx.provider.reload();

      // An empty catalog here is what "the plugin stopped working" looks like.
      log(
        `published ${models.length} model(s) for "${providerID}" from ${baseURL}: ` +
          models
            .map(
              (model) =>
                `${model.id} ctx=${model.limit.context} variants=[${model.variants
                  .map((variant) => variant.id)
                  .join(",")}]` +
                (model.settings.reasoningEffort
                  ? ` default=${model.settings.reasoningEffort}`
                  : ""),
            )
            .join(" | "),
      );
    };

    // One fetch at startup, nothing afterwards: setup() runs once per process.
    await refresh();
  },
});
