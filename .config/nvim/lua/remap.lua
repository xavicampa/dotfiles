local opts = { noremap = true, silent = true }

-- ESC 
vim.api.nvim_set_keymap("i", "jk", "<ESC>", opts)

-- Navigate diagnostics
vim.keymap.set('n', '<C-p>', function() vim.diagnostic.jump({ count = -1 }) end, opts)
vim.keymap.set('n', '<C-n>', function() vim.diagnostic.jump({ count = 1 }) end, opts)

-- Formatting
vim.keymap.set('n', '<Space>f', function() vim.lsp.buf.format() end, opts)
