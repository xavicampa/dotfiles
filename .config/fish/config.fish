if status --is-login
    set -gx PATH $PATH ~/.local/bin
    set -gx PATH $PATH ~/.dotnet/tools
end

alias dotfiles='/usr/bin/git --git-dir=$HOME/.dotfiles/ --work-tree=$HOME'

# keep at the end
starship init fish | source
