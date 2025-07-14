local opts = { noremap = true, silent = true }

-- ESC
vim.api.nvim_set_keymap("i", "jk", "<ESC>", opts)

-- Navigate diagnostics
vim.keymap.set('n', '<C-p>', function() vim.diagnostic.jump({ count = -1 }) end, opts)
vim.keymap.set('n', '<C-n>', function() vim.diagnostic.jump({ count = 1 }) end, opts)

-- Formatting
vim.keymap.set('n', '<Space>f', function() vim.lsp.buf.format() end, opts)

-- Telescope
vim.keymap.set("n", "<leader>ff", ":Telescope find_files<CR>", opts)
vim.keymap.set("n", "<leader>fg", ":Telescope live_grep<CR>", opts)
vim.keymap.set("n", "<leader>fb", ":Telescope buffers<CR>", opts)
vim.keymap.set("n", "<leader>fh", ":Telescope help_tags<CR>", opts)

-- LazyGit
vim.keymap.set("n", "<leader>gg", ":LazyGit<CR>", opts)

-- gen.nvim (llm chat)
vim.keymap.set({ 'n', 'v' }, '<leader>oo', ':Gen<CR>', opts)

-- trouble
vim.keymap.set("n", "<leader>xx", "<cmd>Trouble diagnostics toggle focus=true<cr>", opts)
vim.keymap.set("n", "<leader>xX", "<cmd>Trouble diagnostics toggle filter.buf=0<cr>", opts)
vim.keymap.set("n", "<leader>cs", "<cmd>Trouble symbols toggle focus=false<cr>", opts)
vim.keymap.set("n", "<leader>cl", "<cmd>Trouble lsp toggle focus=false win.position=right<cr>", opts)
vim.keymap.set("n", "<leader>xL", "<cmd>Trouble loclist toggle<cr>", opts)
vim.keymap.set("n", "<leader>xQ", "<cmd>Trouble qflist toggle<cr>", opts)

-- llm.nvim (copilot)
vim.keymap.set("i", "<Tab>", function()
        local llm = require('llm.completion')

        if llm.shown_suggestion ~= nil then
            llm.complete()
        else
            local keys = vim.api.nvim_replace_termcodes('<Tab>', true, false, true)
            vim.api.nvim_feedkeys(keys, 'n', false)
        end
    end,
    { noremap = true, silent = true })
