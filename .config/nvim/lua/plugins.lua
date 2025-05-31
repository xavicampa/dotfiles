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
    {
        "saghen/blink.cmp",
        version = '1.*',
    },
    -- "SirVer/ultisnips",
    -- "honza/vim-snippets",
    -- "quangnguyen30192/cmp-nvim-ultisnips",
    "onsails/lspkind.nvim",
    -- "hrsh7th/nvim-cmp",
    -- "hrsh7th/cmp-buffer",
    -- "hrsh7th/cmp-path",
    -- "hrsh7th/cmp-nvim-lua",
    -- "hrsh7th/cmp-nvim-lsp",
    -- "hrsh7th/cmp-nvim-lsp-signature-help",
    "pedrohdz/vim-yaml-folds",
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
        "nvimtools/none-ls.nvim",
        dependencies = { "nvim-lua/plenary.nvim" },
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
    {
        'huggingface/llm.nvim',
        opts = {
            backend = "ollama",
            model = "codellama:7b-code",
            fim = {
                enabled = true,
                prefix = "<PRE> ",
                middle = " <MID>",
                suffix = " <SUF>",
            },
            context_window = 4096,
            url = "http://localhost:11434",
            tokens_to_clear = { "<EOT>" },
            -- model = "deepseek-coder-v2:16b-lite-base-q4_0",
            -- fim = {
            --     enabled = true,
            --     prefix = "<｜fim▁begin｜>",
            --     middle = "<｜fim▁end｜>",
            --     suffix = "<｜fim▁hole｜>",
            -- },
            -- context_window = 4096,
            -- url = "http://localhost:11434",
        }
    },
    {
        "David-Kunz/gen.nvim",
        opts = {
            model = "llama3.2",
            -- model = "deepseek-r1:14b",
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
    },
    -- {
    --     "yetone/avante.nvim",
    --     dependencies = {
    --         "stevearc/dressing.nvim",
    --         "nvim-lua/plenary.nvim",
    --         "MunifTanjim/nui.nvim",
    --         "nvim-tree/nvim-web-devicons",
    --     },
    --     opts = {
    --         provider = "ollama",
    --         vendors = {
    --             ---@type AvanteProvider
    --             ollama = {
    --                 ["local"] = true,
    --                 endpoint = "127.0.0.1:11434/v1",
    --                 model = "codegemma:2b-v1.1",
    --                 parse_curl_args = function(opts, code_opts)
    --                     return {
    --                         url = opts.endpoint .. "/chat/completions",
    --                         headers = {
    --                             ["Accept"] = "application/json",
    --                             ["Content-Type"] = "application/json",
    --                         },
    --                         body = {
    --                             model = opts.model,
    --                             messages = require("avante.providers").copilot.parse_message(code_opts), -- you can make your own message, but this is very advanced
    --                             max_tokens = 2048,
    --                             stream = true,
    --                         },
    --                     }
    --                 end,
    --                 parse_response_data = function(data_stream, event_state, opts)
    --                     require("avante.providers").openai.parse_response(data_stream, event_state, opts)
    --                 end,
    --             },
    --         },
    --     }
    -- },
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
    'mfussenegger/nvim-jdtls',
    'direnv/direnv.vim',
    'psliwka/vim-smoothie',
    'mfussenegger/nvim-dap',
    'mason-org/mason.nvim',
})
