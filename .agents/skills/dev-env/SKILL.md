---
name: dev-env
description: >-
  Get any missing command, runtime, tool, or library via nix-shell or podman. MUST be loaded the moment a command fails with "command not found" or "No such file or directory", or with EACCES when the binary itself is missing (permission errors on existing binaries belong to the elevated-permissions skill) — or whenever a tool that is not already on PATH is needed, even for one-off use (e.g. nmap, avahi, git, jq, python3, node, ffmpeg). Do NOT improvise workarounds or paper over missing tools with shell one-liners; load this skill first. NEVER install anything into the machine itself: no root/sudo installs, no `npm install`/`npm -g`/`npx --package`, no `pip`/`pipx`, no `apt`/`dnf`/`brew`/`cpanm`, no nix profile/`nix-env` installs, no nixos-rebuild or nixpkgs/systemd edits — only nix-shell (ephemeral) or podman (containers).
---

## Hard rule: no installs on the machine

- **Deny:** `nixos-rebuild`, editing the NixOS system profile/config, any root (`sudo`/`su`) package install, `nix profile install`, `nix-env -i`, package-manager installs like `npm install` / `npm -g` / `npx --package`, `pip install` / `pipx`, `apt` / `dnf` / `brew` / `cpanm`, or anything that persists a package on the machine or mutates its state.
- **Allow:** `nix-shell` (ephemeral) and `podman`/`docker` containers only.
- If a task truly requires a persistent or system-level install, stop and ask the user instead of doing it.

# Package Install

## Strategy

1. **nix-shell** — Preferred. Ephemeral, no root, reproducible.
2. **podman** — Fallback when nix-shell is unavailable or unsuitable.

## nix-shell

### Quick shell with packages

```bash
nix-shell -p nodejs python312 gcc glibc.dev
```

### Flake devShell (avoid when possible)

Skip flakes by default — `nix-shell -p` above needs no flake evaluation. Only
use `nix develop` when the project defines the exact environment you need in a
`flake.nix` devShell:

```bash
nix develop .
```

If `nix-shell -p` can't find nixpkgs (no channel configured), flake references
work via the registry instead:

```bash
nix shell nixpkgs#jq --command jq --version
```

### Run a single command

```bash
nix-shell -p nodejs --run "node --version"
```

### Interactive shell with specific version

```bash
nix-shell -p nodejs_22 python312
```

### Common package names

| Need | nixpkgs package |
|------|-----------------|
| Node.js | `nodejs`, `nodejs_20`, `nodejs_22` |
| Python | `python312`, `python313` |
| Rust | `rustc`, `cargo` |
| Go | `go` |
| Java | `jdk17`, `jdk21` |
| Docker CLI | `docker` |
| GCC | `gcc` |
| CMake | `cmake` |
| Make | `make` |
| Git | `git` |
| jq | `jq` |
| libxml2 | `libxml2.dev` |
| OpenSSL | `openssl` |
| pkg-config | `pkg-config` |
| curl | `curl` |
| wget | `wget` |
| tree | `tree` |
| ripgrep | `ripgrep` |
| fzf | `fzf` |
| tmux | `tmux` |
| vim | `vim` |
| postgresql | `postgresql` |
| redis | `redis` |
| sqlite | `sqlite` |
| ffmpeg | `ffmpeg` |
| imagemagick | `imagemagick` |

For dev libraries, append `.dev` (e.g. `libxml2.dev`, `glibc.dev`).

## podman fallback

Use when nix-shell is unavailable or the project requires a specific OS environment.

### Run a command with a package installed

```bash
podman run --rm -it -v "$PWD":/work -w /work docker.io/library/node:22-alpine node --version
```

### Interactive shell

```bash
podman run --rm -it -v "$PWD":/work -w /work docker.io/library/python:3.12-slim
```

### Common container images

| Need | Image |
|------|-------|
| Node.js | `docker.io/library/node:22-alpine` |
| Python | `docker.io/library/python:3.12-slim` |
| Rust | `docker.io/library/rust:1-slim` |
| Go | `docker.io/library/golang:alpine` |
| Java | `docker.io/library/eclipse-temurin:21-jdk-alpine` |
| Ubuntu base | `docker.io/library/ubuntu:24.04` |
| Debian base | `docker.io/library/debian:bookworm-slim` |

### Build and run in container

```bash
podman run --rm -it -v "$PWD":/work -w /work \
  docker.io/library/node:22-alpine \
  sh -c "npm install && npm run build"
```

## Tips

- Skip flakes when possible: prefer `nix-shell -p` (no flake evaluation); use `nix develop` only when the project defines its environment as a flake devShell.
- With podman, always mount the working directory and set `-w` to avoid copying source.
- When unsure of a nixpkgs package name, search: `nix search nixpkgs <keyword>` or check <https://search.nixos.org/packages>.

