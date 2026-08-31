---
name: dev-env
description: Get any missing command, runtime, tool, or library via nix-shell or podman. MUST be loaded the moment a command fails with "command not found", "No such file or directory", or EACCES — or whenever a tool that is not already on PATH is needed, even for one-off use (e.g. nmap, avahi, git, jq, python3, node, ffmpeg). Do NOT improvise workarounds or paper over missing tools with shell one-liners; load this skill first and use nix-shell -p (preferred) or podman as fallback. NEVER install anything into the machine itself - no system-wide/root installs, no `npm install` / `npm -g` / `npx --package`, no `pip install` / `pipx`, no `apt` / `dnf` / `brew` / `cpanm`, no nixos-rebuild or nixpkgs edits, no nixos/systemd changes, no nix profile / nix-env installs — only nix-shell (ephemeral) or podman (containers).
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

### From a flake

```bash
nix develop github:nixos/nixpkgs/nixos-unstable#devShells.x86_64-linux.default --impure
```

Or if the project has a `flake.nix`:
```bash
nix develop .
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
| Go | `docker.io/library/golang:1.22-alpine` |
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

- Use `--impure` with `nix develop` when the project needs access to the host environment (env vars, home dir).
- Prefer `-p` with `nix-shell` for simple one-off needs over `nix develop`.
- With podman, always mount the working directory and set `-w` to avoid copying source.
- When unsure of a nixpkgs package name, search: `nix search nixpkgs <keyword>` or check <https://search.nixos.org/packages>.

