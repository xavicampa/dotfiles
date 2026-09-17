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

Stage targeted paths only (e.g. `add .config/nvim`) — never `git add .`, since the work tree is $HOME itself.

## Push policy: NEVER push

Never run remote operations (`push`, `push --force`, `push -u`, `fetch`, `ls-remote`, etc.) against the dotfiles remote. Every SSH connection signs with a 1Password SSH key, which requires a manual unlock/approval prompt the user must handle — and the 1Password agent frequently refuses signing when the app is locked. Agent commits stay local; the user pushes themselves. Do not retry a failed push and do not offer workarounds (one-shot agents, key piping) for pushing.
