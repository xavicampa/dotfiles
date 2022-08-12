local fn = vim.fn
local install_path = fn.stdpath('data') .. '/site/pack/packer/start/packer.nvim'
if fn.empty(fn.glob(install_path)) > 0 then
    packer_bootstrap = fn.system({ 'git', 'clone', '--depth', '1', 'https://github.com/wbthomason/packer.nvim',
        install_path })
    vim.cmd [[packadd packer.nvim]]
end

return require('packer').startup(function(use)
    use 'wbthomason/packer.nvim'
    use 'nvim-treesitter/nvim-treesitter'
    use 'neovim/nvim-lspconfig'
    use 'SirVer/ultisnips'
    use 'honza/vim-snippets'
    use 'quangnguyen30192/cmp-nvim-ultisnips'
    use 'onsails/lspkind.nvim'
    use 'hrsh7th/nvim-cmp'
    use 'hrsh7th/cmp-buffer'
    use 'hrsh7th/cmp-path'
    use 'hrsh7th/cmp-nvim-lua'
    use 'hrsh7th/cmp-nvim-lsp'
    use 'hrsh7th/cmp-nvim-lsp-signature-help'
    use {
        "windwp/nvim-autopairs",
        config = function()
            require("nvim-autopairs").setup({
                check_ts =true
            })
        end
    }
    use {
        'preservim/nerdtree',
        requires = { { 'ryanoasis/vim-devicons' } },
    }
    use 'itchyny/lightline.vim'
    use {
        'Xuyuanp/nerdtree-git-plugin',
        requires = { { 'preservim/nerdtree' } },
    }
    use 'tiagofumo/vim-nerdtree-syntax-highlight'
    use 'folke/lsp-colors.nvim'
    use {
        'folke/trouble.nvim',
        requires = { { 'kyazdani42/nvim-web-devicons' } },
    }
    use 'pedrohdz/vim-yaml-folds'
    use {
        'nvim-telescope/telescope.nvim',
        requires = { { 'nvim-lua/plenary.nvim' } },
        config = function()
            vim.api.nvim_set_keymap("n", "<leader>ff", ":Telescope find_files<CR>", { noremap = true })
            vim.api.nvim_set_keymap("n", "<leader>fg", ":Telescope live_grep<CR>", { noremap = true })
            vim.api.nvim_set_keymap("n", "<leader>fb", ":Telescope buffers<CR>", { noremap = true })
            vim.api.nvim_set_keymap("n", "<leader>fh", ":Telescope help_tags<CR>", { noremap = true })
        end
    }
    use {
        'lewis6991/gitsigns.nvim',
        config = function()
            require('gitsigns').setup()
        end
    }
    use {
        'jose-elias-alvarez/null-ls.nvim',
        config = function()
            require('null-ls').setup {
                sources = {
                    require("null-ls").builtins.diagnostics.cfn_lint
                },
            }
        end
    }
    use 'iamcco/markdown-preview.nvim'
    use {
        'phaazon/hop.nvim',
        branch = 'v2'
    }
    use {
        'kdheepak/lazygit.nvim',
        config = function()
            vim.g.lazygit_floating_window_scaling_factor = 0.8
            vim.api.nvim_set_keymap("n", "<leader>gg", ":LazyGit<CR>", { noremap = true })
        end
    }
    use 'rafi/vim-venom'
    use {
        'lukas-reineke/indent-blankline.nvim',
        config = function()
            vim.opt.list = true
            require("indent_blankline").setup {
                show_current_context = true
            }
        end
    }
    use 'folke/tokyonight.nvim'

    -- Automatically set up your configuration after cloning packer.nvim
    -- Put this at the end after all plugins
    if packer_bootstrap then
        require('packer').sync()
    end
end)
