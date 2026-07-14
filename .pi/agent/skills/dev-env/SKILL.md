---
name: dev-env
description: Set up a development environment with the right runtimes, tools, and libraries. Use nix-shell for ephemeral environments (preferred), podman containers as fallback, nix profile for persistent installs.
---

# Package Install

## Strategy

1. **nix-shell** — Preferred. Ephemeral, no root, reproducible.
2. **podman** — Fallback when nix-shell is unavailable or unsuitable.
3. **nix-env / nix profile** — Last resort for persistent installs (user-level, no root).

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

## nix profile (persistent, user-level)

When a package must persist across sessions without root:

```bash
nix profile install nixpkgs#nodejs_22
nix profile install nixpkgs#ripgrep
```

List and remove:
```bash
nix profile list
nix profile remove nodejs_22
```

## Tips

- Use `--impure` with `nix develop` when the project needs access to the host environment (env vars, home dir).
- Prefer `-p` with `nix-shell` for simple one-off needs over `nix develop`.
- With podman, always mount the working directory and set `-w` to avoid copying source.
- When unsure of a nixpkgs package name, search: `nix search nixpkgs <keyword>` or check <https://search.nixos.org/packages>.

