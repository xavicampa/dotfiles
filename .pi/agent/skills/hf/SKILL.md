---
name: hf
description: Manage the Hugging Face Hub — remote repo queries AND the local cache. List what files/quants a remote repo has with sizes (e.g. 'what Q4/GGUF quants of X are on HF', 'list files in an HF repo'), check repo sizes, download models/datasets (file filters, local dirs, gated-repo tokens), list cached repos/quants with disk usage, delete or prune cache, verify integrity. Use whenever the user mentions Hugging Face / HF / Hub or GGUF quants — including purely remote questions (no download or cache involved) — plus downloads, HF cache size, which models/quants are cached, freeing disk space, or a cached repo that won't load.
---

# Hugging Face Hub: downloads & local cache

Prefer `hf` subcommands over poking at the cache dir (snapshots are symlink farms — `ls`/`du` on them mislead). Filesystem inspection is the last resort — see "Manual inspection fallback".

## Setup

`hf` CLI (huggingface_hub). Never `huggingface-cli` (deprecated, non-functional). Check: `hf version`; if missing: `python3 -m pip install -U "huggingface_hub[cli]"` (or `nix-shell -p python3-full`, see dev-env).

## Auth

Token lives in 1Password (dev vault); read on demand, never write to disk:

```bash
export HF_TOKEN=$(timeout 90 op read "op://dev/HF_TOKEN/credential")  # op can block ~90s waiting for approval
```

- `hf auth whoami` → `user=XaviCampa` verifies. Exported env var is used by all `hf` commands; `--token` also works per command.
- Gated repos (Llama, some Qwen) additionally need terms accepted once on huggingface.co with that account.
- If `op` is broken (not approved/signed out): `hf auth login` (stores token in `~/.hf/credentials`).

## Cache location

- Default `~/.cache/huggingface/hub`; overrides `HF_HOME` (root) or `HF_HUB_CACHE` (hub dir). Check with `hf env` — honor a custom location.
- Layout, per repo `models--org--name/` (also `datasets--*`, `spaces--*`): `refs/` (branch→rev hash), `snapshots/<rev>/` (symlinks), `blobs/` (real files, content-addressed), `trees/`.
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
- **Always `--dry-run` first for big repos** (GGUF bundles = 100s of GB): prints exact files, sizes, total.
- `-q` prints local paths (for scripting): `MODEL=$(hf download org/repo --include "*Q4_K_M.gguf" -q)`.
- `--force-download` re-fetches even if cached (corrupt fix; or `hf cache rm` first). `--max-workers` (default 8).
- Prefer `--include` for GGUF repos: one quantization, not all ~28.
- Python: `hf_hub_download("org/repo","f.gguf")` → path; `snapshot_download("org/repo", allow_patterns=["*.gguf"])` → dir.
- Single file outside cache: `hf cp hf://org/repo/config.json ./`.

## Listing the cache

```bash
hf cache ls                      # repos: id, size, accessed/modified, refs; summary line has totals
hf cache ls --revisions          # per-revision (hash column)
hf cache ls --filter "size>1GB" --filter "type=model" --filter "accessed>7d"
                                 # filters (AND, repeatable): size, type=model|dataset|space, accessed>7d, modified>30d
hf cache ls --sort size --limit 10   # sort: size|name|accessed|modified (:asc/:desc)
hf cache ls -q / --format json       # ids only / machine-readable
```

## Querying available quants / repo files

There is no `hf files` / `hf repos files` command.

**Remote — what's in org/repo:**

- `hf download org/repo --dry-run` — names + sizes; `-` in the size column = already cached locally (so it doubles as the local check).
- `hf models info org/repo | jq -r '.siblings[].rfilename'` — names only, **no sizes**; raw output is a wall of JSON (full chat template) — always filter. Also gives download counts/sha/gguf metadata.
- Python: `HfApi().list_repo_tree("org/repo")` → `RepoFile` (`.path`, `.size`) and `RepoFolder` (no `.size`) — filter with `hasattr(f, "size")`.
- No `hf` at all: `curl -s https://huggingface.co/api/models/org/repo/tree/main` (JSON with sizes; `api/datasets/...` for datasets).

**Local — which quants of org/repo are on disk:** `hf cache ls` is repo/revision granularity only; per-file needs Python (hf_hub 1.x, verified on 1.26):

```python
from huggingface_hub import scan_cache_dir
for r in sorted(scan_cache_dir().repos, key=lambda r: r.repo_id):
    for rv in r.revisions:
        for f in rv.files:  # CachedFileInfo: file_path (PosixPath), size_on_disk_str, blob_path
            print(f.size_on_disk_str, f.file_path)
```

1.x shape gotchas: `scan_cache_dir()` returns `HFCacheInfo`, **not iterable** (pre-1.x code iterating it breaks); `.repos`/`.revisions` are frozensets.

## Deleting from cache (destructive — confirm with the user first)

Repo IDs: `model/org/name`, `dataset/org/name`, `space/org/name` (as `hf cache ls` prints them).

```bash
hf cache rm model/org/repo     # whole repo (all revisions)
hf cache rm <revision_hash>    # single revision
```

Protocol: 1) show user what will be removed + size (`hf cache ls --revisions`), 2) `--dry-run`, 3) `--yes` (never answer prompts blindly). Deleting from cache doesn't touch `--local-dir` copies.

## Pruning (semi-safe)

Removes unreferenced revisions + incomplete/interrupted downloads; never touches `refs/`-referenced revisions. Default first move for "free space" without naming a repo — preview and report the reclaimed size:

```bash
hf cache prune --dry-run
hf cache prune --yes
```

## Verifying integrity

`hf cache verify org/repo` (opts: `--revision <ref>`, `--repo-type dataset`) — checksums vs remote, needs network. Use when a cached file won't load (llama.cpp/whisper errors); fix = `hf cache rm` + re-`hf download`.

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
| quants available in X (remote) | `hf download org/repo --dry-run` |
| quants of X cached locally | Python `scan_cache_dir()` snippet above |
| free space | `hf cache prune --dry-run` → `--yes` |
| delete X | confirm → `hf cache rm model/X --dry-run` → `--yes` |
| X won't load | `hf cache verify X` → `rm` + re-download |
| cache on wrong disk | `hf env` |
