---
name: op-ssh
description: SSH to local/LAN machines (rpi, NAS, home servers — anything resolvable by name on the local network) using the SSH keys provisioned by 1Password. Triggered when the user wants to ssh to a local host, when ssh fails with "Permission denied (publickey,password)", or when ssh fails with "sign_and_send_pubkey ... agent refused operation".
---

# SSH to local machines (keys via 1Password)

**1Password is the SSH agent.** This machine's `SSH_AUTH_SOCK` points at
`/home/javi/.1password/agent.sock`, which already presents all 1Password SSH keys
(homepc, homepc-rsa, javi@MacBook-Pro-ed25519, javi@Javis-MBP-2-id_rsa). Do NOT
try to add keys to it — it refuses `ssh-add` (read-only, by design).

**Hard rule: never write a private key to disk** (no `/tmp` files, no key files
in `~/.ssh`). If a key must be pulled from op, pipe it straight into a
throwaway agent (see fallback).

## Standard flow

```bash
ssh -o BatchMode=yes <host> '<command>'
```

The `Match exec` blocks in `~/.ssh/config` select the right `.pub` identity
files; 1Password's agent does the signing. The `Match` blocks are **intentional**
— do not add `Host <name>` entries or modify them to fix auth.

## When it fails

| Symptom | Cause | Fix |
|---|---|---|
| `sign_and_send_pubkey: ... agent refused operation` | 1Password app is locked or an approval prompt is pending | Ask the user to unlock 1Password / approve the prompt, then retry the same ssh |
| `ssh-add -l` shows no keys (empty agent) | 1Password app not running / agent socket gone | Use the one-shot fallback below |
| `Permission denied (publickey,password)` with keys present | wrong remote user | check the known-hosts table; use `ssh -v` and read the `Server accepts key:` line |

## One-shot fallback (1Password agent unavailable)

Runs entirely in one shell: starts a throwaway agent, pipes the key from op
straight into its memory (never to disk), connects, and the agent dies with the
shell. Triggers one 1Password approval prompt — tell the user to approve.

```bash
eval "$(ssh-agent -s)" >/dev/null 2>&1
op item get <item-name-or-id> --fields "private key" --reveal | sed '1d;$d' | ssh-add -
ssh -o BatchMode=yes <host> '<command>'
```

## Known hosts

| Host | Address | User | Working key (1Password item) |
|---|---|---|---|
| `rpi` | 172.16.99.2 (in `/etc/hosts`) | `javi` | `homepc` (fingerprint `SHA256:i257BWt8wtR8w2p6TbnyuI3HbRdqIe3X167AXRfWShc`) |

When a new host starts working, add a row here (host, address, user, key item).

## Pitfalls (learned the hard way)

- `op item get <id> --fields "private key" --reveal` wraps the value in **JSON
  double quotes** — a stray `"` on the first and last lines makes `ssh-add`
  fail with `invalid format`. Strip with `sed '1d;$d'`.
- The field name is `"private key"` (with a space), not `private`.
- The category filter value is `sshkey` (no underscore); the JSON `category`
  field reads `SSH_KEY`.
- "agent refused operation" on `ssh-add` does NOT mean the key is present —
  against the 1Password agent it just means AddIdentity is disallowed. Listing
  (`ssh-add -l`) is always allowed and is the source of truth.
