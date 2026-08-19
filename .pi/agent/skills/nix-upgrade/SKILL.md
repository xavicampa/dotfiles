---
name: nix-upgrade
description: "Two independent upgrade flows — NixOS system (root channels + nixos-rebuild, NixOS host only) and Home Manager (user channels + home-manager, both hosts) — run either or both, on the NixOS host (classic non-flake) or the macOS host (classic home-manager). NixOS flow: fetch root channels into a scratch profile as the plain user, build + closure diff, present summary, and only on explicit confirmation commit the channels to the root profile and switch via --store-path — the root profile is never mutated before confirmation, so decline/failure needs no rollback. Home Manager flow: update the user's channels (macOS host also the root channels, via sudo), test-build, diff, and on confirmation activate the built generation; never touches the system toplevel. Also the reference for no-upgrade home-manager rebuilds (build/switch/--rollback). Triggered when the user asks to upgrade NixOS or home-manager, update channels, run nixos-rebuild with --upgrade/--diff, or apply a NixOS/home-manager update."
---

# NixOS + Home Manager upgrades

**Two independent flows.** Neither requires the other; run whichever the user asked for.

| Flow | Moves | Activates | Hosts |
|---|---|---|---|
| **A — NixOS system upgrade** | root channels (`nixos`, `nixpkgs-unstable`) — scratch-fetched, committed only on confirmation | system toplevel via `nixos-rebuild switch --store-path` | NixOS host only |
| **B — Home Manager upgrade** | user's channels (plain user); **macOS host also fetches the root channels** (sudo) | home-manager generation via `nix-env --set` + the built activate script | both hosts |

Shared discipline (both flows):

1. **Snapshot** the channel profile generation number + store paths *before* fetching.
2. Fetching moves channel state, but nothing is activated yet — the attempt is still fully reversible. Flow B commits generations to the **real** user (and, on macOS, root) channel profiles → reversible by rollback. Flow A commits only to a **scratch** profile the plain user owns → nothing real is ever mutated; reversible by `rm -rf`.
3. **Build, diff, present the summary.**
4. **Ask for explicit confirmation.** Decline → Flow B: roll the real channels back to the snapshot generation; Flow A: delete the scratch — done. Build failure → Flow B: roll the channels back, retry the build without re-fetching; Flow A: retry against the scratch channels (or re-fetch into them). Confirm → activate **exactly the store path that was built** (never re-evaluate against channels to "get the same thing"); Flow A additionally commits the root channel profile to the exact built store paths first — a confirmed upgrade advances channel state; a declined or failed one does not.

## No-upgrade rebuild (config changed, channels stay)

When only `home.nix`/`configuration.nix` changed and no channel is being moved (both hosts, plain user):

```bash
home-manager build              # test build: evaluates + builds, prints the generation store path, NEVER activates (profile untouched)
home-manager switch             # build + activate in one step
home-manager switch --rollback  # undo the last switch: one generation back, no new generation created
```

None of these update **any** channel — they evaluate `home.nix` against the channels as they currently stand. This path never bumps package versions. "Upgrade" = Flow B. On the NixOS host, home *package* versions additionally only move after the root channels have moved via a confirmed Flow A (see Background) — a plain `home-manager switch` right after is then how the home env picks them up.

## Diff summary format (both flows)

From the `nix store diff-closures` output, categorize every line:

| Line pattern | Meaning |
|---|---|
| `name: old → new` | package upgraded (list old/new versions) |
| `name: ∅ → v` | added to the closure |
| `name: v → ∅` | removed from the closure |
| `name: ±size` only | internal/dependency change, no version change |

Present as a table like this, plus a short paragraph:

```
| Package       | Old → New                |
|---------------|--------------------------|
| firefox-bin   | 153.0.3 → 153.0.4        |
| ...           | ...                      |

Added:  bluez 5.87, glib 2.88.3, ...
Removed: audit 4.2, tpm2-tss 4.1.3
```

## Flow A — NixOS system upgrade (NixOS host only)

The upgrade is prepared **without touching the real root channel profile at all**: channels are fetched into a throwaway scratch channel profile owned by the plain user (A1), the build runs against exactly those store paths (A2), and only after the user confirms does the real root profile move — to the same store paths the build used (A4). Decline or build failure → delete the scratch and stop; nothing real ever changed, so there is no rollback to perform. The home environment is **not** touched: user channels and the home-manager profile are left alone.

Why a scratch profile instead of `nix-channel --update` under pkexec (the old approach):

- `nix-channel` run as **root ignores `XDG_STATE_HOME`** (verified on nix 2.34.8): under pkexec it always commits to the real root channel profile, so a root-side fetch can't be isolated from real state.
- `nix-channel` run as the **plain user honors `XDG_STATE_HOME`** (profile at `$XDG_STATE_HOME/nix/profiles/channels`) and reads its channel list from `$HOME/.nix-channels` — both redirectable, so a plain-user fetch into a scratch dir is fully isolated and user-owned (cleanup = `rm -rf`).
- Channel store paths land in the global `/nix/store` either way, and Nix auto-GC-roots the profiles it operates on (even under `/var/tmp`), so a plain-user scratch fetch feeds the root `switch` cleanly.

### A0 — snapshot (no elevation needed)

```bash
readlink -f /run/booted-system /run/current-system   # toplevel store paths incl. version
uname -r
readlink /nix/var/nix/profiles/per-user/root/channels   # → channels-<N>-link ; record N = pre-upgrade generation
readlink -f /nix/var/nix/profiles/per-user/root/channels/nixos
readlink -f /nix/var/nix/profiles/per-user/root/channels/nixpkgs-unstable
```

`N` and the two store paths are the **verification baseline**: after the A4 commit both channels must point at the newly built store paths, and `N` is the rollback target for the A4 escape hatch in case the commit misbehaves.

`nix profile history --profile /nix/var/nix/profiles/per-user/root/channels` (read-only, works as the plain user) lists retained generations, but it prints "No changes" for channel updates that don't bump the version string (the `nixos` channel stays `26.05`) — track the generation number, not the history diff.

Channel versions (optional, for the summary):

```bash
nix-instantiate --eval --strict --raw --impure --expr \
  '(import /nix/var/nix/profiles/per-user/root/channels/nixos {}).lib.version'
nix-instantiate --eval --strict --raw --impure --expr \
  '(import /nix/var/nix/profiles/per-user/root/channels/nixpkgs-unstable {}).lib.version'
```

### A1 — scratch fetch (plain user, **no root**)

Read the real root channel list first (read-only, but `/root` isn't readable without elevation — pkexec, approval per the `elevated-permissions` skill):

```bash
pkexec cat /root/.nix-channels
```

Then replicate it in a scratch `HOME` and fetch into a scratch state dir (plain user):

```bash
SCRATCH=/var/tmp/nixos-upgrade
rm -rf "$SCRATCH"
mkdir -p "$SCRATCH/home"
cat > "$SCRATCH/home/.nix-channels" <<'EOF'
https://channels.nixos.org/nixos-26.05 nixos
https://channels.nixos.org/nixos-unstable nixpkgs-unstable
EOF
env HOME="$SCRATCH/home" XDG_STATE_HOME="$SCRATCH/state" \
  nix-channel --update
```

- The heredoc **must match `/root/.nix-channels` exactly** (one `<url> <name>` per line). Channel branches change across releases — never trust a stale copy.
- If `rm -rf` fails on a leftover root-owned scratch (aborted pkexec attempt), `pkexec rm -rf "$SCRATCH"` first.
- Result: scratch profile `$SCRATCH/state/nix/profiles/channels/` with one symlink per channel. The profile is just symlinks; the store paths live in `/nix/store`.
- Fast (network fetch, no build). If it fails (e.g. network), nothing real was touched — fix and retry.

### A2 — build with diff (plain user, long step)

Pin the build to the exact scratch channel store paths:

```bash
NEW_NIXOS=$(readlink -f "$SCRATCH/state/nix/profiles/channels/nixos")
NEW_UNSTABLE=$(readlink -f "$SCRATCH/state/nix/profiles/channels/nixpkgs-unstable")
```

Sanity-check the pins before the long build (fast; catches a botched fetch):

```bash
NIX_PATH="nixpkgs=$NEW_NIXOS" nix-instantiate --eval --strict --raw -E 'lib.version'
NIX_PATH="nixpkgs-unstable=$NEW_UNSTABLE" nix-instantiate --eval --strict --raw -E 'lib.version'
```

(Expect a `26.05.x` release and an unstable version respectively.) Then build (background + poll, minutes):

```bash
NIX_PATH="nixpkgs=$NEW_NIXOS:nixpkgs-unstable=$NEW_UNSTABLE:nixos-config=/etc/nixos/configuration.nix" \
  nixos-rebuild build --diff --show-trace > /tmp/nixos-upgrade-build.log 2>&1
```

Notes:

- **No `--upgrade-all`**: the channels were already fetched in A1, and `--upgrade-all` would try to re-fetch the *root* channels (root-only; it hard-errors as a plain user). The explicit `NIX_PATH` maps exactly what `--upgrade-all` would have expanded: `nixpkgs` ← the `nixos` channel, `nixpkgs-unstable` ← itself.
- The `--diff` output (`nix store diff-closures /run/current-system <new>`) goes to **stderr** with ANSI colors — strip them with `sed 's/\x1b\[[0-9;]*m//g'`.
- The new toplevel path appears in the log twice: the `>>> /nix/store/...` diff header line and the final `Done. The new configuration is /nix/store/...` line. Grep for it:
  ```bash
  grep -oE '/nix/store/[a-z0-9]+-nixos-system-[a-z0-9.]+-[a-f0-9]+' /tmp/nixos-upgrade-build.log | tail -1
  ```
- If the build fails on creating the result link over a stale root-owned `/tmp/result` (left by an older pkexec build), `pkexec rm -f /tmp/result` and retry.
- **If the build fails (otherwise):** show the user the tail of the log and stop. Nothing real was mutated — no rollback needed. Retry against the same scratch channels, or re-run A1 to pick up newer revisions; clean up per the A4-decline branch when done.

### A3 — present the summary

Use the shared diff format above. Always also check the **kernel** (it's often not in the named diff lines):

```bash
nix path-info --recursive <old-toplevel> <new-toplevel> \
  | grep -oE '/nix/store/[a-z0-9]+-linux-[0-9][^/]*' | sort -u
```

Compare against `uname -r`, and add a line like `Kernel: linux 7.1.8 (unchanged)` or `7.1.8 → 7.2.1 (reboot required)`.

Mention that `--diff` compares against `/run/current-system` (last activated), which can differ from `/run/booted-system` if a switch happened after the last boot.

Also state explicitly: the real root channel profile is still at the A0 revisions; on confirmation it will move to exactly the store paths this build used.

### A4 — confirm, then commit + switch (or clean up)

**Do not switch without an explicit yes.** Ask:

> "Build succeeded and the diff is as above. Shall I commit the root channels to the revisions this build used and run `nixos-rebuild switch --store-path <new-toplevel>`? That activates the new system. If not, I'll remove the scratch state and nothing on the system changes."

**Declined:** clean up (nothing to roll back — the real root profile was never touched):

```bash
rm -rf "$SCRATCH"
```

Verify the root channels still match the A0 paths (they will — they were never modified); state is identical to before the attempt. (A stale root-owned `/tmp/result` from an older pkexec run, if any, can be removed with `pkexec rm -f /tmp/result`; GC collects the declined toplevel once unreferenced.)

**Confirmed:** first commit the channels to exactly the store paths the build used (pkexec, approval per the `elevated-permissions` skill):

```bash
pkexec env PATH="/run/current-system/sw/bin:/run/current-system/bin:/run/wrappers/bin:/usr/sbin:/usr/bin:/sbin:/bin" \
  nix-env -p /nix/var/nix/profiles/per-user/root/channels \
  --install "$NEW_NIXOS" "$NEW_UNSTABLE"
```

- Installing channel store subdirectories creates the standard channel layout and names the entries after the subdirectory — `nixos`, `nixpkgs-unstable` (verified to match a real channel profile). The profile gains a new generation; history is preserved.
- Verify **before** the switch:
  ```bash
  readlink -f /nix/var/nix/profiles/per-user/root/channels/nixos             # must equal $NEW_NIXOS
  readlink -f /nix/var/nix/profiles/per-user/root/channels/nixpkgs-unstable  # must equal $NEW_UNSTABLE
  ```
- If a name is wrong or a path is unexpected: **stop, do not switch**; roll the profile back with `pkexec nix-channel --rollback <N>` (the A0 generation number — `--rollback` takes an absolute generation number, not an offset) and report.

Then switch (pkexec). `<new-toplevel>` is the path grepped in A2; reuse the A2 `NIX_PATH` (it equals the just-committed channel dirs):

```bash
pkexec env PATH="/run/current-system/sw/bin:/run/current-system/bin:/run/wrappers/bin:/usr/sbin:/usr/bin:/sbin:/bin" \
  NIX_PATH="nixpkgs=$NEW_NIXOS:nixpkgs-unstable=$NEW_UNSTABLE:nixos-config=/etc/nixos/configuration.nix" \
  nixos-rebuild switch --store-path /nix/store/<new-toplevel>
```

`--store-path` skips the evaluation and build phases entirely and activates exactly the store path built in A2 — no drift, no re-evaluation. The root channels are left at the committed generation: a confirmed upgrade advances channel state, and later no-upgrade rebuilds (system or home) evaluate against them. (A plain `nixos-rebuild switch` would also work — it would re-evaluate against the just-committed channels and produce the same toplevel — but `--store-path` is faster and can't drift.)

Then:

- Verify: `readlink -f /run/current-system` points at the new toplevel.
- Clean up the scratch (plain user — it's user-owned): `rm -rf "$SCRATCH"`.
- If the kernel changed, tell the user a reboot is needed for the new kernel/initrd.
- The home environment was not touched by this flow. If the user wants their home env on the new root-channel packages, a plain `home-manager switch` (no-upgrade path) picks them up — no channel moves needed.
- Escape hatch if the new system turns out broken: `nixos-rebuild switch --rollback` (pkexec, same env vars; one toplevel generation back). If the new *channels* are the problem, roll them back to `N` (pkexec `nix-channel --rollback <N>`) — old channel generations are retained, never auto-pruned.

## Flow B — Home Manager upgrade (both hosts)

The hm build and activation are always plain user (user channels + home-manager profile are user-owned). Channel elevation differs by host:

- **NixOS host:** the root channels are **not** touched — Flow B is 100% plain user.
- **macOS host:** `pkgs` resolves to the **root** channels, so Flow B fetches them too — under `sudo` (no pkexec on macOS; same ask-before-each-invocation rule as the `elevated-permissions` skill).

The system toplevel is never touched.

### B0 — snapshot

NixOS host:

```bash
readlink ~/.local/state/nix/profiles/channels          # → channels-<M>-link ; record M = pre-upgrade generation
readlink -f ~/.local/state/nix/profiles/channels/home-manager
readlink -f ~/.local/state/nix/profiles/channels/unstable
readlink -f ~/.local/state/nix/profiles/home-manager   # current hm generation = old side of the diff
```

Record `M` (rollback target), both user-channel store paths (rollback verification), and the current hm generation (baseline for the diff).

macOS host — same shape, **plus the root channels** (they're part of the upgrade here; the readlinks are world-readable, no elevation needed for the snapshot). On first use record the host's actual channels and paths (fill them into Background → macOS host, then the flow below is literal):

```bash
readlink /nix/var/nix/profiles/per-user/root/channels   # → channels-<N>-link ; record N (verify this path exists on the host)
readlink -f /nix/var/nix/profiles/per-user/root/channels/<each root channel>
nix-channel --list                                      # user channel names on this host
readlink ~/.local/state/nix/profiles/channels           # (may be ~/.nix-defexpr/channels)
readlink -f <user-channels-profile>/<each user channel>
readlink -f ~/.local/state/nix/profiles/home-manager    # current hm generation
```

Record `N` + root-channel store paths (root rollback target/verification), `M` + user-channel store paths (user rollback target/verification), and the current hm generation (baseline for the diff).

### B1 — fetch channels + test build

**macOS host — root channels first (sudo).** `pkgs` in `home.nix` resolves to the root channels, so they must move for a real package upgrade. **Ask the user for approval first** (same rule as Flow A):

```bash
sudo nix-channel --update > /tmp/hm-root-channels.log 2>&1   # root's channels
```

Then the user side (plain user) on **both hosts**. Run in the background and poll (quick channel fetch; the build itself can take minutes if new packages need building):

```bash
nix-channel --update > /tmp/hm-channels.log 2>&1          # user's channels
home-manager build --no-out-link > /tmp/hm-build.log 2>&1 # test build — never activates
```

- `nix-channel --update` (no args) updates the **user's** channels profile and commits a new generation of it — fetch mutates state, so it is rolled back on decline/failure.
- `home-manager build` is the **test build**: it evaluates `home.nix`, builds the new `home-manager-generation`, and prints its store path as the first line of output — it does **not** touch the home-manager profile, no activation, no symlinks changed. `--no-out-link` skips the `./result` symlink (without it, `./result` appears in the CWD).
- The new generation path:
  ```bash
  grep -oE '/nix/store/[a-z0-9]+-home-manager-generation' /tmp/hm-build.log | tail -1
  ```
- Do **not** rely on `home-manager build --dry-run`: in the non-flake CLI it is ignored in the build path (observed on 26.05-pre) — it behaves exactly like a plain build.
- **If the hm build fails:** show the user the tail of the log and stop. The channels are already updated — roll them back (user to `M`, and on the macOS host also root to `N` — commands in B3), verify against the B0 paths, then retry `home-manager build` **without** re-fetching.

### B2 — present the summary (hm diff)

```bash
nix store diff-closures <old-hm-generation> <new-hm-generation>
```

`<old-hm-generation>` = current profile target recorded in B0, `<new-hm-generation>` = path grepped from the build log in B1. Shared diff format above, as a table titled "Home Manager" (the user's home environment: editors, shells, python envs, …).

Expectations by host:

- **NixOS host:** the diff typically contains only the home-manager module set (user `home-manager` channel) and whatever the user's `unstable` channel provides — home *package* versions are pinned by the **root** channels (see Background) and move only after a confirmed Flow A advanced them. A small diff is expected, not a failure.
- **macOS host:** `pkgs` in `home.nix` resolves to the **root** channels, which this flow fetches — so the diff is the real package-upgrade summary.

### B3 — confirm, then activate (or roll back)

Same discipline as A4: **no activation without an explicit yes.** Ask:

> "Home-manager build succeeded and the diff is as above. Shall I activate generation `<new-hm-generation>`? That keeps your channels at the new generation. If not, I'll roll them back to the pre-upgrade generation and nothing changes."

**Declined:** roll back the user channels (plain user): `nix-channel --rollback <M>`; on the macOS host also the root channels (sudo): `sudo nix-channel --rollback <N>`. Verify `readlink -f` on every channel matches the B0 paths. Done. (Same rule: roll back to the recorded generation number, never bare "one back".)

**Confirmed** — activate **exactly the generation built in B1** (plain user):

```bash
GEN=<new-hm-generation>
nix-env --profile ~/.local/state/nix/profiles/home-manager --set "$GEN"
"$GEN/activate" --driver-version 1
```

This is the home-manager equivalent of `--store-path`: exactly the diffed generation is activated, without re-evaluating `home.nix`. It is precisely what `home-manager switch` does internally (build → `nix-env --profile … --set` → run the activate script), only the build is skipped. A plain `home-manager switch` would re-evaluate and rebuild the same generation (channels are at the new generation) — wasteful, and it could drift from the diffed store path if anything else changed meanwhile.

Then:

- Verify: `readlink -f ~/.local/state/nix/profiles/home-manager` points at the new generation, and `home-manager generations` marks it `(current)`.
- Escape hatch if the new home env turns out broken: `home-manager switch --rollback` (one generation back, no new generation created).
- The channels stay at the new generation (confirmed upgrade advances channel state) — user channels on both hosts, plus the root channels on the macOS host. Future no-upgrade `home-manager build`/`switch` runs evaluate against them.

## Background

### NixOS host (this machine)

- Classic (non-flake) NixOS. Config: `/etc/nixos/configuration.nix` (symlink to `~/.config/nixos/homepc`), shared bits in `~/.config/nixos/common.nix`.
- `nixos-rebuild` on this system is **nixos-rebuild-ng** (supports `--diff`, `--upgrade`, `--upgrade-all`, `--store-path`).
- `pkgs` = root's **`nixos` channel** (`nixos-26.05` branch). `unstable` (used in `common.nix` for e.g. `kiro-cli`, `btop-cuda`, `_1password-cli`) = root's **`nixpkgs-unstable` channel**.
- Kernel: `pkgs.linuxPackages_latest` (from the `nixos` channel). Kernel/initrd changes only take effect after a reboot.
- Root channels live in `/nix/var/nix/profiles/per-user/root/channels/` (root-owned).
- Home Manager: classic (no flakes). CLI: `home-manager` **26.05-pre** from the user's nix-env profile (`~/.nix-profile/bin/home-manager`). Config: `~/.config/home-manager/home.nix`.
- **User's channels profile**: `~/.local/state/nix/profiles/channels` (alias `~/.nix-defexpr/channels`; note `/nix/var/nix/profiles/per-user/javi/` does **not** exist). User-owned. Two channels: `home-manager` (provides `<home-manager>`, the module set the CLI evaluates) and `unstable` (provides `<unstable>`, currently unused by `home.nix`).
- **What `home-manager build` actually resolves**: `pkgs` = `<nixpkgs>` = root's `nixos` channel; the `unstable` variable in `home.nix` = `import <nixpkgs-unstable>` = root's `nixpkgs-unstable` channel. Consequence: Flow B (user channels only) refreshes the home-manager module set but **not** home package versions — those move only when a confirmed Flow A has advanced the root channels. The `home-manager` CLI itself never fetches any channel (`build`/`switch` only evaluate + build).
- **home-manager profile**: `~/.local/state/nix/profiles/home-manager` (the CLI picks `$XDG_STATE_HOME/nix/profiles`). List generations with `home-manager generations`; `nix profile history --profile …` has the same "No changes" quirk as the channel profiles.
- Update the user's channels with `nix-channel --update`; roll them back with `nix-channel --rollback <M>` (both plain user).

### macOS host

- Classic home-manager (channels), no flakes.
- `pkgs` in `home.nix` resolves to the **root** channels → Flow B must fetch them (sudo); that's what makes this the full home upgrade (module set **and** package versions).
- Root channels are root-owned: fetch/rollback under `sudo` (no pkexec on macOS — apply the `elevated-permissions` ask-first rule to `sudo`). User channels + home-manager profile are user-owned → plain user.
- **Biometric approval for `sudo` (recommended):** see the macOS section of the `elevated-permissions` skill — the Touch ID PAM module setup (plus Apple Watch approval) makes `sudo` show a Touch ID prompt instead of a password prompt.
- **Fill in from first run** (run the B0 macOS checklist, then record here): root channels profile path + channel names, user channel names (`nix-channel --list`), CLI install source (`which home-manager`), user channels profile path, home-manager profile path.

## Elevation — NixOS host (Flow A) + macOS host (Flow B root channels)

- Flow A needs root for **only two steps, plus one read**: committing the confirmed channel revisions into the root profile (`nix-env --install`, A4), the activation (`nixos-rebuild switch --store-path`, A4), and the read-only `pkexec cat /root/.nix-channels` (A1). The scratch fetch (A1) and the build (A2) run as the plain user — the scratch profile is user-owned and the build touches only `/nix/store`.
- `switch` updates the system profile and runs activation — root-only. The root channel profile is root-owned — hence those steps run under `pkexec` (per the `elevated-permissions` skill: **ask the user for approval before each pkexec invocation**).
- NixOS host: Flow B never needs elevation (user channels only). macOS host: Flow B's **root channel fetch + rollback** run under `sudo` (pkexec doesn't exist on macOS — apply the same ask-before-each-invocation rule); everything else in Flow B is plain user.
- Running under pkexec resets parts of the environment, so **always set `PATH` (and `NIX_PATH` where evaluation happens) explicitly** — otherwise `<nixpkgs>`, `<nixos-config>` and `<nixpkgs-unstable>` may not resolve. For the Flow A pkexec steps:

```bash
PATH="/run/current-system/sw/bin:/run/current-system/bin:/run/wrappers/bin:/usr/sbin:/usr/bin:/sbin:/bin"
NIX_PATH="nixpkgs=$NEW_NIXOS:nixpkgs-unstable=$NEW_UNSTABLE:nixos-config=/etc/nixos/configuration.nix"   # the A2 scratch pins; not needed for nix-env --install
```

- **Never export or modify `PATH` before invoking `pkexec`.** The default PATH resolves `pkexec` to the setuid wrapper at `/run/wrappers/bin/pkexec`; other locations (e.g. `/run/current-system/sw/bin/pkexec`) are not setuid and fail with "pkexec must be setuid root". Pass `PATH` via `env PATH=...` *inside* the pkexec command instead (the standard form in this skill).
- Historical: `nixos-rebuild --upgrade/--upgrade-all` re-fetches **root's** channels and hard-errors as non-root ("you must also pass '--sudo' or run the command as root") — that's why Flow A fetches in a scratch profile (A1) instead. (`--upgrade-all` also refreshes `nixpkgs-unstable`, which plain `--upgrade` would skip; the A2 `NIX_PATH` pins both channels explicitly.)

## Gotchas

- Flow A runs as a plain user **except** the commit and the switch (A4): the scratch fetch and the build need no root. If you ever reach for `--upgrade-all` (channel fetch via nixos-rebuild), it hard-errors as non-root — that's why A1 fetches into a scratch profile instead.
- The global flake registry has `flake:nixpkgs` pinned to a live unstable tarball — irrelevant for this classic rebuild (which resolves via NIX_PATH/channels), don't let it confuse the summary.
- `nixos-rebuild build` (non-flake) resolves to `import <nixpkgs/nixos>` with `configuration = <nixos-config>`; no flake or `--file` arguments are needed.
- Any channel update on a **real** profile commits a generation (`--upgrade-all` does one `nix-channel --update <name>` per channel, each its own generation; a plain `nix-channel --update` commits one). So roll back to the recorded generation number, never "one back" — the rule for Flow B and for the Flow A escape hatch. Note `nix-channel --rollback` takes an **absolute generation number**, not an offset: bare `nix-channel --rollback 1` would jump to generation 1.
- Channel generations are never auto-pruned (only explicit `nix-env --delete-generations` removes them), so pre-upgrade generations survive across upgrades. Old generations keep their channel store paths valid and GC-protected — if a rollback isn't possible (e.g. the old generation was pruned), retry the build with `NIX_PATH` pinned to the A0 snapshot store paths (explicit `nixpkgs=…` / `nixpkgs-unstable=…` entries) instead of re-fetching.
- Confirmed upgrades intentionally leave channels at the new generation; declined and failed attempts must leave them at the snapshot generation. Always verify with `readlink -f` against the snapshot paths before declaring either branch done.
- On the NixOS host, a Flow B that runs without a preceding Flow A shows a small diff (module set only) — expected, because home package versions are pinned by the root channels. After a confirmed Flow A, a plain `home-manager switch` (no-upgrade path) brings the home env onto the new packages with no channel moves.
- On the NixOS host home-manager is classic: the CLI comes from the user's nix-env profile, not a flake or the channel. Updating the channels does **not** update the CLI binary; to bump it, `nix-env -u home-manager` (after the channel/repo it was installed from has moved).
- `home-manager build`/`switch` never fetch channels — neither the user's nor the root's. A "home-manager upgrade" that skips the fetch steps (B1) is just a rebuild against the same channels — on the macOS host the **root** fetch is the one that carries the package versions.
- `home-manager build` (non-flake) ignores `--dry-run` — it does the full build either way. A plain `build` never touches the profile; the `./result` it leaves (unless `--no-out-link`) is just a symlink in the CWD, not a GC root.
- The user's channels profile and the home-manager profile live under `~/.local/state/nix/profiles/` (XDG state), not `/nix/var/nix/profiles/per-user/<user>/` — that directory does not exist on the NixOS host.
- Root `nix-channel` **ignores `XDG_STATE_HOME`** (verified on nix 2.34.8): under pkexec it always commits to the real root channel profile, even with a scratch `XDG_STATE_HOME` exported. Plain-user `nix-channel` **honors** `XDG_STATE_HOME` (profile at `$XDG_STATE_HOME/nix/profiles/channels`) and reads its channel list from `$HOME/.nix-channels`. That asymmetry is why A1 fetches as the plain user with scratch `HOME` + `XDG_STATE_HOME`. Side effect: any `nix-channel` invocation (even read-only `--list-generations`) auto-creates a profile skeleton in the state dir it resolves to — with a scratch `XDG_STATE_HOME` that's harmless scratch state, but don't run plain `nix-channel` against a real state dir unless that's what you want.
- The A1 scratch is user-owned: cleanup is a plain `rm -rf "$SCRATCH"`. If a leftover scratch is root-owned (e.g. from an aborted pkexec attempt), `pkexec rm -rf "$SCRATCH"` is needed instead.
