[Wallpaper/Lock screen](https://wallpapersmug.com/w/download/3840x2160/multicolor-abstract-lines-4k-aaa206)

# Add dotfiles to new machine
1. Clone repo:

```git clone --bare git@github.com:xavicampa/dotfiles.git $HOME/.dotfiles```

2. Add alias to `.zshrc`:

```alias dotfiles='/usr/bin/git --git-dir=$HOME/.dotfiles/ --work-tree=$HOME'```

3. Check out:

```dotfiles checkout```

4. Hide untracked files:

```dotfiles config --local status.showUntrackedFiles no```

# Wallpaper
