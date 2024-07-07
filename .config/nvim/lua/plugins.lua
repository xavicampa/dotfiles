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
        },
        config = function()
            require("lualine").setup {
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
    -- {
    --     "terrortylor/nvim-comment",
    --     config = function()
    --         require("nvim_comment").setup({
    --             hook = function()
    --                 require("ts_context_commentstring.internal").update_commentstring()
    --             end,
    --         })
    --     end,
    -- },
    -- {
    --     "JoosepAlviste/nvim-ts-context-commentstring",
    --     dependencies = {
    --         "nvim-treesitter/nvim-treesitter",
    --         "terrortylor/nvim-comment",
    --     },
    --     config = function()
    --     end
    -- },
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
    -- {
    --   "folke/noice.nvim",
    --   event = "VeryLazy",
    --   opts = {
    --     -- add any options here
    --   },
    --   dependencies = {
    --     -- if you lazy-load any plugin below, make sure to add proper `module="..."` entries
    --     "MunifTanjim/nui.nvim",
    --     -- OPTIONAL:
    --     --   `nvim-notify` is only needed, if you want to use the notification view.
    --     --   If not available, we use `mini` as the fallback
    --     "rcarriga/nvim-notify",
    --     }
    -- },
    -- {
    --     "nomnivore/ollama.nvim",
    --     dependencies = {
    --         "nvim-lua/plenary.nvim",
    --     },
    --
    --     -- All the user commands added by the plugin
    --     cmd = { "Ollama", "OllamaModel", "OllamaServe", "OllamaServeStop" },
    --
    --     keys = {
    --         -- Sample keybind for prompt menu. Note that the <c-u> is important for selections to work properly.
    --         {
    --             "<leader>oo",
    --             ":<c-u>lua require('ollama').prompt()<cr>",
    --             desc = "ollama prompt",
    --             mode = { "n", "v" },
    --         },
    --
    --         -- Sample keybind for direct prompting. Note that the <c-u> is important for selections to work properly.
    --         {
    --             "<leader>oG",
    --             ":<c-u>lua require('ollama').prompt('Generate_Code')<cr>",
    --             desc = "ollama Generate Code",
    --             mode = { "n", "v" },
    --         },
    --     },
    --     opts = {
    --         model = "codeqwen"
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
    -- {
    --     "mfussenegger/nvim-jdtls"
    -- }
    -- {
    --     "David-Kunz/gen.nvim",
    --     opts = {
    --         host = "http://bedroc-proxy-yrrxly5lro9z-1372903793.us-west-2.elb.amazonaws.com/api/v1",
    --         -- model = "codellama:34b"
    --         model = "anthropic.claude-3-sonnet-20240229-v1:0"
    --     }
    -- },
    -- {
    --     'huggingface/llm.nvim',
    --     opts = {
    --         backend = "ollama",
    --         -- api_token = "bedrock",
    --         -- url = "http://bedroc-proxy-yrrxly5lro9z-1372903793.us-west-2.elb.amazonaws.com/api/v1/chat/completions",
    --         url = "http://localhost:11434",
    --         -- model = "anthropic.claude-3-sonnet-20240229-v1:0",
    --         model = "codeqwen",
    --         -- request_body = {}
    --         request_body = {
    --             -- Modelfile options for the model you use
    --             options = {
    --                 temperature = 0.2,
    --                 top_p = 0.95,
    --             }
    --         }
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
    -- {
    --     "gsuuon/model.nvim",
    --     cmd = { "Model", "Mchat" },
    --     init = function()
    --         vim.filetype.add({ extension = { mchat = "mchat" } })
    --     end,
    --     ft = "mchat",
    --     keys = { { "<leader>h", ":Model<cr>", mode = "v" } },
    --     config = function()
    --         local openai = require("model.providers.openai")
    --         local util = require("model.util")
    --         require("model").setup({
    --             -- hl_group = "Substitute",
    --             prompts = util.module.autoload("prompt_library"),
    --             default_prompt = {
    --                 provider = openai,
    --                 options = {
    --                     url =
    --                     "http://bedroc-proxy-yrrxly5lro9z-1372903793.us-west-2.elb.amazonaws.com/api/v1/",
    --                     authorization = "Bearer bedrock",
    --                 },
    --                 builder = function(input)
    --                     return {
    --                         model = "anthropic.claude-3-sonnet-20240229-v1:0",
    --                         messages = {
    --                             {
    --                                 role = "system",
    --                                 content = "You are helpful assistant. You will only give code in your responses without any explanation nor backticks",
    --                             },
    --                             { role = "user", content = input },
    --                         },
    --                     }
    --                 end,
    --             },
    --         })
    --     end
    -- }
})
