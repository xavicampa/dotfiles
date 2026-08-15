---
name: dotfiles
description: Manage the dotfiles repository by passing --git-dir and --work-tree flags before the git subcommand. Only trigger when the user explicitly mentions dotfiles.
---

# dotfiles

Prepend --git-dir=$HOME/.dotfiles/ --work-tree=$HOME to the git command whenever dotfiles is mentioned, i.e. place the flags BEFORE the subcommand:

git --git-dir=$HOME/.dotfiles/ --work-tree=$HOME <subcommand> [args]

Do NOT put the flags after the subcommand (`git status --git-dir=... --work-tree=...` fails with "not a git repository").

Examples:

git --git-dir=$HOME/.dotfiles/ --work-tree=$HOME status
git --git-dir=$HOME/.dotfiles/ --work-tree=$HOME add .config/nvim
git --git-dir=$HOME/.dotfiles/ --work-tree=$HOME commit -m "update config"
