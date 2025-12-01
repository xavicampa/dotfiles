-- Neovim key mappings configuration
-- This file defines custom keybindings for various plugins and Neovim features

-- Common options for key mappings: non-recursive and silent
local opts = { noremap = true, silent = true }

-- ESC key mapping: use 'jk' to exit insert mode
vim.api.nvim_set_keymap("i", "jk", "<ESC>", opts)

-- Navigate diagnostics: jump to previous/next diagnostic
vim.keymap.set('n', '<C-p>', function() vim.diagnostic.jump({ count = -1 }) end, opts)
vim.keymap.set('n', '<C-n>', function() vim.diagnostic.jump({ count = 1 }) end, opts)

-- Formatting: format the current buffer using LSP
vim.keymap.set('n', '<Space>f', function() vim.lsp.buf.format() end, opts)

-- Telescope: file search, grep, buffers, help
vim.keymap.set("n", "<leader>ff", ":Telescope find_files<CR>", opts)
vim.keymap.set("n", "<leader>fg", ":Telescope live_grep<CR>", opts)
vim.keymap.set("n", "<leader>fb", ":Telescope buffers<CR>", opts)
vim.keymap.set("n", "<leader>fh", ":Telescope help_tags<CR>", opts)

-- opencode.nvim: select text in normal or visual mode for LLM interaction
vim.keymap.set({ "n", "x" }, "<leader>oo", function() require("opencode").select() end, opts)
vim.keymap.set({ "n", "x" }, "<leader>oa", function() require("opencode").ask("@buffer: ", {submit = true}) end, opts)

-- trouble: toggle diagnostics, symbols, LSP references, etc.
vim.keymap.set("n", "<leader>xx", "<cmd>Trouble diagnostics toggle focus=true<cr>", opts)
vim.keymap.set("n", "<leader>xX", "<cmd>Trouble diagnostics toggle filter.buf=0<cr>", opts)
vim.keymap.set("n", "<leader>cs", "<cmd>Trouble symbols toggle focus=false<cr>", opts)
vim.keymap.set("n", "<leader>cl", "<cmd>Trouble lsp toggle focus=false win.position=right<cr>", opts)
vim.keymap.set("n", "<leader>xL", "<cmd>Trouble loclist toggle<cr>", opts)
vim.keymap.set("n", "<leader>xQ", "<cmd>Trouble qflist toggle<cr>", opts)

-- llm.nvim (copilot): custom Tab behavior for LLM completions
-- vim.keymap.set("i", "<Tab>", function()
--     local llm = require('llm.completion')
--
--     -- If there's an LLM suggestion visible, accept it
--     if llm.shown_suggestion ~= nil then
--       llm.complete()
--     else
--       -- Otherwise, insert a regular Tab character
--       local keys = vim.api.nvim_replace_termcodes('<Tab>', true, false, true)
--       vim.api.nvim_feedkeys(keys, 'n', false)
--     end
--   end,
--   { noremap = true, silent = true })
