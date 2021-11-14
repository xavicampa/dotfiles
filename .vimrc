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
Plug 'OmniSharp/omnisharp-vim'
Plug 'dense-analysis/ale'
Plug 'junegunn/fzf', { 'do': { -> fzf#install() } }
Plug 'junegunn/fzf.vim'
"Plug 'prabirshrestha/asyncomplete.vim'
Plug 'preservim/nerdtree'
Plug 'sheerun/vim-polyglot'
Plug 'vim-airline/vim-airline'
Plug 'vim-airline/vim-airline-themes'
Plug 'morhetz/gruvbox'
Plug 'neoclide/coc.nvim', { 'branch': 'release' }
Plug 'valloric/MatchTagAlways'
Plug 'jiangmiao/auto-pairs'
Plug 'tpope/vim-fugitive'
Plug 'Xuyuanp/nerdtree-git-plugin'
Plug 'ryanoasis/vim-devicons'
call plug#end()

inoremap jk <ESC>
let mapleader = "æ"
syntax on
set number
set relativenumber
set noswapfile
set hlsearch
set ignorecase
set incsearch
nnoremap <C-t> :NERDTreeToggle<CR>
let g:airline_powerline_fonts = 1
let g:airline#extensions#tabline#enabled = 1
let g:airline#extensions#tabline#buffer_nr_show = 1
colorscheme gruvbox
set background=dark
let g:coc_global_extensions=[ 'coc-cfn-lint' ]
let g:NERDTreeGitStatusIndicatorMapCustom = {
                \ 'Modified'  :'✹',
                \ 'Staged'    :'✚',
                \ 'Untracked' :'✭',
                \ 'Renamed'   :'➜',
                \ 'Unmerged'  :'═',
                \ 'Deleted'   :'✖',
                \ 'Dirty'     :'✗',
                \ 'Ignored'   :'☒',
                \ 'Clean'     :'✔︎',
                \ 'Unknown'   :'?',
                \ }
let g:ale_linters = {'cs': ['OmniSharp']}
let g:ale_sign_error = '•'
let g:ale_sign_warning = '•'
let g:ale_sign_info = '·'
let g:ale_sign_style_error = '·'
let g:ale_sign_style_warning = '·'
let g:OmniSharp_selector_findusages = 'fzf'
"let g:asyncomplete_auto_popup = 1
"let g:asyncomplete_auto_completeopt = 0
let g:OmniSharp_diagnostic_showid = 1
inoremap <silent><expr> <c-space> coc#refresh()
inoremap <expr> <Tab> pumvisible() ? "\<C-n>" : "\<Tab>"
inoremap <expr> <S-Tab> pumvisible() ? "\<C-p>" : "\<S-Tab>"
autocmd FileType cs nmap <silent> gd :OmniSharpGotoDefinition<CR>
autocmd FileType cs nnoremap <buffer> <Leader>fu :OmniSharpFindUsages<CR>
autocmd FileType cs nnoremap <buffer> <Leader>fi :OmniSharpFindImplementations<CR>
autocmd FileType cs nnoremap <Leader><Space> :OmniSharpGetCodeActions<CR>
let g:ale_disable_lsp = 1
nmap <silent> <C-e> <Plug>(ale_next_wrap)
nmap <silent> <buffer> <C-\> <Plug>(omnisharp_signature_help)
imap <silent> <buffer> <C-\> <Plug>(omnisharp_signature_help)
