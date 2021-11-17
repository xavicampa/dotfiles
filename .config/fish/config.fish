if status --is-login
    set -gx PATH $PATH ~/.local/bin
    set -gx PATH $PATH ~/.dotnet/tools
    set -Ux FZF_DEFAULT_COMMAND 'fdfind --type f'
    set -U fish_greeting
end

alias dotfiles="/usr/bin/git --git-dir=$HOME/.dotfiles/ --work-tree=$HOME"

# keep at the end
starship init fish | source
