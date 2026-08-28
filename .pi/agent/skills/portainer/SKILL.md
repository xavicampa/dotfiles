---
name: portainer
description: Manage the Portainer instance on the Raspberry Pi home server via its REST API — install/deploy applications (App Store templates, containers, stacks), and manage containers, images, and volumes. Use when the user asks to install an app on the rpi/home server, list or manage rpi containers, or interact with Portainer.
---

# Portainer (rpi home server)

Manage the Portainer instance on the Raspberry Pi home server via its REST API —
installing/deploying apps and managing containers, images, volumes, and templates.

## Credentials

- **No secrets are stored on disk.** The API key is in 1Password
  (`op://Private/portainer-rpi-ai-user/notesPlain`) and loaded into the
  `PORTAINER_API_KEY` environment variable **on-demand** by the
  `load-secrets` extension when this skill is loaded (it also triggers on any
  bash command referencing `skills/portainer/scripts/portainer` or `rpi:9443`).
- If `PORTAINER_API_KEY` is unset, run the `/load-secrets` command (the
  1Password desktop app must be running) and retry.
- Base URL: `https://rpi:9443` (self-signed cert → always `curl -k`). Not a secret;
  override with `PORTAINER_BASE_URL` if needed.

## Helper script

`./scripts/portainer` (resolve relative to this skill directory).
Subcommands: `status`, `containers`, `create FILE.json`, `start/stop/rm <id>`,
`logs <id>`, `images`, `volumes`, `templates [filter]`,
`deploy <templateId> NAME [ENV=VAL ...]`, `raw <METHOD> <PATH> [body]`.

## Critical API quirks (Portainer 2.39.1)

1. **Auth header**: API keys (`ptr_...`) go in the **`X-API-KEY`** header, NOT
   `Authorization: Bearer` (that's only for JWTs). Bearer + API key →
   `{"message":"Invalid JWT token"}`.
2. **Local environment is endpoint id 2, not 1** (Portainer's own container takes id 1).
   Re-resolve dynamically: `GET /api/endpoints` → `select(.Name=="local") | .Id`.
3. **Backend is Podman 5.4.2**, not Docker — but the Docker-compatible passthrough works.
4. **Resource routes** (raw engine API passthrough):
   `GET/POST /api/endpoints/{id}/docker/...` — e.g.
   - `GET /api/endpoints/2/docker/containers/json?all=true` (list)
   - `POST /api/endpoints/2/docker/containers/create` (body = Docker createContainer schema)
   - `POST /api/endpoints/2/docker/containers/{id}/start` / `/stop`, `DELETE .../containers/{id}?force=true`
   - `GET /api/endpoints/2/docker/containers/{id}/logs?stdout=true&stderr=true&tail=100`
   - `POST /api/endpoints/2/docker/images/create?fromImage=<img>&tag=<tag>` (pull)
   - `GET /api/endpoints/2/docker/images/json`, `GET /api/endpoints/2/docker/volumes`
   - Engine version: `GET /api/endpoints/2/docker/version`
5. `GET /api/endpoints/{id}/containers` (without `/docker`) is 404 in 2.39 — do not use.
6. **Admin-run containers are invisible to this token** — `GET .../docker/containers/json?all=true` can return `[]` even though the endpoint snapshot (`Snapshots[].ContainerCount` / `RunningContainerCount`) shows running containers. That is expected, not an error; the host also runs containers under an admin-managed namespace this token can't list. Endpoint-scoped stack routes (`/api/endpoints/2/stacks`, `/composestacks`, `/swarmstacks`) 404 for this token even though `StackCount` may be > 0 in the snapshot — but the **global** stack routes work (see below). To see/manage admin containers you'd need `ssh rpi` — but see the SSH rule below.
7. **SSH to the rpi is a last resort** — prefer the Portainer API for anything (volumes, images, mounts, endpoints). If the API can't answer, **ask the user for confirmation before ssh-ing** (and that they approve the 1Password prompt); do not ssh uninvited.
8. **Port bindings go in `NetworkingConfig.Ports`** — a bare `HostConfig.PortBindings` on `containers/create` is silently dropped (container runs with `"Ports":{"x/tcp":null}` and the host port is never reachable). Pass `NetworkingConfig: {"Ports": {"5055/tcp":[{"HostIp":"","HostPort":"5055"}]}}` (setting HostConfig.PortBindings as well is harmless). Verify after start: `GET .../containers/{id}/json` → `.NetworkSettings.Ports` must list the HostPort.
9. **Images must be pulled first** — container create fails with "no such image" if the
   image is not in the local store (no implicit pull through this route).
10. **`exec` sub-routes are not proxied** — `POST /containers/{id}/exec` works (201), but everything under it (`.../exec/{eid}/start`, `.../exec/{eid}/json`) returns a plain `Not Found` 404. To run a command inside a container's filesystem, create a **one-shot busybox container** mounting the same volume(s) (busybox is already local), start it, read `/logs`, then `DELETE ...?force=true`.
11. **App Store templates**: `GET /api/templates` → `.templates[]` with `.id`, `.title`, `.image`.
   Deploy: `POST /api/templates/{id}/deploy` with
   `{"name":"<app>","hostId":<localId>,"env":[{"name":..,"value":..}],"volumes":[{"Container":..,"Host":..}]}`.
   Template deploy is all-or-nothing on its config; for fine control (compose, custom
   networks/volumes), prefer `containers/create` or stacks.

## Stacks (compose) via the global API

Endpoint-scoped stack routes 404 for this token, but the **global** routes work (Portainer 2.39.1, verified):

- List: `GET /api/stacks`
- Create (standalone compose from string):
  `POST /api/stacks/create/standalone/string?endpointId=2` with
  `{"Name":"myapp","StackFileContent":"services:\n  web:\n    image: nginx"}`
  → returns the created stack (`Id`, `Name`, `Status`).
- Delete: `DELETE /api/stacks/{id}?endpointId=2`
- Update/redeploy (file-based stacks): `PUT /api/stacks/{id}?endpointId=2` with `{"StackFileContent":"<new compose yaml>"}` — verified this also performs a `compose up` redeploy (new services appear without a separate step)
- Start / stop: `POST /api/stacks/{id}/start?endpointId=2`, `POST /api/stacks/{id}/stop?endpointId=2`
- File / migrate: `GET /api/stacks/{id}/file?endpointId=2`, `POST /api/stacks/{id}/migrate`

Quirks learned the hard way:
- **Compose project name = stack `Name`** — it must be lowercase alphanumerics / hyphens / underscores and start with a letter or number. `__probe__` (leading underscore) → 500 "invalid project name".
- **Port conflict = hard fail, but nothing is persisted** — if `compose up` fails (e.g. `bind: address already in use`), the API returns 500 and **no stack row is created** (`GET /api/stacks` stays clean). Free the ports (stop/remove the squatter containers), then re-POST — no cleanup of a half-created stack needed.
- Storing a reference copy of the compose locally (e.g. `~/<name>stack.yml`) is handy for re-deploys.
- `StackFileContent` is the compose YAML **as a JSON string** (`\n`-escaped); easiest to build the body with a heredoc + `jq -n`/a pre-escaped file.
- **Compose prefixes top-level named volumes with the project name** (project name = stack `Name`): a stack `jelly` with volume `jellyfin-media` uses podman volume **`jelly_jellyfin-media`**, not `jellyfin-media`. Consequences: volumes created before the stack (e.g. for standalone containers) are NOT reused by the stack — pre-populate the prefixed name; and to inspect/prepare a stack volume, use the prefixed name in a one-shot busybox container.

## Verified working example (token test, 2026-08)

```bash
T="$PORTAINER_API_KEY"; B="https://rpi:9443"
curl -sk -H "X-API-KEY: $T" "$B/api/endpoints"                # env list (local = id 2)
curl -sk -X POST -H "X-API-KEY: $T" "$B/api/endpoints/2/docker/images/create?fromImage=busybox&tag=latest"
curl -sk -X POST -H "X-API-KEY: $T" -H "Content-Type: application/json" \
  -d '{"Image":"docker.io/library/busybox:latest","Cmd":["sleep","30"],"Labels":{"managed-by":"pi-agent"}}' \
  "$B/api/endpoints/2/docker/containers/create"               # → {"Id":"..."}
curl -sk -X POST -H "X-API-KEY: $T" "$B/api/endpoints/2/docker/containers/<id>/start"
```

## Conventions

- Label managed containers: `managed-by: pi-agent`
- Keep app data under a shared data dir with one subdir per app (check existing
  mounts/volumes first)
- Prefer stacks (compose) for multi-container apps
- Never print the API key in output; it only lives in `PORTAINER_API_KEY`

## Security notes

- The user is a **Standard** (non-admin) Portainer user; the token is revocable in the
  UI (user icon → Settings → API access tokens) — stored in the 1Password item
  `portainer-rpi-ai-user` (notes field)
- UI should stay LAN-only (or behind Tailscale) — do not port-forward 9443
