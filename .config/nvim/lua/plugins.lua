local lazypath = vim.fn.stdpath("data") .. "/lazy/lazy.nvim"

if not vim.loop.fs_stat(lazypath) then
    vim.fn.system({
        "git",
        "clone",
        "--filter=blob:none",
        "https://github.com/folke/lazy.nvim.git",
        "--branch=stable", -- latest stable release
        lazypath,
    })
end
vim.opt.rtp:prepend(lazypath)

require("lazy").setup({
    "folke/which-key.nvim",
    "nvim-treesitter/nvim-treesitter",
    "neovim/nvim-lspconfig",
    "SirVer/ultisnips",
    "honza/vim-snippets",
    "quangnguyen30192/cmp-nvim-ultisnips",
    "onsails/lspkind.nvim",
    "hrsh7th/nvim-cmp",
    "hrsh7th/cmp-buffer",
    "hrsh7th/cmp-path",
    "hrsh7th/cmp-nvim-lua",
    "hrsh7th/cmp-nvim-lsp",
    "hrsh7th/cmp-nvim-lsp-signature-help",
    "pedrohdz/vim-yaml-folds",
    "lewis6991/gitsigns.nvim",
    {
        "preservim/nerdtree",
        dependencies = {
            "Deftera186/vim-devicons",
            "xuyuanp/nerdtree-git-plugin",
        }
    },
    {
        "nvim-lualine/lualine.nvim",
        dependencies = {
            "nvim-tree/nvim-web-devicons",
            "nomnivore/ollama.nvim",
        },
        config = function()
            -- local function cond()
            --     return package.loaded["ollama"] and require("ollama").status ~= nil
            -- end
            -- local function status_icon()
            --     local status = require("ollama").status()
            --     if status == "IDLE" then
            --         return "󱙺 "
            --     elseif status == "WORKING" then
            --         return "󰚩 "
            --     end
            -- end
            require("lualine").setup {
                -- sections = { lualine_x = { status_icon, cond } }
            }
        end
    },
    {
        "nvim-telescope/telescope.nvim",
        dependencies = { "nvim-lua/plenary.nvim" },
        config = function()
            vim.api.nvim_set_keymap("n", "<leader>ff", ":Telescope find_files<CR>", { noremap = true })
            vim.api.nvim_set_keymap("n", "<leader>fg", ":Telescope live_grep<CR>", { noremap = true })
            vim.api.nvim_set_keymap("n", "<leader>fb", ":Telescope buffers<CR>", { noremap = true })
            vim.api.nvim_set_keymap("n", "<leader>fh", ":Telescope help_tags<CR>", { noremap = true })
        end
    },
    {
        "lewis6991/gitsigns.nvim",
        config = function()
            require("gitsigns").setup()
        end
    },
    {
        "jose-elias-alvarez/null-ls.nvim",
        dependencies = { "nvim-lua/plenary.nvim" }
    },
    --    {
    --         "iamcco/markdown-preview.nvim",
    --         run = "cd app && npm install",
    --         setup = function() vim.g.mkdp_filetypes = { "markdown" } end, ft = { "markdown" }
    --     }
    "phaazon/hop.nvim",
    {
        "kdheepak/lazygit.nvim",
        config = function()
            -- vim.g.lazygit_floating_window_winblend = 10
            vim.g.lazygit_floating_window_scaling_factor = 0.8
            vim.api.nvim_set_keymap("n", "<leader>gg", ":LazyGit<CR>", { noremap = true })
        end
    },
    "Mofiqul/dracula.nvim",
    {
        "https://git.sr.ht/~whynothugo/lsp_lines.nvim",
        config = function()
            require("lsp_lines").setup()
        end,
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
    -- {
    --     "nomnivore/ollama.nvim",
    --     dependencies = {
    --         "nvim-lua/plenary.nvim",
    --     },
    --     cmd = { "Ollama", "OllamaModel", "OllamaServe", "OllamaServeStop" },
    --     keys = {
    --         {
    --             "<leader>oo",
    --             ":<c-u>lua require('ollama').prompt()<cr>",
    --             desc = "ollama prompt",
    --             mode = { "n", "v" },
    --         },
    --         {
    --             "<leader>oG",
    --             ":<c-u>lua require('ollama').prompt('Generate_Code')<cr>",
    --             desc = "ollama Generate Code",
    --             mode = { "n", "v" },
    --         },
    --     },
    --     opts = {
    --         model = "codeqwen",
    --         -- model = "qwen:32b"
    --         -- model = "llama3"
    --         -- model = "llama2:13b",
    --         -- model = "dolphin:latest",
    --         -- model = "dolphin-mixtral:8x7b-v2.7-q2_K",
    --         -- model = "codellama:34b",
    --         -- model = "dolphin-mixtral:8x7b-v2.7-q3_K_M",
    --         -- model = "codellama:13b-code-q6_K",
    --         -- url = "http://homepc:11434"
    --         -- url = "http://Bedroc-Proxy-YrRxlY5LRo9Z-1372903793.us-west-2.elb.amazonaws.com/api/v1"
    --     }
    -- },
})
