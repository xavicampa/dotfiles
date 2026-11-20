/**
 * Filter Bedrock model variants by data-residency scope prefix.
 *
 * Bedrock catalogs the same model under several scope prefixes: `us.`,
 * `eu.`, `apac.`, `au.`, `jp.`, `in.`, `ca.`, `global.`, and unprefixed.
 *
 * Two modes, configured through plugin options in opencode.json:
 *  - "keep": keep ONLY models whose ID starts with one of these prefixes;
 *    everything else (including unprefixed) is removed.
 *  - "remove": remove models whose ID starts with one of these prefixes
 *    (default when "keep" is absent: ["us."]).
 *
 * Example — EU data residency only:
 *   { "package": "./plugins/bedrock-scope-filter", "options": { "keep": ["eu."] } }
 *
 * OpenCode replays model transforms whenever the provider catalog
 * rebuilds, so newly added out-of-scope models disappear automatically —
 * unlike per-model `disabled: true` config, which must be maintained by hand.
 */
import { Plugin } from "@opencode/plugin"

const DEFAULT_REMOVE = ["us."]

const strings = (value) => (Array.isArray(value) ? value.filter((p) => typeof p === "string") : [])

export default Plugin.define({
  id: "bedrock-scope-filter",
  async setup(ctx) {
    const keep = strings(ctx.options?.keep)
    const remove = keep.length > 0 ? [] : strings(ctx.options?.remove)
    await ctx.model.transform((editor) => {
      for (const model of editor.list("amazon-bedrock")) {
        const outOfScope =
          keep.length > 0
            ? !keep.some((prefix) => model.id.startsWith(prefix))
            : remove.length > 0
              ? remove.some((prefix) => model.id.startsWith(prefix))
              : DEFAULT_REMOVE.some((prefix) => model.id.startsWith(prefix))
        if (outOfScope) editor.remove(model.providerID, model.id)
      }
    })
  },
})
