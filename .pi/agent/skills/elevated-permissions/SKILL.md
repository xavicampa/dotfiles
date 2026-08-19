---
name: elevated-permissions
description: Execute commands requiring elevated (root) permissions. Triggered when commands fail with access denied, permission denied, EACCES, or similar errors — OR when sudo is required or mentioned — OR when the task involves system administration, hardware inspection (lspci, lshw, dmidecode), package management, service control, disk/mount operations, firewall rules, or any operation that may need root. Always load this skill before running any command that might require elevated permissions. On macOS there is no pkexec — this skill documents the `sudo` fallback and how to enable Touch ID / Apple Watch approval via the Touch ID PAM module.
---

# pkexec

Always use `pkexec` instead of `sudo` for elevated permissions.

## When this skill applies

This skill is triggered whenever a command fails with elevated-permission errors, including:

- **Permission denied** / **EACCES**
- **Access denied**
- **Operation not permitted** / **EPERM**
- **Only root can do** / **must be root**
- **cannot open / read / write** (on system paths like `/etc/`, `/var/`, `/usr/`)
- Any error indicating the current user lacks the required privileges

When triggered, re-run the failing command with `pkexec` (or `sudo` on macOS — see below) after obtaining user approval.

## macOS — `sudo` instead of `pkexec`

`pkexec` does not exist on macOS. Use `sudo` there, with the same ask-first rule as below.

### Biometric approval (recommended)

Apple ships a Touch ID PAM module (`/usr/lib/pam/pam_tid.so`). Enable it once and `sudo` shows a Touch ID prompt on the Mac instead of a password prompt (the commands themselves are unchanged):

- macOS Sonoma+ (survives OS updates):
  ```bash
  sed "s/^#auth/auth/" /etc/pam.d/sudo_local.template | sudo tee /etc/pam.d/sudo_local
  ```
- Older macOS: add `auth sufficient pam_tid.so` as the first line of `/etc/pam.d/sudo` (reset by OS updates).

Notes:

- Apple Watch works with the same prompt (double-click crown) when "Approve requests with your Apple Watch" is on (System Settings → Touch ID & Password) — even with the Mac locked.
- Only works in a local GUI terminal session (tmux/SSH fall back to password); `sudo`'s timestamp still applies (~5 min).
- Until enabled, `sudo` asks for the password.

## Safety — always ask first

**Before executing ANY command with `pkexec` (or `sudo` on macOS), you MUST ask the user for explicit approval.**

- State clearly what the command does and what it will change on the system.
- Wait for the user's explicit "go ahead" or equivalent confirmation before running it.
- Never assume permission — even for seemingly harmless commands (reading files, checking status, etc.).
- If the user declines, respect the decision and do not retry.

Example interaction:

> "I need to restart nginx with `pkexec systemctl restart nginx`. This will briefly interrupt active connections. Shall I proceed?"

## Basic usage

```bash
pkexec command args...
```

## Common patterns

### Package management (NixOS)

```bash
pkexec nixos-rebuild switch
pkexec nixos-rebuild switch --flake .#myhost
pkexec nix-collect-garbage -d
```

### Systemd services

```bash
pkexec systemctl restart nginx
pkexec systemctl enable --now postgresql
pkexec systemctl status sshd
```

### File operations

```bash
pkexec cat /etc/shadow
pkexec chmod 755 /usr/local/bin/script
pkexec cp config /etc/myapp/
```

### Network / firewall

```bash
pkexec nft list ruleset
pkexec ip addr show
```

### Disk / mount

```bash
pkexec mount /dev/sdb1 /mnt/data
pkexec df -h
```

## Running a shell

```bash
pkexec bash
pkexec /bin/sh -c "command1 && command2"
```

## Environment under pkexec

- `pkexec` resets most of the environment: `PATH`, `HOME`, and user-defined variables (`NIX_PATH`, `XDG_STATE_HOME`, …) do not pass through. If the elevated command needs them, pass them via `env` **inside** the pkexec invocation:
  ```bash
  pkexec env PATH="/run/current-system/sw/bin:/run/current-system/bin:/run/wrappers/bin:/usr/sbin:/usr/bin:/sbin:/bin" \
    NIX_PATH="..." nixos-rebuild build
  ```
- **Never export or modify `PATH` in the outer shell before invoking `pkexec`.** On NixOS only the wrapper at `/run/wrappers/bin/pkexec` is setuid; other resolved locations (e.g. `/run/current-system/sw/bin/pkexec`) are not setuid and fail with "pkexec must be setuid root". Invoke `pkexec` with the default PATH and pass `PATH` via `env PATH=...` inside.

## Tips

- `pkexec` may prompt for authentication via polkit — expect a password prompt.
- Use `pkexec /bin/sh -c "..."` to chain multiple privileged commands.
- Prefer single-command invocations over spawning a root shell when possible.
- When a command fails with permission errors, rerun with `pkexec` — never assume the error is unrelated to permissions.

