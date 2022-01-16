autocmd BufRead *.yaml if getline(1) =~ '^AWSTemplateFormatVersion.*$' | set filetype=yaml.cloudformation | endif
