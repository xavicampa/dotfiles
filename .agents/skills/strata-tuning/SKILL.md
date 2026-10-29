---
name: strata-tuning
description: >-
  Tune/measure the Strata engine containers on the home PC: trees, presets, run configs, the llama-swap
  reload dance, bench commands, 502/OOM boot diagnosis, and the hard rules (never switch model mid-tuning,
  never hand-run `podman run`, never leave a warm engine after a preset edit, keep ~512 MiB free per GPU stage).
  Explicit-only — run with /skill:strata-tuning.
disable-model-invocation: true
---

# Tuning Strata from pi

Three Strata trees, each its own container/model pair:

| tree | preset | run config | container (proxy id) | notes |
|---|---|---|---|---|
| `1slot` | `.config/strata/1slot/strata/launch-presets/docker.json` | `.config/strata/1slot/strata-iq3_s.json` | `qwen3.8-flash-next-iq3_s` | solo, `--pipeline-windows 2` active |
| `parallel` | `.config/strata/parallel/…` | `.config/strata/parallel/strata-iq3_s.json` | `qwen3.8-flash-next-iq3_s-parallel` | batched iq3_s |
| `coder` | `.config/strata/coder/…` | `.config/strata/coder/strata-coder-iq1_m.json` | `qwen3.8-flash-next-coder-iq1_m-parallel` | expert-pruned IQ1_M |

Each tree has a `TUNING_NOTES.md` — **read it before touching that tree, write the finding there after measuring.** Findings that live only in chat have been re-litigated.

## Hard rules

1. **Never switch model mid-tuning.** llama-swap swaps out the engine under test; a request for another model id unloads the arm you are measuring and silently benches a cold boot or the wrong engine. Stop the other arm first or ask the user.
2. **Never test a knob with a hand-run `podman run`.** Only llama-swap recreates the container (with `--replace`) from the preset + env + run config; a manual container measures something that will not exist on the next boot.
3. **Never edit a preset and leave the old engine warm** — do the stop + reload in section 3 in the same tool call. That same-call rule is also what keeps *your own session* alive when pi is served by the arm under test (§3).
4. **Never leave a GPU stage under ~512 MiB free** — window graphs are captured on first use and later context growth fails.

## 1. Establish which arm is live (first tool call of every session)

Do not assume; the user switches models by using the client.

```bash
podman ps --format '{{.Names}}\t{{.Image}}\t{{.Status}}' | grep -i strata   # filter on the IMAGE, not the name
podman inspect -f 'created={{.Created}} started={{.State.StartedAt}} pid={{.State.Pid}} {{range .Config.Env}}{{println .}}{{end}}' <container>
for p in 5801 5802 8080; do printf "%s=%s\n" "$p" "$(curl -s -m 5 -o /dev/null -w '%{http_code}' http://127.0.0.1:$p/health)"; done
env | grep -E '^PI_MODEL=|ANTHROPIC_BASE_URL='                            # is this session served by the arm? see §3
```

Engine containers are named **exactly the model id** (`qwen3.8-flash-next-iq3_s`), so grepping names for `strata` finds nothing; the image (`ghcr.io/niko1221/strata`) also matches the dashboard containers, which you tell apart by cmd — engine `cmd=[run]`, dashboard `cmd=[strata monitor --url http://127.0.0.1:<engine-port>]`. `{{.State.CreatedAt}}` is not a field in this podman (`can't evaluate field CreatedAt`) — use `.Created` / `.State.StartedAt`. The port that answers `200` is the live engine; `000` means nothing is listening there (another arm's port, or the arm under test is unloaded — llama-swap boots it on the next request for its id).

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

Stop → request must be in the **same call**: a stopped container stays unloaded (`ttl = 0`), and a separate later call risks the client or another arm grabbing the swap. Expect `reload=200 t≈19-24s` (cold boot + graph capture) on the batched arms; the solo `1slot` arm measured **36-40 s** (two pipeline-window stages to capture) — a slow reload there is not a failure. llama-swap's `unloadTimeout = 40` bounds only its own stop hook — an unload timeout logged while the engine is still flushing is not a failure. `502`/`500`/`exited: 1` = read the boot before trying anything else; common causes in `references/engine-log.md`.

Never issue a request for a **different model id** while tuning an arm (hard rule 1). If a hand-run container is tempting: hard rule 2 — llama-swap recreates the container with `--replace` from preset + env + run config, so a manual `podman run` measures something that will not exist on the next boot.

### When pi is served by the arm under test

Check it in §1: `PI_MODEL` equals the arm's model id and the base URL is the llama-swap front door (`http://localhost:8080`). Then the loop is closed — this session's tokens, its slot session and its conversation cache all live inside the engine being stopped, and the session is the "traffic in flight" that cold-booted it. The dance still works synchronously, and rule 3 is exactly what makes it work:

- A tool call runs while the engine is **idle**: pi generates tokens only *between* tool calls, so `podman stop` inside a call never cuts one of your own generations in half.
- The reload `curl` at the end of that call blocks until llama-swap has recreated the container and the engine answers (`reload=200 t≈19-24s`). The engine is warm again *before* the tool result has to become the next assistant turn — **one synchronous call, session survives it.** Do the whole switch (preset edit → stop → sleep 2 → curl → read the boot) in a single tool call.
- Expect, and do not chase, the cost: the restart drops the conversation cache, so your next request re-reads the whole session cold — a few seconds of extra latency per arm switch, growing with session length.

What not to do in this state:

- **Never run the stop detached** (`setsid`, `&`, a background sweep script) "to protect the session". It decouples the reload curl from the tool call, and pi's own next request then races llama-swap's cold boot: two boots, `502` on the retry, and a bench window that measures your session's retry instead of the arm. Detached is only sound for a step that no longer needs the engine — and a tuning session always does.
- **Never move pi to another model id** to "free the arm": `ttl = 0` means that request unloads the engine under test (hard rule 1).
- A bad boot leaves you with no session *and* no way to read why, so archive the boot inside the same call — `tail -n +<era-line> "$L" > <tree>/.tune/<arm>.boot.txt` (`<tree>` = `~/.config/strata/<tree>`; era pattern in `references/engine-log.md`) — before reasoning about the `502`/`exited: 1`.

Benching while your own session is live: a bench issued **from** a tool call has no self-generated traffic in flight (the engine is idle during it), so decode is measured on a quiet box. Your live conversation does still occupy the single slot / conversation cache — the same for every arm, so the A/B stays valid, but do not compare those numbers against a table measured with the session closed.

## 4. Measure

```bash
python3 /home/javi/.config/strata/parallel/bench-util.py \
  --url http://127.0.0.1:5801 --model <engine-id> --container <container> \
  --levels 1 2 3 --rounds 4 --max-tokens 400 --csv ~/.config/strata/<tree>/.tune/<arm>.csv
```

- **400-token streams, not 250**: short generations are dominated by warm-up and verify overhead and understate decode.
- Discard the first stream at each level (window-graph capture / cache fill), and treat level 1 as decode and levels 2-3 as fan-out admission.
- Fixed-config drift is bigger than it looks: five **identical** baseline runs on `1slot` gave stage A 167.7-182.6, B 136.6-159.1, **C 130.0-159.5 (±11 %)**. The **cold prompt read is the stable control** (4,798.6-4,848.9, ±1 %) — if a knob moves it (e.g. −5 %), the effect is real even when decode medians overlap. Interleave arms (`31 33 31 33` / `V A V A`) and take **n≥4 per arm** for any effect under ~15 %, or the drift decides the winner.
- Engine-side truth, per era (both containers share one log — pick the boot by pack):

```bash
python3 /home/javi/.config/strata/parallel/erastats.py --pack coder-iq1_m   # med/p25/p75, acceptance, long-request med, prefill, cache hits
```

- GPU side, always both: `nvidia-smi --query-gpu=index,name,memory.used,memory.total,utilization.gpu,power.draw --format=csv,noheader`, and for placement/leaks `nvidia-smi --query-compute-apps=gpu_uuid,pid,used_memory --format=csv,noheader` (map uuid → index; the vision tower is its **own** process row).
- One knob per arm. Everything else byte-identical, else the result is unattributable.
- Pool samples, not medians: the boot line carries the effective argv, so **eras self-label by arm** (`--layer-split` / `--pcie-frac` / `--gpu` / `--mtp`). Parse the `strata serve: prompt … generated …` lines across eras to get 12 decode samples from 5 boots instead of 5 medians — and filter by the full argv, or the next arm that shares your split lands in your pool (it did: an MTP arm polluted the split-30/frac-0.00 pool).
- Read an instrument **in-era**. The `KV streaming: …% of N block reads hit VRAM` line bucketed by prompt size is near-noise-free *within* one era (median vs worst ~0.4 points across rounds) and is the right way to judge KV knobs; pooled across eras it measures the traffic mix instead. Cross-era pooling here invented a +1.4-point deep-context gain for `--kv-resident 49152` that a same-era control erased (97.57% vs 97.41%).
- Gate the bench on the boot: parse the new era for `<n> of its <n> profiled pairs` (short = residency lost), both `MiB of VRAM free with everything loaded` lines (≥512), and absence of `LOW`/`WARNING` — then bench. A failed gate costs one reload, not a reload plus a wasted bench. Run arms through the tree's runner so they are switched identically: `~/.config/strata/1slot/tune-arm.sh <label> [split=N] [kv=N] [frac=X] [mtp=on|off] [vision=gpu|cpu] [--no-bench]`, `ROUNDS=2` for two bench rounds per boot, artifacts (boot/bench/era line) in `<tree>/.tune/`.

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
- **Consecutive boots differ at identical config** when `--expert-profile-save` is on: the learned profile is rewritten by whatever the previous run did. Two identical `1slot` boots came out `62% resident / 763 MiB free` and `61% / 1021 MiB free`. Attribute an arm from the argv and the pair counts (`9216 of its 9216 profiled pairs`), and treat `res%`/free-VRAM deltas as context, not signal — that boot-to-boot swing is bigger than most knobs.
- Judge a knob's *reachable* effect before chasing medians: `--pcie-frac` moved only the routed slice (none → 0.3/1.4/3.0 % of lookups over PCIe) while the arena, pair counts and the stable cold read were identical, so no split of it can beat ±11 % decode noise. Swept 0.00/0.20/0.40/0.60 on `1slot`: a tie, and **0.20 is what both `1slot` and `coder` now run** — do not re-sweep it unless the mechanism changes (residency far below 60 %, or a second engine making the other card's VRAM the cheap tier).
- `--kv-resident` steps are cheap where you expect them to be expensive and expensive where they hurt: on a split with a **profile-capped** last stage (`9216 of its 9216 profiled pairs`), 32768→49152 cost CUDA1 only ~84 MiB but took **196 slots** off the first stage's expert cache — the binding resource. So `kv-resident` cannot fund extra layers on the last stage (20480 at split 29 still came out `9413 of 9728`), and never fund anything with `--vram-reserve-later-mib` (window graphs need that room). The only lever that ever bought a layer there was physical GiB on that card (vision off the GPU: 798 → 1,139 MiB).
- The engine **port moves** with the llama-swap entry (1slot is `PORT=5802`; its notes and `bench-1slot.py` said 5801). Read `-e PORT` from `podman inspect` and patch the tree's bench script (with a `.bak`) — a bench aimed at a dead port prints `HTTP` failures or measures another arm.
- If `PI_MODEL` is the arm under test, §3 "When pi is served by the arm under test" applies — the reload is synchronous by design, and the tempting "detached sweep script" breaks the measurement rather than protecting the session.
- The `gpus` role swap only pays if the **last** stage's card can hold its whole span in VRAM (it also carries head + drafter). It depends on the pack's pairs/layer: accepted on the pruned coder pack (256 pairs/layer → 17 layers = 8.78 GiB fits the 5070 Ti, +13 % decode), **rejected** on `iq3_s` (512 pairs/layer → 17 layers = 17.55 GiB never fits 16.3 GiB; the fitted `[1,0]/38` boot was clean — stage 1 fully resident, 802/1,459 MiB free, acceptance unchanged — yet decode −33…−42 % and cold prompt read −66 %). Never copy a split or an order between packs; recompute from pairs/layer.

## 7. Etiquette

- Backup before editing: `cp file file.bak-<date>-<why>`; leave the `.bak` files untracked.
- Touch only the tree under test; other trees' presets are their own arms.
- Commit through the dotfiles repo (`git --git-dir=$HOME/.dotfiles/ --work-tree=$HOME add <explicit paths>`) — targeted paths only, **never push**.
- Destructive/long ops (`nixos-rebuild switch`, deleting `.gguf`s, stopping a container with traffic in flight): confirm with the user first.

Read `references/engine-log.md` before grepping the engine log.
