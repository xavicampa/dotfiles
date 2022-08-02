" Install vim-plug if not found
let data_dir = has('nvim') ? stdpath('data') . '/site' : '~/.vim'
if empty(glob(data_dir . '/autoload/plug.vim'))
  silent execute '!curl -fLo '.data_dir.'/autoload/plug.vim --create-dirs  https://raw.githubusercontent.com/junegunn/vim-plug/master/plug.vim'
  autocmd VimEnter * PlugInstall --sync | source $MYVIMRC
endif

" Run PlugInstall if there are missing plugins
autocmd VimEnter * if len(filter(values(g:plugs), '!isdirectory(v:val.dir)'))
  \| PlugInstall --sync | source $MYVIMRC
\| endif

call plug#begin(stdpath('data') . '/plugged')
Plug 'nvim-treesitter/nvim-treesitter', {'do': ':TSUpdate'}
Plug 'neovim/nvim-lspconfig'
Plug 'SirVer/ultisnips'
Plug 'honza/vim-snippets'
Plug 'quangnguyen30192/cmp-nvim-ultisnips'
Plug 'onsails/lspkind.nvim'
Plug 'hrsh7th/nvim-cmp'
Plug 'hrsh7th/cmp-buffer'
Plug 'hrsh7th/cmp-path'
Plug 'hrsh7th/cmp-nvim-lua'
Plug 'hrsh7th/cmp-nvim-lsp'
Plug 'hrsh7th/cmp-nvim-lsp-signature-help'
Plug 'preservim/nerdtree'
"Plug 'kdheepak/tabline.nvim'
"Plug 'akinsho/bufferline.nvim'
"Plug 'nvim-lualine/lualine.nvim'
"Plug 'vim-airline/vim-airline'
"Plug 'vim-airline/vim-airline-themes'
"Plug 'gruvbox-community/gruvbox'
Plug 'folke/tokyonight.nvim', { 'branch': 'main' }
"Plug 'rose-pine/neovim'
"Plug 'catppuccin/nvim', {'as': 'catppuccin'}
"Plug 'sainnhe/gruvbox-material'
"Plug 'valloric/MatchTagAlways'
"Plug 'tpope/vim-fugitive'
Plug 'itchyny/lightline.vim'
Plug 'Xuyuanp/nerdtree-git-plugin'
Plug 'tiagofumo/vim-nerdtree-syntax-highlight'
Plug 'kyazdani42/nvim-web-devicons'
Plug 'folke/lsp-colors.nvim'
Plug 'folke/trouble.nvim'
Plug 'ryanoasis/vim-devicons'
Plug 'pedrohdz/vim-yaml-folds'
Plug 'lukas-reineke/indent-blankline.nvim'
Plug 'nvim-lua/plenary.nvim'
Plug 'nvim-telescope/telescope.nvim'
Plug 'lewis6991/gitsigns.nvim'
Plug 'jose-elias-alvarez/null-ls.nvim'
Plug 'iamcco/markdown-preview.nvim', { 'do': 'cd app && yarn install'  }
Plug 'phaazon/hop.nvim'
"Plug 'glepnir/lspsaga.nvim', { 'branch': 'main' }
Plug 'kdheepak/lazygit.nvim'
Plug 'rafi/vim-venom'
call plug#end()

set encoding=utf-8
inoremap jk <ESC>
let mapleader = ","
syntax on
set number
set relativenumber
set noswapfile
set hlsearch
set nowrap
set ignorecase
set incsearch
set scrolloff=8
"set colorcolumn=80
set termguicolors
"let g:gruvbox_italic=1
"colorscheme gruvbox-material
"let g:tokyonight_transparent=1
let g:tokyonight_style='storm'
let g:lightline = {'colorscheme': 'tokyonight'}
set noshowmode
colorscheme tokyonight
set background=dark
set wildmenu
set wildmode=longest:full,full
set tabstop=4
set softtabstop=-1
set shiftwidth=0
set expandtab
set autoindent
set smartindent

" mouse
set mouse=a

" clipboard
set clipboard=unnamed,unnamedplus

" transparent background
" hi Normal ctermbg=NONE guibg=NONE

" folding
set foldmethod=expr
set foldexpr=nvim_treesitter#foldexpr()

" autocompletion options
set completeopt=menu,menuone,noselect

if exists("g:neovide")
    " Put anything you want to happen only in Neovide here
    set guifont=JetBrainsMono\ Nerd\ Font
    " let g:neovide_transparency=0.70
endif
