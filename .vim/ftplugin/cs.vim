nmap <silent> gd :OmniSharpGotoDefinition<CR>
nnoremap <buffer> <Leader>fu :OmniSharpFindUsages<CR>
nnoremap <buffer> <Leader>fi :OmniSharpFindImplementations<CR>
nnoremap <Leader><Space> :OmniSharpGetCodeActions<CR>
nmap <silent> <buffer> <C-\> <Plug>(omnisharp_signature_help)
imap <silent> <buffer> <C-\> <Plug>(omnisharp_signature_help)
