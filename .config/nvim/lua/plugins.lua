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
    -- { "catppuccin/nvim", name = "catppuccin", priority = 1000 },
    {
        "preservim/nerdtree",
        dependencies = {
            "ryanoasis/vim-devicons",
        }
    },
    {
        "nvim-lualine/lualine.nvim",
        dependencies = { "nvim-tree/nvim-web-devicons" },
    },
    {
        "xuyuanp/nerdtree-git-plugin",
        dependencies = { "preservim/nerdtree" }
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
    {
        "terrortylor/nvim-comment",
        config = function()
            require("nvim_comment").setup({
                hook = function()
                    require("ts_context_commentstring.internal").update_commentstring()
                end,
            })
        end,
    },
    {
        "JoosepAlviste/nvim-ts-context-commentstring",
        dependencies = {
            "nvim-treesitter/nvim-treesitter",
            "terrortylor/nvim-comment",
        },
        config = function()
            -- require("ts_context_commentstring").setup {
            --     skip_ts_context_commentstring_movule = false
            -- }
            -- require("nvim-treesitter.configs").setup {
            --     context_commentstring = {
            --         enable = true,
            --         enable_autocmd = false,
            --     }
            -- }
        end
    },
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
        "nomnivore/ollama.nvim",
        dependencies = {
            "nvim-lua/plenary.nvim",
        },

        -- All the user commands added by the plugin
        cmd = { "Ollama", "OllamaModel", "OllamaServe", "OllamaServeStop" },

        keys = {
            -- Sample keybind for prompt menu. Note that the <c-u> is important for selections to work properly.
            {
                "<leader>oo",
                ":<c-u>lua require('ollama').prompt()<cr>",
                desc = "ollama prompt",
                mode = { "n", "v" },
            },

            -- Sample keybind for direct prompting. Note that the <c-u> is important for selections to work properly.
            {
                "<leader>oG",
                ":<c-u>lua require('ollama').prompt('Generate_Code')<cr>",
                desc = "ollama Generate Code",
                mode = { "n", "v" },
            },
        },
        opts = {
            -- model = "llama2:13b",
            -- model = "dolphin:latest",
            -- model = "dolphin-mixtral:8x7b-v2.7-q2_K",
            model = "codellama:34b",
            -- model = "dolphin-mixtral:8x7b-v2.7-q3_K_M",
            -- model = "codellama:13b-code-q6_K",
            -- url = "http://homepc:11434"
        }
    },
    -- Minimal configuration
    -- {
    --     "David-Kunz/gen.nvim",
    --     opts = {
    --         model = "codellama:34b"
    --     }
    -- },
    -- {
    --     'huggingface/llm.nvim',
    --     opts = {
    --         model = "http://localhost:11434/api/generate"
    --         -- cf Setup
    --     }
    -- },
    -- {
    --     "jackMort/ChatGPT.nvim",
    --     event = "VeryLazy",
    --     dependencies = {
    --         "MunifTanjim/nui.nvim",
    --         "nvim-lua/plenary.nvim",
    --         "nvim-telescope/telescope.nvim"
    --     },
    --     config = function()
    --         require("chatgpt").setup({
    --             api_key_cmd = "op read op://private/openai/credential --no-newline"
    --         })
    --     end
    -- }
})
