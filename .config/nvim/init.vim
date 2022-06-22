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
"Plug 'dense-analysis/ale'
"Plug 'neoclide/coc.nvim', {'branch': 'release'}
"Plug 'OmniSharp/omnisharp-vim'
"Plug 'nickspoons/vim-sharpenup'
Plug 'nvim-treesitter/nvim-treesitter', {'do': ':TSUpdate'}
Plug 'neovim/nvim-lspconfig'
Plug 'onsails/lspkind.nvim'
Plug 'hrsh7th/nvim-cmp'
Plug 'hrsh7th/cmp-buffer'
Plug 'hrsh7th/cmp-path'
Plug 'hrsh7th/cmp-nvim-lua'
Plug 'hrsh7th/cmp-nvim-lsp'
Plug 'hrsh7th/cmp-nvim-lsp-signature-help'
Plug 'junegunn/fzf', { 'do': { -> fzf#install() } }
Plug 'junegunn/fzf.vim'
Plug 'preservim/nerdtree'
Plug 'vim-airline/vim-airline'
Plug 'vim-airline/vim-airline-themes'
Plug 'gruvbox-community/gruvbox'
Plug 'valloric/MatchTagAlways'
Plug 'tpope/vim-fugitive'
Plug 'Xuyuanp/nerdtree-git-plugin'
Plug 'kyazdani42/nvim-web-devicons'
Plug 'folke/lsp-colors.nvim'
Plug 'folke/trouble.nvim'
Plug 'ryanoasis/vim-devicons'
Plug 'pedrohdz/vim-yaml-folds'
Plug 'lukas-reineke/indent-blankline.nvim'
Plug 'nvim-lua/plenary.nvim'
Plug 'lewis6991/gitsigns.nvim'
"Plug 'wfxr/minimap.vim'
Plug 'iamcco/markdown-preview.nvim', { 'do': 'cd app && yarn install'  }
"Plug 'github/copilot.vim'
call plug#end()

set encoding=utf-8
inoremap jk <ESC>
let mapleader = " "
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
colorscheme gruvbox
"set background=dark
set wildmenu
set wildmode=longest:full,full
set mouse=v
set tabstop=4
set softtabstop=-1
set shiftwidth=0
set expandtab
set autoindent
set smartindent

hi! Normal ctermbg=NONE guibg=NONE

"nmap <silent> <C-k> :lprevious<CR>
"nmap <silent> <C-j> :lnext<CR>
"nmap <silent> <C-p> :cprevious<CR>
"nmap <silent> <C-n> :cnext<CR>

" folding
set foldmethod=expr
set foldexpr=nvim_treesitter#foldexpr()

" autocompletion options
" Use <Tab> and <S-Tab> to navigate through popup menu
"inoremap <expr> <Tab>   pumvisible() ? "\<C-n>" : "\<Tab>"
"inoremap <expr> <S-Tab> pumvisible() ? "\<C-p>" : "\<S-Tab>"
" Set completeopt to have a better completion experience
set completeopt=menu,menuone,noselect
" Avoid showing message extra message when using completion
"set shortmess+=c
