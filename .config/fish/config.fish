alias dotfiles="/usr/bin/git --git-dir=$HOME/.dotfiles/ --work-tree=$HOME"
if which exa>/dev/null
    alias l='exa'
    alias la='exa -a'
    alias ll='exa -lah'
    alias ls='exa --color=auto'
end

if test -f /home/javi/nvim.appimage
    alias vim='/home/javi/nvim.appimage'
end

if which nvim>/dev/null
    alias vim='/opt/homebrew/bin/nvim'
end

if status --is-login
    set -gx PATH $PATH ~/.local/bin
    set -gx PATH $PATH ~/.dotnet/tools
    set -gx PATH $PATH ~/.cargo/bin
    set -gx PATH $PATH /Users/javi/Library/Python/3.8/bin
    set -U fish_greeting
    set -Ux EDITOR vim
    set -Ux VISUAL $EDITOR
    if which fdfind>/dev/null
        set -Ux FZF_DEFAULT_COMMAND 'fdfind --type f'
    else if which fd>/dev/null
        set -Ux FZF_DEFAULT_COMMAND 'fd --type f'
    end
end

# keep at the end
starship init fish | source
