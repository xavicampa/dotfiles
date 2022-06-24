alias dotfiles="/usr/bin/git --git-dir=$HOME/.dotfiles/ --work-tree=$HOME"
if which exa>/dev/null
    alias l='exa'
    alias la='exa -a'
    alias ll='exa -lah'
    alias ls='exa --color=auto'
end

#if test -f /home/javi/nvim.appimage
#    alias vim='/home/javi/nvim.appimage'
#end
#
if which nvim>/dev/null
    alias vim=(which nvim)
end

# Go
set -g GOPATH $HOME/go
set -gx PATH $GOPATH/bin $PATH

# python
set -gx PATH $PATH ~/.local/bin

if status --is-login
    set -gx PATH $PATH ~/.dotnet/tools
    set -gx PATH $PATH ~/.cargo/bin
    contains ~/go/bin $fish_user_paths; or set -Ua fish_user_paths ~/go/bin
    set -gx PATH $PATH /Users/javi/Library/Python/3.8/bin
    set -U fish_greeting
    set -Ux EDITOR nvim
    set -Ux VISUAL $EDITOR
    if which fdfind >/dev/null 2>/dev/null
        set -Ux FZF_DEFAULT_COMMAND 'fdfind --type f'
    else if which fd>/dev/null 2>/dev/null
        set -Ux FZF_DEFAULT_COMMAND 'fd --type f'
    end
end

# keep at the end
starship init fish | source
