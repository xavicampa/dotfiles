---
name: strata-tuning
description: >-
  Retune and measure the Strata engine containers on the home PC from a pi session: change one knob,
  restart that engine through llama-swap without switching model, then read the arm. Load when asked to
  tune, bench, A/B, sweep, pick a layer-split / slot count / expert cache / vision placement, free VRAM
  headroom, reload or stop a strata container, diagnose a strata 502/OOM, or while editing anything under
  ~/.config/strata. Hard rules: never switch model mid-tuning (llama-swap swaps out the engine under test),
  never test a knob with a hand-run `podman run` (llama-swap recreates the container with --replace), never
  edit a preset and leave the old engine warm, and never leave a GPU stage under ~512 MiB free.
---

# Tuning Strata from pi

Three Strata trees, each its own container/model pair:

| tree | preset | run config | container (proxy id) | notes |
|---|---|---|---|---|
| `1slot` | `.config/strata/1slot/strata/launch-presets/docker.json` | `.config/strata/1slot/strata-iq3_s.json` | `qwen3.8-flash-next-iq3_s` | solo, `--pipeline-windows 2` active |
| `parallel` | `.config/strata/parallel/…` | `.config/strata/parallel/strata-iq3_s.json` | `qwen3.8-flash-next-iq3_s-parallel` | batched iq3_s |
| `coder` | `.config/strata/coder/…` | `.config/strata/coder/strata-coder-iq1_m.json` | `qwen3.8-flash-next-coder-iq1_m-parallel` | expert-pruned IQ1_M |

Each tree has a `TUNING_NOTES.md` — **read it before touching that tree, write the finding there after measuring.** Findings that live only in chat have been re-litigated.

## 1. Establish which arm is live (first tool call of every session)

Do not assume; the user switches models by using the client.

```bash
podman ps --format '{{.Names}} {{.Status}}' | grep strata
podman inspect -f '{{.State.CreatedAt}} {{.Config.Env}}' <container>
for p in 5801 5802; do printf "%s=%s\n" "$p" "$(curl -s -o /dev/null -w '%{http_code}' http://$p/health)"; done
```

Ports come from `-e PORT` in the llama-swap entry (`~/.config/nixos/homepc/configuration.nix`), front door is **:8080**. Two ids for the same arm: the **proxy id** (`…-parallel`, what llama-swap routes) and the **engine id** (what the engine itself answers). Reload requests must use the proxy id; benches must target the engine port with the engine id.

Then read the boot you are measuring (see `references/engine-log.md` for the patterns): layer split, residency, per-stage free VRAM, warnings. **The live boot line is the ground truth** — merged preset + env + run config often differs from what the files suggest.

## 2. Where a knob lives (precedence, highest first)

1. **Container env in `configuration.nix`** — `-e PARALLEL`, `-e PORT`, `-e STRATA_*`. This beats the preset and is written back into it. Needs `nixos-rebuild switch`; **hold the rebuild while generations are in flight and ask the user** rather than dropping their work.
2. **Preset `extra`** — most knobs (`--layer-split`, `--batch-mtp`, `--kv-resident`, `--vram-reserve*`, `--pcie-frac`, `--expert-cache`, conversation cache). Default place to tune: no rebuild, survives relaunch. Also `gpus`, `parallel`, `context` keys.
3. **Run config `<tree>/strata-<name>.json`** — the pieces with no launch flag: `max_queue`, `queue_timeout`, and the **`vision` block** (`gpu`, `cuda_device`, `max_tokens`, `threads`). Mounted at `/data/install/…`; the launcher mirrors it into `/data/state/strata/launch/docker.json`, so editing the tree file is enough.

Rule: put a knob in `configuration.nix` only when it genuinely has no preset/run-config path, and leave a comment naming the tree's notes section so nobody re-adds a dead knob.

## 3. The reload dance — one tool call, in this order

Preset edits do not apply to a warm engine.

```bash
podman stop -t 120 <container>            # same -t as the service's own cmdStop; the engine flushes its KV cache on SIGTERM, so a stop takes tens of seconds
sleep 2
curl -s -m 190 http://localhost:8080/v1/chat/completions \
  -H 'Content-Type: application/json' \
  -d '{"model":"<proxy-id>","max_tokens":8,"messages":[{"role":"user","content":"ping"}]}' \
  -o /dev/null -w 'reload=%{http_code} t=%{time_total}\n'   # llama-swap recreates + cold-boots the engine
```

Stop → request must be in the **same call**: a stopped container stays unloaded (`ttl = 0`), and a separate later call risks the client or another arm grabbing the swap. Expect `reload=200 t≈19-24s` (cold boot + graph capture). llama-swap's `unloadTimeout = 40` bounds only its own stop hook — an unload timeout logged while the engine is still flushing is not a failure. `502`/`500`/`exited: 1` = read the boot before trying anything else; common causes in `references/engine-log.md`.

Never issue a request for a **different model id** while tuning an arm: llama-swap swaps the engines (unload of the one under test → the next arm silently measures a cold boot or the wrong engine). If another arm is live, stop it first or ask the user.

## 4. Measure

```bash
python3 /home/javi/.config/strata/parallel/bench-util.py \
  --url http://127.0.0.1:5801 --model <engine-id> --container <container> \
  --levels 1 2 3 --rounds 4 --max-tokens 400 --csv /tmp/<arm>.csv
```

- **400-token streams, not 250**: short generations are dominated by warm-up and verify overhead and understate decode.
- Discard the first stream at each level (window-graph capture / cache fill), and treat level 1 as decode and levels 2-3 as fan-out admission.
- Same config can drift **152 → 164 tok/s** between runs. For any A/B, interleave arms (`31 33 31 33`) or the drift decides the winner.
- Engine-side truth, per era (both containers share one log — pick the boot by pack):

```bash
python3 /home/javi/.config/strata/parallel/erastats.py --pack coder-iq1_m   # med/p25/p75, acceptance, long-request med, prefill, cache hits
```

- GPU side, always both: `nvidia-smi --query-gpu=index,name,memory.used,memory.total,utilization.gpu,power.draw --format=csv,noheader`, and for placement/leaks `nvidia-smi --query-compute-apps=gpu_uuid,pid,used_memory --format=csv,noheader` (map uuid → index; the vision tower is its **own** process row).
- One knob per arm. Everything else byte-identical, else the result is unattributable.

## 5. Accept / reject

Speed: single-stream med, long-request med (`gen>=150/400`), fan-out aggregate. Health, from the boot (reject if any is bad even when faster):
- `layer split: 100% of the experts resident` — sub-100% means the page-locked-RAM expert path joined decode (measured cost: ~10% or more).
- `<n> MiB of VRAM free with everything loaded` for **each** stage — below ~512 MiB you get `- LOW: its window graphs are captured on first use and need room`, and later context growth fails.
- Absence of `WARNING: a decode window`, `not enough room`, `out of memory`, `parallel override conflicts with --batch/--slots`.
- Drafting alive: `accept 8x%`, `drafts/step 4-8`, `yield gen/fed ~1.4`.

Record the accepted arm in `TUNING_NOTES.md` with the boot lines quoted, and keep the preset on it.

## 6. Traps that already cost time

- `--gpu LIST` **remaps the engine's device labels** (`CUDA_VISIBLE_DEVICES`/`CUDA_DEVICE_ORDER`). With `gpus: [1, 0]`, log `CUDA0` = nvidia-smi index 1 (the 3090 Ti). Anchor on `nvidia-smi`, never on the label.
- `vision.cuda_device` is the **physical** nvidia-smi index — `strata-vision` does not inherit that remap. Verify with `--query-compute-apps`.
- Head + draft layer + slot drafters are pinned to the **last** stage (layer 47's hidden state). The lever over which card that is, is the `gpus` order — not the split, and not `STRATA_MTP_STAGE0=1` (measured inert under `--batch`).
- `--mtp-q4 proj|all` shrinks the draft but measures `accept 0.0%`, `drafts/step 0.00` — rejected, do not re-try.
- `--batch-groups` needs a split and to divide `--batch`; it turns `--adapt-async` off, raises GPU occupancy and loses decode.
- `--pipeline-windows 2` prints `is off: not with --batch slots` in batch mode; solo (`1slot`) is the arm where stage overlap exists.
- Free VRAM on a stage is **working memory** (slot sessions, long-context KV, window graphs), not spare capacity: pushing the split past the optimum costs 4-9% per step, and past the fill ceiling it falls off (~115 tok/s).
- Bench CPU sampling must use the **host** PID from `podman inspect -f '{{.State.Pid}}'` (namespaced PIDs read 0.00 cores); engine restarts between requests need re-finding.
- Era stats must be split by `--pack` — `erastats.py --pack coder-iq1_m`, or the newest boot may be the other model's.

## 7. Etiquette

- Backup before editing: `cp file file.bak-<date>-<why>`; leave the `.bak` files untracked.
- Touch only the tree under test; other trees' presets are their own arms.
- Commit through the dotfiles repo (`git --git-dir=$HOME/.dotfiles/ --work-tree=$HOME add <explicit paths>`) — targeted paths only, **never push**.
- Destructive/long ops (`nixos-rebuild switch`, deleting `.gguf`s, stopping a container with traffic in flight): confirm with the user first.

Read `references/engine-log.md` before grepping the engine log.
