# Add dotfiles to new machine
1. Clone repo:

```git clone --bare git@github.com:xavicampa/dotfiles.git $HOME/.dotfiles```

2. Add alias to `.zshrc` — plain `git`, not an absolute path:

```alias dotfiles='git --git-dir=$HOME/.dotfiles/ --work-tree=$HOME'```

(`/usr/bin/git` is what this used to say, and it does not exist on NixOS: git lives in
the user profile, `/etc/profiles/per-user/<user>/bin/git`.)

3. Check out:

```dotfiles checkout```

4. Hide untracked files:

```dotfiles config --local status.showUntrackedFiles no```

(This only hides what is left over. The actual ignore policy is tracked — `$HOME/.gitignore`,
`.pi/agent/.gitignore`, `~/.config/strata/<tree>/.gitignore` — so it arrives with step 3.)

5. Make origin visible (a bare clone does not do this):

```dotfiles config --local remote.origin.fetch '+refs/heads/*:refs/remotes/origin/*'```

`git clone --bare` writes a `[remote "origin"]` with a url and **no `fetch` refspec**, so
`fetch` only writes `FETCH_HEAD`, `push` records nothing, and `git status` / `branch -vv`
have no `[origin/master]` to report ahead/behind against — the repo can sit a commit ahead
of origin with no local trace of it. Safe to add: a 2.54 bare clone does **not** install
`+refs/heads/*:refs/heads/*`, so a plain `fetch` will not overwrite local branches.
