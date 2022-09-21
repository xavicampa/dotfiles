-- Colorscheme
vim.opt.termguicolors=true
vim.opt.background='dark'
-- vim.g.tokyonight_transparent=1
vim.g.tokyonight_style='storm'
vim.g.lightline={ colorscheme='tokyonight' }
vim.cmd([[colorscheme tokyonight]])
vim.cmd([[colorscheme tokyonight]]) -- called twice for indent-blankline to pick up the colors?
