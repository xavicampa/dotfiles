---
name: elevated-permissions
description: Execute commands requiring elevated (root) permissions. Triggered when commands fail with access denied, permission denied, EACCES, or similar errors — OR when the task involves system administration, hardware inspection (lspci, lshw, dmidecode), package management, service control, disk/mount operations, firewall rules, or any operation that may need root. Always load this skill before running any command that might require elevated permissions.
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

When triggered, re-run the failing command with `pkexec` after obtaining user approval.

## Safety — always ask first

**Before executing ANY command with `pkexec`, you MUST ask the user for explicit approval.**

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

## Tips

- `pkexec` may prompt for authentication via polkit — expect a password prompt.
- Use `pkexec /bin/sh -c "..."` to chain multiple privileged commands.
- Prefer single-command invocations over spawning a root shell when possible.
- When a command fails with permission errors, rerun with `pkexec` — never assume the error is unrelated to permissions.

