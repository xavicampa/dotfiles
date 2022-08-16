alias dotfiles="git --git-dir=$HOME/.dotfiles/ --work-tree=$HOME"
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

# node
set -gx PATH $PATH ~/.npm-packages/bin
set -gx NODE_PATH $NODE_PATH ~/.npm-packages/lib/node_modules

# amplify nixos
set -gx PATH $PATH ~/amplify-cli/node_modules/.bin

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

# tokyonight
# TokyoNight Color Palette
set -l foreground c0caf5
set -l selection 364A82
set -l comment 565f89
set -l red f7768e
set -l orange ff9e64
set -l yellow e0af68
set -l green 9ece6a
set -l purple 9d7cd8
set -l cyan 7dcfff
set -l pink bb9af7

# Syntax Highlighting Colors
set -g fish_color_normal $foreground
set -g fish_color_command $cyan
set -g fish_color_keyword $pink
set -g fish_color_quote $yellow
set -g fish_color_redirection $foreground
set -g fish_color_end $orange
set -g fish_color_error $red
set -g fish_color_param $purple
set -g fish_color_comment $comment
set -g fish_color_selection --background=$selection
set -g fish_color_search_match --background=$selection
set -g fish_color_operator $green
set -g fish_color_escape $pink
set -g fish_color_autosuggestion $comment

# Completion Pager Colors
set -g fish_pager_color_progress $comment
set -g fish_pager_color_prefix $cyan
set -g fish_pager_color_completion $foreground
set -g fish_pager_color_description $comment

# keep at the end
starship init fish | source
