return {
  "carlos-algms/agentic.nvim",
  event = "VeryLazy",
  opts = {
    -- llama-swap, bridged through OpenCode's ACP mode (reuses the
    -- `local` provider in ~/.config/opencode + local-model-discovery plugin)
    provider = "opencode-acp",

    -- Built-in definitions already work as-is:
    --   opencode-acp -> `opencode acp`  (models: local/qwen3.8-flash-next (alias, pinned as
    --                opencode's default), local/qwen3.8-flash-next-iq3_s*, glm-5.3-flash-maya-s24)
    --   kiro-acp     -> `kiro-cli acp`  (uses the logged-in kiro-cli session)
    -- Override here only if you ever need absolute paths or extra env.

    -- Provider switcher shows only installed CLIs (hides claude/gemini/cursor/...)
    provider_switcher = { hide_unhealthy_providers = true },
  },
  -- Portable on both Linux-XKB and macOS Norwegian layouts: only unshifted,
  -- Option-free physical keys (`,` and `.` sit in the same place on both).
  -- macOS NO has no Ctrl-reachable `\` (it's ⌥⇧7) or straight `'` at all.
  keys = {
    { "<C-,>",     function() require("agentic").toggle() end,                          desc = "Toggle Agentic Chat",               mode = { "n", "v", "i" } },
    { "<C-.>",     function() require("agentic").new_session() end,                     desc = "New Agentic session",               mode = { "n", "v", "i" } },
    { "<leader>ac", function() require("agentic").add_selection_or_file_to_context() end, desc = "Add selection/file to Agentic context", mode = { "n", "v" } },
  },
}
