" Install vim-plug if not found
if empty(glob('~/.vim/autoload/plug.vim'))
  silent !curl -fLo ~/.vim/autoload/plug.vim --create-dirs
    \ https://raw.githubusercontent.com/junegunn/vim-plug/master/plug.vim
endif

" Run PlugInstall if there are missing plugins
autocmd VimEnter * if len(filter(values(g:plugs), '!isdirectory(v:val.dir)'))
  \| PlugInstall --sync | source $MYVIMRC
\| endif

call plug#begin('~/.vim/plugged')
Plug 'preservim/nerdtree'
Plug 'OmniSharp/omnisharp-vim'
Plug 'sheerun/vim-polyglot'
Plug 'vim-airline/vim-airline'
Plug 'vim-airline/vim-airline-themes'
Plug 'dracula/vim', { 'as': 'dracula'  }
Plug 'neoclide/coc.nvim', {'branch': 'release'}
Plug 'valloric/MatchTagAlways'
Plug 'jiangmiao/auto-pairs'
call plug#end()

inoremap jk <ESC>
let mapleader = "æ"
syntax on
set number
set noswapfile
set hlsearch
set ignorecase
set incsearch
nnoremap <C-t> :NERDTreeToggle<CR>
filetype indent plugin on
let g:airline_powerline_fonts = 1
colorscheme dracula
let g:coc_global_extensions=[ 'coc-omnisharp', 'coc-yaml', 'coc-cfn-lint', 'coc-json' ]
inoremap <silent><expr> <c-space> coc#refresh()
inoremap <expr> <Tab> pumvisible() ? "\<C-n>" : "\<Tab>"
inoremap <expr> <S-Tab> pumvisible() ? "\<C-p>" : "\<S-Tab>"
autocmd FileType cs nmap <silent> gd :OmniSharpGotoDefinition<CR>
autocmd FileType cs nnoremap <buffer> <Leader>fu :OmniSharpFindUsages<CR>
autocmd FileType cs nnoremap <buffer> <Leader>fi :OmniSharpFindImplementations<CR>
autocmd FileType cs nnoremap <Leader><Space> :OmniSharpGetCodeActions<CR>
