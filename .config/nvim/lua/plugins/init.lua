return {
    "folke/which-key.nvim",
    {
        "saghen/blink.cmp",
        version = '1.*',
        opts = {}
    },
    "onsails/lspkind.nvim",
    "pedrohdz/vim-yaml-folds",
    {
        "preservim/nerdtree",
        dependencies = {
            "Deftera186/vim-devicons",
            "xuyuanp/nerdtree-git-plugin",
        },
        opts = {},
        config = function ()
            vim.api.nvim_set_keymap("n", "<C-t>", ":NERDTreeToggle<CR>", { noremap = true })
            vim.g.NERDTreeQuitOnOpen=1
            vim.g.NERDTreeGitStatusUseNerdFonts = 1
            vim.g.NERDTreeFileExtensionHighlightFullName = 1
            vim.g.NERDTreeExactMatchHighlightFullName = 1
            vim.g.NERDTreePatternMatchHighlightFullName = 1
        end
    },
    {
        "nvim-lualine/lualine.nvim",
        dependencies = {
            "nvim-tree/nvim-web-devicons",
        },
        opts = {}
    },
    {
        "nvim-telescope/telescope.nvim",
        dependencies = { "nvim-lua/plenary.nvim" },
    },
    {
        "lewis6991/gitsigns.nvim",
        opts = {},
    },
    {
        "phaazon/hop.nvim",
        init = function()
            vim.api.nvim_set_keymap('', 's', "<cmd>lua require'hop'.hint_char1()<cr>", {})
        end,
        opts = {},
    },
    "kdheepak/lazygit.nvim",
    {
        "https://git.sr.ht/~whynothugo/lsp_lines.nvim",
        opts = {},
    },
    "Hoffs/omnisharp-extended-lsp.nvim",
    {
        "folke/which-key.nvim",
        event = "VeryLazy",
        init = function()
            vim.o.timeout = true
            vim.o.timeoutlen = 300
        end,
        opts = {
            -- your configuration comes here
            -- or leave it empty to use the default settings
            -- refer to the configuration section below
        }
    },
    {
        "folke/trouble.nvim",
        opts = {},
    },
    "stevearc/dressing.nvim",
    {
        'MeanderingProgrammer/render-markdown.nvim',
        opts = {
            file_types = { "markdown", "Avante" },
        },
        ft = { "markdown", "Avante" },
        -- dependencies = { 'nvim-treesitter/nvim-treesitter', 'echasnovski/mini.nvim' }, -- if you use the mini.nvim suite
        -- dependencies = { 'nvim-treesitter/nvim-treesitter', 'echasnovski/mini.icons' }, -- if you use standalone mini plugins
        dependencies = { 'nvim-treesitter/nvim-treesitter', 'nvim-tree/nvim-web-devicons' }, -- if you prefer nvim-web-devicons
    },
    'direnv/direnv.vim',
    'psliwka/vim-smoothie',
    'mfussenegger/nvim-dap',
}
