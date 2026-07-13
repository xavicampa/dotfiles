# Hermes Agent

## Layout

| Path | Purpose |
|------|---------|
| `~/.config/hermes/config.yaml` | Config (copied into container on start) |
| `~/.local/hermes/` | State: sessions, memories, skills, logs, `.env` |

## Usage

```bash
podman exec -it hermes hermes                      # TUI
systemctl --user restart hermes                    # restart (re-copies config)
```

## Model

Points at the local llamacpp server via `host.containers.internal:8080`.
When switching models, edit `~/.config/hermes/config.yaml` and restart.

## Docs

https://hermes-agent.nousresearch.com/docs/user-guide/docker
