vim.g.mapleader = ','

-- vim.o.ch = 0    -- command height

vim.opt.encoding = 'utf-8'
vim.opt.number = true
vim.opt.relativenumber = true
vim.opt.hlsearch = true
vim.opt.incsearch = true
vim.opt.scrolloff = 8
vim.opt.swapfile = false
vim.opt.wrap = false
vim.opt.showmode = false
vim.opt.wildmenu = true
vim.opt.wildmode = 'longest:full,full'
vim.opt.tabstop = 4
vim.opt.softtabstop = -1
vim.opt.shiftwidth = 0
vim.opt.expandtab = true
vim.opt.autoindent = true
vim.opt.smartindent = true
vim.opt.winborder = 'rounded'
-- vim.opt.spell = true

-- Mouse
vim.opt.mouse = 'a'

-- Clipboard
vim.opt.clipboard = 'unnamed,unnamedplus'

-- Folding
vim.opt.foldmethod = 'expr'
vim.opt.foldexpr = 'nvim_treesitter#foldexpr()'
-- vim.opt.completeopt = 'menu,menuone,noselect'
vim.opt.foldlevelstart = 2

-- Diagnostics
vim.diagnostic.config({
    signs = {
        text = {
            [vim.diagnostic.severity.ERROR] = '',
            [vim.diagnostic.severity.WARN] = '',
            [vim.diagnostic.severity.HINT] = '',
            [vim.diagnostic.severity.INFO] = ''
        }
    },
    severity_sort = true,
    virtual_lines = true,
})
