---
name: dotfiles
description: Manage the dotfiles repository. Only trigger when the user explicitly mentions dotfiles.
---

# dotfiles

Prepend --git-dir=$HOME/.dotfiles/ --work-tree=$HOME to the git command whenever dotfiles is mentioned, i.e. place the flags BEFORE the subcommand:

git --git-dir=$HOME/.dotfiles/ --work-tree=$HOME <subcommand> [args]

Do NOT put the flags after the subcommand (`git status --git-dir=... --work-tree=...` fails with "not a git repository").

Examples:

git --git-dir=$HOME/.dotfiles/ --work-tree=$HOME status
git --git-dir=$HOME/.dotfiles/ --work-tree=$HOME add .config/nvim
git --git-dir=$HOME/.dotfiles/ --work-tree=$HOME commit -m "update config"

## Push policy: NEVER push

Never run `git push` (or any remote operation like `push --force`, `push -u`, `ls-remote`, `fetch` for pushing) against the dotfiles remote. Commits are local-only; the user pushes themselves. Do not retry a failed push and do not offer workarounds (one-shot agents, key piping) for pushing.

Reason: pushing signs with 1Password SSH keys, which requires a manual unlock/approval prompt the user must handle, and the 1Password agent frequently refuses signing when the app is locked.
