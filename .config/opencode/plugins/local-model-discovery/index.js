/**
 * Auto-discovers models from llama.cpp /v1/models endpoint
 * and injects them into the provider config.
 */
export default async function (ctx, options = {}) {
  const providerId = options.providerId || "llamacpp";

  return {
    async config(config) {
      const provider = config.provider?.[providerId];
      if (!provider) return;

      const baseURL = provider.options?.baseURL || "http://localhost:8080/v1";

      try {
        const res = await fetch(`${baseURL}/models`);
        if (!res.ok) return;

        const data = await res.json();
        const models = {};

        for (const m of data.data || []) {
          const arch = m.architecture || {};
          const meta = m.meta || {};
          const inputModes = arch.input_modalities || ["text"];
          const outputModes = arch.output_modalities || ["text"];

          models[m.id] = {
            limit: {
              context: meta.n_ctx || 131072,
              output: meta.n_ctx || 131072,
            },
            modalities: {
              input: inputModes,
              output: outputModes,
            },
          };
        }

        provider.models = models;
      } catch {
        // silent fail — models will be empty
      }
    },
  };
}
