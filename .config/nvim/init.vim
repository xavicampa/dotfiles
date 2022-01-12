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
"Plug 'OmniSharp/omnisharp-vim'
Plug 'junegunn/fzf', { 'do': { -> fzf#install() } }
Plug 'junegunn/fzf.vim'
Plug 'preservim/nerdtree'
"Plug 'sheerun/vim-polyglot'
Plug 'vim-airline/vim-airline'
Plug 'vim-airline/vim-airline-themes'
Plug 'gruvbox-community/gruvbox'
Plug 'valloric/MatchTagAlways'
"Plug 'jiangmiao/auto-pairs'
Plug 'tpope/vim-fugitive'
Plug 'Xuyuanp/nerdtree-git-plugin'
Plug 'ryanoasis/vim-devicons'
Plug 'neovim/nvim-lspconfig'
Plug 'hrsh7th/nvim-cmp'
Plug 'hrsh7th/cmp-nvim-lsp'
Plug 'L3MON4D3/LuaSnip'
Plug 'saadparwaiz1/cmp_luasnip'
Plug 'neoclide/coc.nvim', {'branch': 'release'}
Plug 'pedrohdz/vim-yaml-folds'
Plug 'Yggdroot/indentLine'
"Plug 'nvim-treesitter/nvim-treesitter', {'do': ':TSUpdate'}  " We recommend updating the parsers on update
Plug 'easymotion/vim-easymotion'
call plug#end()

set encoding=utf-8
inoremap jk <ESC>
let mapleader = " "
"syntax on
set number
set relativenumber
set noswapfile
set hlsearch
"set nowrap
set ignorecase
set incsearch
set scrolloff=8
"set colorcolumn=80
colorscheme gruvbox
set background=dark
set wildmenu
set wildmode=longest:full,full
"set mouse=a
set list lcs=tab:\|\ 
let g:indentLine_char_list = ['|', '¦', '┆', '┊']
set tabstop=4
set softtabstop=-1
set shiftwidth=0
set expandtab
set autoindent
set smartindent

hi! Normal ctermbg=NONE guibg=NONE
