---
name: nixos
description: Upgrade NixOS on this host (classic non-flake setup) — update the system channels, build the new system, show a summary table of package upgrades (diff-closures), roll the channels back to the pre-upgrade generation, and only after explicit user confirmation switch to the built toplevel via --store-path. Triggered when the user asks to upgrade NixOS, update channels, "what will nixos-rebuild switch upgrade", run nixos-rebuild with --upgrade/--diff, or apply a NixOS update.
---

# NixOS Upgrade

Full flow: **build with channel upgrades + closure diff → present summary → roll channels back → confirm → switch to the built toplevel via `--store-path`**.

## Background for this host

- Classic (non-flake) NixOS. Config: `/etc/nixos/configuration.nix` (symlink to `~/.config/nixos/homepc`), shared bits in `~/.config/nixos/common.nix`.
- `nixos-rebuild` on this system is **nixos-rebuild-ng** (supports `--diff`, `--upgrade`, `--upgrade-all`, `--store-path`).
- `pkgs` = root's **`nixos` channel** (`nixos-26.05` branch). `unstable` (used in `common.nix` for e.g. `kiro-cli`, `btop-cuda`, `_1password-cli`) = root's **`nixpkgs-unstable` channel**.
- Kernel: `pkgs.linuxPackages_latest` (from the `nixos` channel). Kernel/initrd changes only take effect after a reboot.
- The channels live in `/nix/var/nix/profiles/per-user/root/channels/` (root-owned).

## Elevation — yes, pkexec is required

- `--upgrade`/`--upgrade-all` re-fetches **root's** channels. nixos-rebuild-ng hard-errors with "you must also pass '--sudo' or run the command as root" when euid != 0.
- `switch` updates the system profile and runs activation — root-only.
- Therefore both the build and the switch run under `pkexec` (per the `elevated-permissions` skill: **ask the user for approval before each pkexec invocation**).
- Running under pkexec resets parts of the environment, so **always set `PATH` and `NIX_PATH` explicitly** — otherwise `<nixpkgs>`, `<nixos-config>` and `<nixpkgs-unstable>` may not resolve:

```bash
NIX_PATH="nixpkgs=/nix/var/nix/profiles/per-user/root/channels/nixos:nixos-config=/etc/nixos/configuration.nix:/nix/var/nix/profiles/per-user/root/channels"
PATH="/run/current-system/sw/bin:/run/current-system/bin:/run/wrappers/bin:/usr/sbin:/usr/bin:/sbin:/bin"
```

- Use **`--upgrade-all`**, not `--upgrade`: plain `--upgrade` only updates the `nixos` channel plus channels marked with a `.update-on-nixos-rebuild` file (none are marked on this host), so `nixpkgs-unstable` — and every `unstable.*` package — would silently stay stale.

## Step 0 — snapshot current state (no elevation needed)

```bash
readlink -f /run/booted-system /run/current-system   # toplevel store paths incl. version
uname -r
readlink /nix/var/nix/profiles/per-user/root/channels   # → channels-<N>-link ; record N = pre-upgrade generation
readlink -f /nix/var/nix/profiles/per-user/root/channels/nixos
readlink -f /nix/var/nix/profiles/per-user/root/channels/nixpkgs-unstable
```

Record `N` and both store paths — `N` is needed to roll the channels back (after the diff, step 3, or if the build fails in step 1); the store paths verify the rollback and serve as a last-resort `NIX_PATH` pin.

`nix profile history --profile /nix/var/nix/profiles/per-user/root/channels` (read-only, works as the plain user) lists the retained generations, but it prints "No changes" for channel updates that don't bump the version string (the `nixos` channel stays `26.05`) — track the generation number, not the history diff.

Channel revisions (optional, for the summary):

```bash
nix-instantiate --eval --strict --raw --impure --expr \
  '(import /nix/var/nix/profiles/per-user/root/channels/nixos {}).lib.version'
nix-instantiate --eval --strict --raw --impure --expr \
  '(import /nix/var/nix/profiles/per-user/root/channels/nixpkgs-unstable {}).lib.version'
```

## Step 1 — build with upgraded channels + diff

**Ask the user for approval first** (this re-fetches the system channels and builds). Then run in the background and poll (channel fetch + build can take minutes):

```bash
pkexec env PATH="/run/current-system/sw/bin:/run/current-system/bin:/run/wrappers/bin:/usr/sbin:/usr/bin:/sbin:/bin" \
  NIX_PATH="nixpkgs=/nix/var/nix/profiles/per-user/root/channels/nixos:nixos-config=/etc/nixos/configuration.nix:/nix/var/nix/profiles/per-user/root/channels" \
  nixos-rebuild build --diff --upgrade-all > /tmp/nixos-upgrade-build.log 2>&1
```

Notes:

- The `--diff` output (`nix store diff-closures /run/current-system <new>`) goes to **stderr** with ANSI colors — strip them with `sed 's/\x1b\[[0-9;]*m//g'`.
- The new toplevel path appears in the log twice: the `>>> /nix/store/...` diff header line and the final `Done. The new configuration is /nix/store/...` line. Grep for it:
  ```bash
  grep -oE '/nix/store/[a-z0-9]+-nixos-system-[a-z0-9.]+-[a-f0-9]+' /tmp/nixos-upgrade-build.log | tail -1
  ```
- If the build fails, show the user the tail of the log and stop. **The channels are already updated at this point** (channel fetches run before the build inside `--upgrade-all`), and a plain `nixos-rebuild build` retry would evaluate against the new channels — possibly the very revision that broke the build. Roll the channels back to the step 0 generation first (same command as step 3), verify both channels match the step 0 paths, then retry the build with the same env vars, **without** `--upgrade-all`.

## Step 2 — present the summary

From the diff-closures block, categorize every line:

| Line pattern | Meaning |
|---|---|
| `name: old → new` | package upgraded (list old/new versions) |
| `name: ∅ → v` | added to the system closure |
| `name: v → ∅` | removed from the system closure |
| `name: ±size` only | internal/dependency change, no version change |

Always also check the **kernel** (it's often not in the named diff lines):

```bash
nix path-info --recursive <old-toplevel> <new-toplevel> \
  | grep -oE '/nix/store/[a-z0-9]+-linux-[0-9][^/]*' | sort -u
```

Compare against `uname -r`.

Present as a table like this, plus a short paragraph:

```
| Package       | Old → New                |
|---------------|--------------------------|
| firefox-bin   | 153.0.3 → 153.0.4        |
| ...           | ...                      |

Added:  bluez 5.87, glib 2.88.3, ...
Removed: audit 4.2, tpm2-tss 4.1.3
Kernel:  linux 7.1.8 (unchanged) / or 7.1.8 → 7.2.1 (reboot required)
```

Mention that `--diff` compares against `/run/current-system` (last activated), which can differ from `/run/booted-system` if a switch happened after the last boot.

## Step 3 — roll the channels back (before asking about the switch)

After step 1 the channels are already updated, and nothing later in the flow depends on them staying updated — so roll them back to the pre-upgrade generation right after the summary is presented. The user's decision (approve/decline the switch) then has no channel side effects, and if the user declines there is nothing left to undo. Channel state is identical to before the upgrade attempt from here on, so future plain `nixos-rebuild` invocations evaluate against the pre-upgrade channels again.

The channels profile is root-owned, so the rollback runs under pkexec too — ask for approval first (the question can be combined with presenting the summary in step 2). `<N>` is the pre-upgrade generation recorded in step 0:

```bash
pkexec env PATH="/run/current-system/sw/bin:/run/current-system/bin:/run/wrappers/bin:/usr/sbin:/usr/bin:/sbin:/bin" \
  NIX_PATH="nixpkgs=/nix/var/nix/profiles/per-user/root/channels/nixos:nixos-config=/etc/nixos/configuration.nix:/nix/var/nix/profiles/per-user/root/channels" \
  nix-channel --rollback <N>
```

Under the hood this is `nix-env -p /nix/var/nix/profiles/per-user/root/channels --switch-generation <N>` — a pure symlink swap: no build, no download, instant, and the updated generations are kept (re-forwardable with `--rollback <newer>`).

**Do not use bare `nix-channel --rollback`** (one generation back): `--upgrade-all` updates channels one at a time and each update commits its own generation, so the pre-upgrade state can be two generations back — a one-step rollback would land on an intermediate state with only one channel updated.

Verify `readlink -f` on both channels matches the paths recorded in step 0.

## Step 4 — confirm, then switch

**Do not switch without an explicit yes.** Ask:

> "Build succeeded and the diff looks as above. The channels are rolled back to the pre-upgrade generation. Shall I run `nixos-rebuild switch --store-path <new-toplevel>` to activate it?"

Only after explicit confirmation, run (pkexec, same env vars). `<new-toplevel>` is the path grepped from the build log in step 1:

```bash
pkexec env PATH="/run/current-system/sw/bin:/run/current-system/bin:/run/wrappers/bin:/usr/sbin:/usr/bin:/sbin:/bin" \
  NIX_PATH="nixpkgs=/nix/var/nix/profiles/per-user/root/channels/nixos:nixos-config=/etc/nixos/configuration.nix:/nix/var/nix/profiles/per-user/root/channels" \
  nixos-rebuild switch --store-path /nix/store/<new-toplevel>
```

`--store-path` is essential here: after the step 3 rollback, a plain `nixos-rebuild switch` would re-evaluate the config against the (rolled-back) channels and deploy the *old* toplevel — not the diffed closure. With `--store-path`, the evaluation and build phases are skipped entirely (man: "skips the evaluation and build phases entirely") and exactly the store path built in step 1 is activated. (Only valid for switch/boot/test/dry-activate; mutually exclusive with `--rollback`/`--flake`/`--file`/`--attr` — none used here.)

Then:

- Verify: `readlink -f /run/current-system` should point at the new toplevel.
- If the kernel changed, tell the user a reboot is needed for the new kernel/initrd.
- Note: the build in step 1 also left a `./result` symlink in the CWD of the pkexec invocation (root's home) — harmless.

## Gotchas

- Never run the upgrade as a plain user: `--upgrade` errors out (needs root), and a non-root `switch` cannot activate.
- The global flake registry has `flake:nixpkgs` pinned to a live unstable tarball — irrelevant for this classic rebuild (which resolves via NIX_PATH/channels), don't let it confuse the summary.
- `nixos-rebuild build` (non-flake) resolves to `import <nixpkgs/nixos>` with `configuration = <nixos-config>`; no flake or `--file` arguments are needed.
- After the step 3 rollback, the switch must always use `--store-path` with the step 1 toplevel: a plain `nixos-rebuild switch` re-evaluates against the old channels and would deploy the old system, silently discarding the diffed build.
- `--upgrade-all` = one `nix-channel --update <name>` per channel, and each commits a separate generation of the channels profile — so roll back to the recorded generation number, never "one back".
- Channel generations are never auto-pruned (only explicit `nix-env --delete-generations` removes them), so the pre-upgrade generation survives across upgrades. Old generations keep their channel store paths valid and GC-protected — if a rollback isn't possible (e.g. the old generation was pruned), retry the build with `NIX_PATH` pinned to the step 0 store paths (explicit `nixpkgs=…` / `nixpkgs-unstable=…` entries) instead.
