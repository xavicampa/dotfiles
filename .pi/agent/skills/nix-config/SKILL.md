---
name: nix-config
description: Add options, services, and packages to NixOS and home-manager configuration. Triggered when the user wants to add, enable, or configure a NixOS service, system program, option, or home-manager program ("add X to my nix config", "enable Y in NixOS", "add Z to home-manager", "configure the <service> module"). For one-off tool runs without config changes, use the dev-env skill instead.
---

# NixOS & home-manager configuration

Add options, services, and packages to the NixOS / home-manager configs.
Verify option syntax locally **before** editing, then build (no activation)
and confirm with the user before activating.

## Layout (this system)

- `/etc/nixos` is a **symlink** to `~/.config/nixos/<machine>` — find the
  active machine with `readlink -f /etc/nixos` (here `homepc`; a sibling
  `dell/` exists).
- Machine config: `~/.config/nixos/<machine>/configuration.nix`
  - imports `../common.nix` and `./hardware-configuration.nix`
    (hardware file is auto-generated — do not hand-edit)
- Shared config: `~/.config/nixos/common.nix` — options that apply to all
  machines go here; machine-specific ones in `configuration.nix`
- Home-manager: `~/.config/home-manager/home.nix` (classic invocation;
  single file, user `javi`)
  - **Shared with a macOS host**: `home.nix` has a `macos =
    builtins.pathExists "/Users/javi"` flag — keep HM changes
    cross-platform-safe (or guard them) unless the user says otherwise
- Both NixOS configs expose `unstable = import <nixpkgs-unstable> {
  config.allowUnfree = true; }` (`_module.args` in common.nix; module arg in
  configuration.nix). `pkgs` = stable nixpkgs (root `nixos` channel);
  prefer `unstable.<pkg>` when the package is newer/unfree there
- Configs are **not** under git — make surgical edits, keep diffs minimal

## Where changes go

- User programs, dotfiles, editors, CLI tools → home-manager
- System services, desktop, boot, networking, kernel, users → NixOS
- Applies to several machines → `common.nix`, else the machine file

## 1. Find the right package / option

**Option lookup (local, authoritative, offline)** — always confirm the exact
path and type *before* writing config:

- NixOS: `nixos-option <path>` → Value/Default/Type/Description/Example,
  plus "Declared by" (channel source file — open it for full docs) and
  "Defined by" (user config)
- NixOS browse: `nixos-option -r <prefix>` (e.g. `nixos-option -r
  programs.hyprland`)
- Home-manager: `home-manager option <path>` (same output; `--recursive`
  to browse a subtree; a partial path lists what the attribute set
  contains)
- Unknown path → `error: Couldn't resolve config path '<path>'` — use this
  to validate candidate options before editing

**Package search (local, against the user's own channels)**:

```bash
nix eval --impure --json --expr '
let
  pkgs = import <nixpkgs> { config.allowUnfree = true; };  # or <nixpkgs-unstable>
  lib = pkgs.lib;
  in lib.mapAttrs (_: v: toString (v.version or "?"))
       (lib.filterAttrs (n: _: n != "lib" && lib.hasInfix "KEYWORD" n) pkgs)
'
```

(`--impure` resolves `<nixpkgs>` / `<nixpkgs-unstable>` from NIX_PATH to the
same root channels the configs use. Replace `KEYWORD` with the search term.)

Search `<nixpkgs>` (stable) first; if a package only exists in unstable, say
so — the configs already bind `unstable`, so no channel upgrade is needed.

Pitfall: `nix search <store-path>` fails on this nix version ("does not
correspond to a Nix language value") — use the `nix eval` form above.

**Online (when local search is inconclusive)**: `web_search` for
"nixpkgs <name>" / "nixos <service>"; module docs at
https://nixos.wiki/wiki/<PackageName>; human-facing indexes
https://search.nixos.org/packages and /options (channel 26.05 / unstable).
If the option/module only exists in a newer nixpkgs, suggest the
**nix-upgrade** skill (channel update) instead of patching.

## 2. Draft-validate before touching real files

**Home-manager** (edit a copy first):

1. `cp ~/.config/home-manager/home.nix /tmp/draft-home.nix`, apply the edit
   to the copy
2. `home-manager -f /tmp/draft-home.nix build --no-out-link` — full strict
   check; unknown options error with "The option `…' does not exist" +
   "Did you mean …"
3. If green, apply the edit to the real `home.nix`

**NixOS** (overlay draft — a plain /tmp copy of the config breaks its
relative `../common.nix` import):

```nix
# /tmp/draft.nix
{
  imports = [ /home/javi/.config/nixos/<machine>/configuration.nix ];
  # proposed change:
  services.<x>.<y> = ...;
}
```

`NIXOS_CONFIG=/tmp/draft.nix nixos-rebuild dry-build` — same strict check.
Pitfall: the overlay must import the **canonical** `~/.config/nixos/...`
path, not `/etc/nixos/...` — `import` paths in file bodies are not
symlink-canonicalized, so the relative `../common.nix` import would break.

## 3. Build (validates, does not activate)

- NixOS, no root: `nixos-rebuild dry-build` (fast eval check, ~10 s) →
  `nixos-rebuild build` (full build, no activation). On failure: show the
  error, fix, repeat.
- Home-manager, no root: `home-manager build --no-out-link`. On failure:
  fix, repeat.

## 4. Activate — always confirm with the user first

- NixOS: `pkexec nixos-rebuild switch` (needs root — see the
  **elevated-permissions** skill). `nixos-rebuild` is nixos-rebuild-ng:
  `--diff` shows which files will change; `--dry-run` simulates. Do not
  reboot unless the user asks.
- Home-manager: `home-manager switch` (no root needed).

## Coordination

- **nix-upgrade** — channel updates when a package/option is missing from
  the current stable channel
- **dev-env** — running a tool once without adding it to any config
- **elevated-permissions** — `pkexec` for `nixos-rebuild switch`
