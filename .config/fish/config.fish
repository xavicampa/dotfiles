if status --is-login
    set -gx PATH $PATH ~/.local/bin
    set -gx PATH $PATH ~/.dotnet/tools
    set -U fish_greeting
    set -Ux FZF_DEFAULT_COMMAND 'fd --type f'
end

alias dotfiles="/usr/bin/git --git-dir=$HOME/.dotfiles/ --work-tree=$HOME"

# keep at the end
starship init fish | source
