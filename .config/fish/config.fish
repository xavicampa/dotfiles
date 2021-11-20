alias dotfiles="/usr/bin/git --git-dir=$HOME/.dotfiles/ --work-tree=$HOME"

if status --is-login
    set -gx PATH $PATH ~/.local/bin
    set -gx PATH $PATH ~/.dotnet/tools
    set -U fish_greeting
    set -Ux FZF_DEFAULT_COMMAND 'fdfind --type f'
    set -Ux EDITOR vim
    set -Ux VISUAL $EDITOR
end

# keep at the end
starship init fish | source
