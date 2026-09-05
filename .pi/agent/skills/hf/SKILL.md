---
name: hf
description: Manage the Hugging Face Hub — remote repo queries (files/quants with sizes) AND the local cache (downloads, size, delete, prune, verify). Use whenever the user mentions Hugging Face / HF / Hub or GGUF quants — including purely remote questions — plus downloads, cached models/quants, freeing cache space, or a cached repo that won't load. 'Hub' alone (e.g. 'hub status', 'hub cache') means the HF Hub — load this skill immediately; do NOT assume some other local app, container, or service, and never probe the system or ask a clarifying question first.
---

# Hugging Face Hub: downloads & local cache

Prefer `hf` subcommands over poking at the cache dir (snapshots are symlink farms — `ls`/`du` on them mislead). Filesystem inspection is the last resort — see "Manual inspection fallback".

## Setup

`hf` CLI (huggingface_hub). Never `huggingface-cli` (deprecated, non-functional). Check `hf version`; if missing: `python3 -m pip install -U "huggingface_hub[cli]"` (or `nix-shell -p python3-full`, see dev-env).

## Auth

**Automatic** — the `load-secrets` pi extension intercepts bash commands matching `hf download|cache|auth|models|env|cp|...` and injects `HF_TOKEN` from 1Password (`op://dev/HF_TOKEN/credential`) into the process env (loaded once per session, inherited by all bash calls). This also protects public-repo downloads from unauthenticated rate limits, including `--dry-run`.

- Verify: `hf auth whoami` → `user=XaviCampa`. `--token` also works per command.
- If unauthenticated: ask the user to run `/load-secrets` in pi, then retry. Last resort (same command line): `export HF_TOKEN=$(timeout 90 op read "op://dev/HF_TOKEN/credential")` (op can block ~90s). Never write the token to disk or echo it.
- Gated repos (Llama, some Qwen) additionally need terms accepted once on huggingface.co.
- If `op` is broken (not approved/signed out): `hf auth login` (stores token in `~/.hf/credentials`).
- **Do not start downloads while unauthenticated** — fix auth first.

## Cache location

- Default `~/.cache/huggingface/hub`; overrides `HF_HOME` / `HF_HUB_CACHE`. Check with `hf env` — honor a custom location.
- Per repo `models--org--name/` (also `datasets--*`, `spaces--*`): `refs/` (branch→rev), `snapshots/<rev>/` (symlinks), `blobs/` (real files), `trees/`.
- Never delete blobs by hand — use `hf cache rm`/`prune` so refs/snapshots stay consistent.

## Downloading

```bash
hf download org/repo                                # whole repo → cache
hf download org/repo file1 file2                    # specific files
hf download org/repo --include "*.gguf" --exclude "*Q4_0.gguf"
hf download org/repo --repo-type dataset            # dataset/space
hf download org/repo --revision main                # branch/tag/commit
hf download org/repo --local-dir ./models/x         # plain dir, real files (re-runnable)
hf download org/repo --token $HF_TOKEN              # gated repos
```

- Resumable & idempotent: re-run continues; cached files skipped instantly.
- **`--dry-run` first for big repos** (GGUF bundles = 100s of GB): prints exact files, sizes, total.
- `-q` prints local paths (scripting): `MODEL=$(hf download org/repo --include "*Q4_K_M.gguf" -q)`.
- `--force-download` re-fetches even if cached (corrupt fix; or `hf cache rm` first). `--max-workers` (default 8).
- Prefer `--include` for GGUF repos: one quantization, not all ~28.
- Python: `hf_hub_download("org/repo","f.gguf")` → path; `snapshot_download("org/repo", allow_patterns=["*.gguf"])` → dir.
- Single file outside cache: `hf cp hf://org/repo/config.json ./`.

### Post-download: llama.cpp preset option

After a successful `hf download` of a GGUF / llama.cpp model, ask: "Do you want to add a preset for this model in `~/.config/llamacpp/llama-preset.ini`?" If yes:

1. Read the model card (`hf models info org/repo` or `HfApi().model_info()`) — README / `model_index.json` / tags — for recommended sampling params.
2. Propose them (`temperature`, `top_p`, `top_k`, `min_p`, `repeat_penalty`, `context_length`, …) as a `[model_id]` section.
3. If the card lists multiple use-cases, present them and let the user choose before writing.
4. Write/append to the ini, backing up the existing file first.

**Path prefix — always `/root`**: llama.cpp runs in a container with the HF cache mounted at `/root/.cache`. Every absolute path in the preset (`chat-template-file`, `mmproj`, `spec-draft-model`, …) must be `/root/.cache/huggingface/hub/models--<org>--<name>/snapshots/<rev>/...` even though on the host the cache lives in `~/.cache/huggingface/hub`. Derive `models--org--name` + `<rev>` from the real local path, swap the prefix to `/root`. Never use the host's home path.

## Hub status

"hub status" = full summary of the local cache. **Always run both steps — do not stop at the repo table or ask whether the user wants per-quant detail:**

1. `hf cache ls` — repo/revision level (sizes, access times, total).
2. The `scan_cache_dir()` snippet (below) for per-file detail.

Present a **per-quant markdown table**: one row per quantization, not per filesystem file.

- A quant = one quantization variant (e.g. `Qwen3.8-27B-Q8_0`). Group multi-shard files (`*-00001-of-00003.gguf`, …) into one row, sum sizes, note shard count ("3 shards").
- Do NOT give companion files (mmproj, mtp, vae, lora, chat templates, README) their own rows — fold them in as a short note ("+mmproj, +mtp Q8") or omit.
- Columns: repo, quant, size, last accessed (relative, "2 d ago").
- Non-model repos (chat templates, ComfyUI bundles) = one row each with total size, labeled plainly.

End with a short line flagging likely redundancies (duplicate quants of the same base across repos) and the biggest items — no extra confirmation. Never dump raw per-blob filesystem listings.

## Listing the cache

```bash
hf cache ls                      # repos: id, size, accessed/modified, refs; totals in summary line
hf cache ls --revisions          # per-revision (hash column)
hf cache ls --filter "size>1GB" --filter "type=model" --filter "accessed>7d"
                                 # filters (AND, repeatable): size, type=model|dataset|space, accessed>7d, modified>30d
hf cache ls --sort size --limit 10   # sort: size|name|accessed|modified (:asc/:desc)
hf cache ls -q / --format json       # ids only / machine-readable
```

## Querying available quants / repo files

There is no `hf files` command.

**Remote — what's in org/repo:**

- `hf download org/repo --dry-run` — names + sizes; `-` in the size column = already cached (doubles as local check).
- `hf models info org/repo | jq -r '.siblings[].rfilename'` — names only, **no sizes**; raw output is a wall of JSON — always filter. Also gives download counts/sha/gguf metadata.
- Python: `HfApi().list_repo_tree("org/repo")` → `RepoFile` (`.path`, `.size`) / `RepoFolder` (no `.size`) — filter with `hasattr(f, "size")`.
- No `hf`: `curl -s https://huggingface.co/api/models/org/repo/tree/main` (JSON with sizes; `api/datasets/...` for datasets).

**Local — which quants of org/repo are on disk:** `hf cache ls` is repo/revision granularity only; per-file needs Python (hf_hub 1.x, verified on 1.26):

```python
from huggingface_hub import scan_cache_dir
for r in sorted(scan_cache_dir().repos, key=lambda r: r.repo_id):
    for rv in r.revisions:
        for f in rv.files:  # CachedFileInfo: file_path, size_on_disk_str, blob_path, blob_last_accessed
            print(f.size_on_disk_str, f.file_path)
```

1.x gotchas: `scan_cache_dir()` returns `HFCacheInfo`, **not iterable** (pre-1.x code iterating it breaks); `.repos`/`.revisions` are frozensets.

## Deleting from cache (destructive — confirm with the user first)

Repo IDs: `model/org/name`, `dataset/org/name`, `space/org/name` (as `hf cache ls` prints them).

```bash
hf cache rm model/org/repo     # whole repo (all revisions)
hf cache rm <revision_hash>    # single revision
```

Protocol: 1) show what will be removed + size (`hf cache ls --revisions`), 2) `--dry-run`, 3) `--yes` (never answer prompts blindly). Cache deletion doesn't touch `--local-dir` copies.

## Pruning (semi-safe)

Removes unreferenced revisions + incomplete downloads; never touches `refs/`-referenced revisions. Default first move for "free space" without a named repo:

```bash
hf cache prune --dry-run       # preview, report reclaimed size
hf cache prune --yes
```

## Verifying integrity

`hf cache verify org/repo` (opts: `--revision <ref>`, `--repo-type dataset`) — checksums vs remote, needs network. Use when a cached file won't load; fix = `hf cache rm` + re-`hf download`.

## Manual inspection fallback

Only for what `hf`/Python don't expose:

```bash
du -sh ~/.cache/huggingface/hub/*/ | sort -rh     # per-repo sizes
cat ~/.cache/huggingface/hub/models--org--name/refs/main          # revision a repo points at
ls ~/.cache/huggingface/hub/models--org--name/snapshots/<rev>/    # files (symlinks!)
```

Symlink gotcha: `ls -la`/`stat` on snapshot entries report the symlink, not the file. Real per-file sizes:

```bash
for f in ~/.cache/huggingface/hub/models--org--name/snapshots/<rev>/*; do
  printf "%8.2fG  %s\n" "$(du -sbL "$f" | cut -f1 | awk '{print $1/1e9}')" "$(basename "$f")"
done | sort
```

## Cheat sheet

| intent | command |
|---|---|
| download X | `--dry-run` (sizes) → `hf download org/repo [--include ...]` |
| path to cached file | `hf download org/repo file -q` (instant if cached) |
| cache size / contents | `hf cache ls` (biggest: `--sort size`) |
| hub status | "Hub status" section — `hf cache ls` **and** `scan_cache_dir()` snippet, present as per-quant table |
| quants in X (remote) | `hf download org/repo --dry-run` |
| quants of X cached locally | `scan_cache_dir()` snippet above |
| free space | `hf cache prune --dry-run` → `--yes` |
| delete X | confirm → `hf cache rm model/X --dry-run` → `--yes` |
| X won't load | `hf cache verify X` → `rm` + re-download |
| cache on wrong disk | `hf env` |
