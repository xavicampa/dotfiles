return {
    {
        "klen/nvim-config-local",
        opts = {},
    },
    {
        "mason-org/mason.nvim",
        version = "^1.0.0",
        opts = {},
    },
    {
        "mfussenegger/nvim-dap",
        keys = {
            { '<leader>db', '<cmd>DapToggleBreakpoint<CR>' },
            { '<leader>dn', '<cmd>DapNew<CR>' },
            { '<leader>dc', '<cmd>DapContinue<CR>' },
            { '<leader>dt', '<cmd>DapTerminate<CR>' },
            { '<leader>dl', '<cmd>DapStepInto<CR>' },
            { '<leader>dh', '<cmd>DapStepOut<CR>' },
            { '<leader>dj', '<cmd>DapStepOver<CR>' },
        },
    },
    "folke/which-key.nvim",
    {
        "saghen/blink.cmp",
        version = '1.*',
        opts = {}
    },
    "onsails/lspkind.nvim",
    "pedrohdz/vim-yaml-folds",
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
        opts = {}
    },
    {
        "lewis6991/gitsigns.nvim",
        opts = {},
    },
    {
        "phaazon/hop.nvim",
        keys = {
            { "s", "<cmd>lua require'hop'.hint_char1()<CR>" },
        },
        opts = {},
    },
    "kdheepak/lazygit.nvim",
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
}
