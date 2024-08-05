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
            -- "nomnivore/ollama.nvim",
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
    -- {
    --     "https://git.sr.ht/~whynothugo/lsp_lines.nvim",
    --     config = function()
    --         require("lsp_lines").setup()
    --     end,
    -- },
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
        'huggingface/llm.nvim',
        opts = {
            backend = "ollama",
            model = "codegemma:2b-v1.1",
            fim = {
                enabled = true,
                prefix = "<|fim_prefix|>",
                middle = "<|fim_middle|>",
                suffix = "<|fim_suffix|>",
            },
            context_window = 8192,
            url = "http://localhost:11434",
            accept_keymap = "<C-y>",
            dismiss_keymap = "<C-n>",
            request_body = {
                num_predict = 128,
                temperature = 0,
                top_p = 0.9,
            },
            tokensToClear = { "<|file_separator|>" },
        }
    },
    {
        "David-Kunz/gen.nvim",
        opts = {
            model = "llama3.1",
        },
        vim.keymap.set({ 'n', 'v' }, '<leader>oo', ':Gen<CR>'),
        init = function()
            require("gen").prompts["Generate"] = {
                prompt = "These are your instructions:\n\n$input\n\n" ..
                    "Do not include examples.\n\n" ..
                    "Do not include usage examples.\n\n" ..
                    "Only output the result in format ```$filetype\n...\n```:\n```$filetype\n...\n```",
                replace = "false",
                extract = "```$filetype\n(.-)```"
            }
        end,
    }
})
