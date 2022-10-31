-- Colorscheme
vim.opt.termguicolors = true
vim.opt.background = 'dark'
vim.g.tokyonight_transparent = 1
vim.g.tokyonight_style = 'night'
vim.g.lightline = { colorscheme = 'tokyonight' }
vim.api.nvim_exec([[
augroup MyColors
	autocmd!
	autocmd ColorScheme * highlight LineNr guifg=#5081c0   | highlight CursorLineNR guifg=#FFba00
augroup END
]], false)
vim.cmd([[colorscheme tokyonight]])
vim.cmd([[colorscheme tokyonight]]) -- called twice for indent-blankline to pick up the colors?
