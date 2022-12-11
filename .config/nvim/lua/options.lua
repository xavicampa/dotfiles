vim.g.mapleader = ','

vim.o.ch = 0    -- command height

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
vim.opt.spell = true

-- Mouse
vim.opt.mouse = 'a'

-- Clipboard
vim.opt.clipboard = 'unnamed,unnamedplus'

-- Folding
vim.opt.foldmethod = 'expr'
vim.opt.foldexpr = 'nvim_treesitter#foldexpr()'
vim.opt.completeopt = 'menu,menuone,noselect'

-- Diagnostics
vim.diagnostic.config({
    severity_sort = true,
    virtual_text = false,
    float = {
        border = 'rounded'
    }
})

-- nerdtree workaround
vim.g.NERDTreeMinimalMenu = 1
