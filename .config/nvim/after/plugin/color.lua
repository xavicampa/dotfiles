-- require('catppuccin').setup {
--     flavour = "frappe",
-- }

require("dracula").setup {
    italic_comment = true,
}

require('lualine').setup {
  options = {
    theme = 'dracula-nvim'
  }
}

vim.opt.termguicolors = true
-- vim.opt.background = 'dark'

-- vim.g.gruvbox_italic = 1
-- vim.g.gruvbox_contrast_dark = 'soft'

-- vim.g.tokyonight_transparent = 1
-- vim.g.tokyonight_style = 'night'

-- vim.g.lightline = { colorscheme = 'tokyonight' }
-- vim.g.lightline = { colorscheme = 'gruvbox' }
-- vim.g.lightline = { colorscheme = 'catppuccin' }

-- vim.api.nvim_exec([[
-- augroup MyColors
-- 	autocmd!
-- 	autocmd ColorScheme * highlight LineNr guifg=#5081c0   | highlight CursorLineNR guifg=#FFba00
-- augroup END
-- ]], false)

-- Colorscheme
-- vim.cmd([[colorscheme gruvbox]])
-- vim.cmd([[colorscheme gruvbox]])
-- vim.cmd([[colorscheme tokyonight]])
-- vim.cmd([[colorscheme tokyonight]]) -- called twice for indent-blankline to pick up the colors?
-- vim.cmd([[colorscheme catppuccin]])
-- vim.cmd([[colorscheme catppuccin]])
-- vim.cmd([[Catppuccin mocha]])

vim.cmd([[colorscheme dracula]])
vim.cmd([[colorscheme dracula]])
