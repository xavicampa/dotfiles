# Add dotfiles to new machine
1. Clone repo:

```git clone --bare git@github.com:xavicampa/dotfiles.git $HOME/.dotfiles```

2. Add alias to `.zshrc`:

```alias dotfiles='/usr/bin/git --git-dir=$HOME/.dotfiles/ --work-tree=$HOME'```

3. Check out:

```dotfiles checkout```
