---
name: elevated-permissions
description: Execute commands requiring elevated (root) permissions. Triggered when commands fail with access denied, permission denied, EACCES, or similar errors — OR when sudo is required or mentioned — OR when the task involves system administration, hardware inspection (lspci, lshw, dmidecode), package management, service control, disk/mount operations, firewall rules, or any operation that may need root. Always load this skill before running any command that might require elevated permissions. On macOS there is no pkexec — use `sudo` there.
---

# Elevated permissions (pkexec)

Default to `pkexec`, not `sudo`, on Linux/NixOS. **`pkexec` works from the tool shell** — the dialog appears on the user's desktop, not in the terminal. Assume it works; claim otherwise only with a `pkexec` error you actually observed.

## Scope

This skill decides **how** to elevate. It does not decide **what** to run or **when**:

- Installing a missing tool/runtime → **dev-env** (never install into the machine).
- Changing NixOS/home-manager config → **nix-config**.
- Upgrading channels/system/home-manager → **nix-upgrade** (build → diff → confirm → `switch --store-path`). Do not improvise a `nixos-rebuild switch` from this file.
- EACCES because the binary itself is missing → **dev-env**, not root.

## Safety — always ask first

**Before executing ANY command with `pkexec` (or `sudo` on macOS), you MUST ask the user for explicit approval.**

- State what the command does and what it changes on the system.
- Wait for an explicit "go ahead" or equivalent. Never assume permission, even for read-only commands.
- Batch the approval: present the whole command list once, get one confirmation, then run it (see "One invocation" below).
- If the user declines, or the polkit dialog is dismissed/times out: **stop and report**. Do not retry, do not try a different elevation path.

> "I need to restart nginx — `pkexec env PATH="…" systemctl restart nginx` (one polkit dialog will appear on your desktop). This will briefly interrupt active connections. Shall I proceed?"

## Execution context — the tool has no TTY

The agent's shell is **not a terminal** (no stdin/stdout TTY). This changes everything:

- Elevation goes through **polkit**: `pkexec` asks the desktop's registered polkit agent to show a password dialog **on the user's desktop**, and the tool call **blocks** until the user answers it. Tell the user to expect a dialog, and bound the wait, e.g. `timeout 180 pkexec …` (or pass a `timeout` to the bash tool).
- `pkexec`'s own fallback agent prompts on `/dev/tty`, which does not exist here — if no agent is reachable the call fails with `Not authorized` / `Failed to get authentication`. That error is a **result**, obtained by running `pkexec`, never by inspecting processes first.
- `sudo` is **not** a fallback for a fresh prompt: with no TTY it cannot read a password. It is only usable when a timestamp is already cached from the user's own terminal — test with `sudo -n <cmd>` and fall back to asking the user if it fails.
- On macOS `sudo` can never prompt from the tool at all → print the exact command and ask the user to run it in their own terminal.

## No preflight — attempt, then diagnose

**In a desktop session, run the command with `pkexec`. Do not try to prove in advance that elevation is possible.** There is no reliable way to detect a polkit agent, and a wrong "no" costs the whole task:

- `pgrep -i polkit` shows **only `polkitd`** on homepc — the authentication agent is built into the desktop shell (DMS / Dux Shell: processes `.dms-wrapped`, `quickshell`; GNOME/KDE/other stacks embed theirs in the shell, portal or compositor too). "No agent process found" is a **false negative, not a blocker**. Never conclude anything from this probe.
- `sudo -n` failing ("a password is required"), or the user's history of typing `sudo …` in their own terminal, says **nothing** about polkit. Different mechanism — not evidence.
- Never write "I cannot elevate from here" / "pkexec has no prompt to show you" unless you can quote the **actual error from a `pkexec` call you ran**. Otherwise: make the call, mention the dialog, and let the user answer it.

The legitimate blockers are only: the user declined, the dialog was dismissed/timed out, or `pkexec` returned an auth error. In that last case the usual cause is that this shell is not inside an active local seat session — check *after* the failure:

```bash
cat /proc/self/cgroup                                  # needs /…/session.slice/… ; SSH/system service/container won't have it
loginctl show-session <id> -p Active -p Type -p Remote # from the session number above
```

Confirmed headless/remote → hand the exact command to the user to run in their own terminal. Do not retry via another elevation path.

## One invocation per task

polkit does not reliably cache `org.freedesktop.policykit.exec` — expect a **fresh dialog per invocation**. Batch a task's privileged commands into a single call so the user approves once and the steps stay atomic:

```bash
pkexec env PATH="/run/current-system/sw/bin:/run/current-system/bin:/run/wrappers/bin:/usr/sbin:/usr/bin:/sbin:/bin" \
  /bin/sh -c "systemctl enable --now fstrim.timer && systemctl start fstrim.service && systemctl status fstrim.service --no-pager"
```

The `env PATH=…` prefix is mandatory on NixOS, not optional — see the next section. Never `pkexec bash` / `pkexec -i …`: an interactive root shell cannot work without a TTY.

## NixOS — PATH and environment under pkexec

- **`pkexec` resolves the command against a restricted secure PATH** (`/usr/bin:/bin:/usr/sbin:/sbin` + polkit's own bin). On NixOS `/bin` contains only `sh` and `/usr/bin` only `env` — `systemctl`, `mount`, `ip`, `nixos-rebuild` live in `/run/current-system/sw/bin` and `/run/wrappers/bin`, which are **not** in that PATH. So plain `pkexec systemctl …` fails to find the command; use the `pkexec env PATH=… <cmd>` form for essentially every system command, not just for nix.
- `pkexec` also resets the environment: `PATH`, `HOME`, and user variables (`NIX_PATH`, `XDG_STATE_HOME`, …) do not pass through. If the elevated command needs them, pass them via `env` **inside** the invocation:
  ```bash
  pkexec env PATH="/run/current-system/sw/bin:/run/current-system/bin:/run/wrappers/bin:/usr/sbin:/usr/bin:/sbin:/bin" \
    NIX_PATH="$NIX_PATH" nixos-rebuild build
  ```
  (`env` resolves because NixOS symlinks `/usr/bin/env` into the system profile.)
- Pass the current shell's `NIX_PATH` **verbatim** — don't reconstruct or omit it. `nixos-rebuild` re-evaluates the config, so it needs the `nixos-config` and `nixpkgs` entries; a missing/empty `NIX_PATH` fails with `error: file 'nixpkgs/nixos' was not found in the Nix search path`.
- `HOME` becomes `/root`. Leave it unless the command writes to `$HOME` (nix build/cache dirs) — then add `HOME="$HOME"` to the same `env` block.
- **Never export or modify `PATH` in the outer shell before invoking `pkexec`.** On NixOS only the wrapper at `/run/wrappers/bin/pkexec` is setuid; other resolved locations (e.g. `/run/current-system/sw/bin/pkexec`) are not setuid and fail with "pkexec must be setuid root". Invoke `pkexec` with the default PATH and pass `PATH` via `env PATH=...` inside.

## Common patterns

On NixOS every one of these needs the `env PATH=…` prefix — write it out **verbatim** each time (the literal list from the section above; don't rely on a shell variable surviving into the pkexec call):

```bash
# Systemd services
pkexec env PATH="/run/current-system/sw/bin:/run/current-system/bin:/run/wrappers/bin:/usr/sbin:/usr/bin:/sbin:/bin" \
  systemctl restart nginx

# Network / firewall
pkexec env PATH="/run/current-system/sw/bin:/run/current-system/bin:/run/wrappers/bin:/usr/sbin:/usr/bin:/sbin:/bin" \
  nft list ruleset

# Disk / mount
pkexec env PATH="/run/current-system/sw/bin:/run/current-system/bin:/run/wrappers/bin:/usr/sbin:/usr/bin:/sbin:/bin" \
  mount /dev/sdb1 /mnt/data
```

Tools that aren't in the system profile at all (e.g. `lspci` from a nix-shell) must be given by absolute path. Read-only inspection often needs no elevation at all (`systemctl status`, `ip addr show`, `df -h`, `journalctl` for the current user, plain `lspci`) — check that first. System package/config changes go through **nix-config** / **nix-upgrade**, not ad-hoc `nixos-rebuild` calls from here.

## Diagnose before escalating

A permission error is a hypothesis, not a verdict. Before re-running as root, confirm the cause:

```bash
ls -ld <path>            # owner/mode
test -e <path> || echo missing
findmnt -no OPTIONS <path> | grep -o ro   # read-only mount
command -v <cmd> || echo "not on PATH → dev-env"
```

Then elevate only for the real privilege gap. Re-running a broken command as root turns a harmless failure into a system change.

## Failure modes

| Symptom | Meaning / action |
|---|---|
| `pkexec must be setuid root` | `pkexec` was resolved off the default PATH (PATH was tampered with) — re-run with the default PATH, see above. |
| `Not authorized` / `Failed to get authentication` | This session really has no reachable agent (headless/remote/system-service — see the session check above). Hand the command to the user. |
| `… No such file or directory` while executing | The command isn't on pkexec's secure PATH — add the `env PATH=…` prefix or use an absolute path. |
| Command hangs | Dialog is waiting on the desktop — tell the user, and use a timeout. |
| Dialog dismissed / timed out | Treat as a decline: stop, report, don't retry. |

## macOS — `sudo` instead of `pkexec`

`pkexec` does not exist on macOS. Use `sudo`, with the same ask-first rule; because the tool has no TTY, give the user the exact command to run locally (or use `sudo -n` if they've authenticated within the ~5 min timestamp window).

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
