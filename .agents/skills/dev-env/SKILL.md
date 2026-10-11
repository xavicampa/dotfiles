---
name: dev-env
description: >-
  Get any missing command, runtime, tool, or library via nix-shell or podman. Load the moment a command fails with "command not found" or "No such file or directory", or with EACCES when the binary itself is missing (permission errors on existing binaries belong to the elevated-permissions skill) — or whenever a tool that is not already on PATH is needed, even for one-off use (e.g. nmap, avahi, git, jq, python3, node, ffmpeg). Do not paper over missing tools with shell workarounds; load this skill first. NEVER install anything into the machine itself: no root/sudo installs, no `npm install`/`npm -g`/`npx --package`, no `pip`/`pipx`, no `apt`/`dnf`/`brew`/`cpanm`, no nix profile/`nix-env` installs, no nixos-rebuild or nixpkgs/systemd edits — only nix-shell (ephemeral) or podman (containers).
---

## Hard rule: never install on the machine

Allow only `nix-shell` (ephemeral) and `podman`/`docker` containers. Deny anything that persists a package or mutates system state: `sudo`/`su` installs, `nix profile install`, `nix-env -i`, `npm install` / `npm -g` / `npx --package`, `pip` / `pipx`, `apt` / `dnf` / `brew` / `cpanm`, `nixos-rebuild`, NixOS config/system-profile edits. If a task truly needs a persistent or system-level install, stop and ask the user.

## nix-shell — preferred

Ephemeral, no root, reproducible.

```bash
nix-shell -p nodejs python312 gcc glibc.dev    # interactive shell
nix-shell -p nodejs --run "node --version"     # single command
nix-shell -p nodejs_22 python313               # pinned versions
nix shell nixpkgs#jq --command jq --version    # if no channel: flake ref via registry
nix develop .                                  # only if the repo defines the devShell you need
```

Prefer `nix-shell -p` (no flake evaluation); `nix develop` only when `flake.nix` already defines the environment you need.

Unknown package name → `nix search nixpkgs <keyword>` or <https://search.nixos.org/packages>. Names usually equal the command (`jq`, `make`, `cmake`, `gcc`, `go`, `cargo`, `ffmpeg`, `redis`, …); non-obvious:

| Need | nixpkgs |
|------|---------|
| Node.js | `nodejs` (latest), `nodejs_20`, `nodejs_22`, `nodejs_24` |
| Python | `python312`, `python313`, `python314` |
| Java | `jdk17`, `jdk21` |
| telnet / ftp / nslookup / ping | `inetutils` |
| ripgrep (`rg`) | `ripgrep` |
| Docker CLI | `docker` |
| dev headers/libs | append `.dev` — `libxml2.dev`, `glibc.dev` |

## podman — fallback

When nix-shell is unavailable/unsuitable or a specific OS is required. Always mount the working dir and set `-w` so nothing is copied; installs are allowed only *inside* the container.

```bash
podman run --rm -it -v "$PWD":/work -w /work docker.io/library/node:22-alpine node --version
podman run --rm -it -v "$PWD":/work -w /work docker.io/library/python:3.12-slim
podman run --rm -it -v "$PWD":/work -w /work docker.io/library/ubuntu:24.04 sh -c "npm install && npm run build"
```

Images: `docker.io/library/` + `node:22-alpine`, `python:3.12-slim`, `rust:1-slim`, `golang:alpine`, `eclipse-temurin:21-jdk-alpine`, `ubuntu:24.04`, `debian:bookworm-slim`.
