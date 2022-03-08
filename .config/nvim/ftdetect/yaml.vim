autocmd BufRead,BufNewFile *.yaml if getline(1) =~ '^AWSTemplateFormatVersion.*$' || getline(2) =~ '^AWSTemplateFormatVersion.*$'| set filetype=yaml.cloudformation | endif
