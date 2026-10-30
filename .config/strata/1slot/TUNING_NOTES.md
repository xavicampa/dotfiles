# Strata 1slot — tuning notes (qwen3.8-flash-next-iq3_s)

Box: RTX 5070 Ti (CUDA0) + RTX 3090 Ti (CUDA1, 23.6 GiB), 62.3 GiB RAM, 24-core CPU (15 pool workers).
Container `qwen3.8-flash-next-iq3_s`, preset `docker`, **port 5802** (`-e PORT` in the llama-swap entry — 5801 is stale; `bench-1slot.py` patched 2026-10-29, backup `bench-1slot.py.bak-20261029-port5802`), engine 0.1.52 linux-x86_64-cuda-cuda13.
Single slot (no `--batch`), 262,144 ctx, IQ3_S (46.8 GiB experts, 48 layers, 512 pairs/layer), PLE table 26.8 GiB.
Config lives in **two** places: `strata/launch-presets/docker.json` (preset `extra`) **and** `strata-iq3_s.json`
(the installed config, which is the base every launch is built from — see "merge order").

## Current best config (2026-10-26, arm 5) — live now

> **Superseded 2026-10-29:** `--layer-split 30` + `"vision": {"gpu": false}` is the keeper
> (see "Vision off the GPU buys the GiB — split 30" below). Everything in this section still holds
> except the split (31 -> 30) and CUDA1's free-VRAM numbers (798 -> 1,139 MiB).

preset `extra`:

```
--resident-experts on     --adapt-async 1   --adapt-every 1   --adapt-swaps 160   --adapt-decay 0.97
--layer-split 31          --kv-resident 32768
--pcie-frac 0.00          --pipeline-windows 2
--spec 4                  --spec-min-p 0.70 --trim-stage-weights
--vram-reserve-mib 1024   --vram-reserve-later-mib 1024
--conversation-cache-mib 1024 --conversation-cache-min-tokens 256 --conversation-cache-park-gain 512
```

> **Conversation-cache values superseded 2026-10-30** — the three `--conversation-cache-*` values above are
> the old ones; the arm now running is **`mib 6144 / min-tokens 8192 / park-gain 16384`**. See
> “Conversation cache: a 1024 MiB pool cannot hold one pi session” at the end of this file.
--expert-profile /data/state/strata/profile-learned.bin (+ --expert-profile-save)
```

`--kv-resident 32768` is on because it is what pays for split 31 (see "Split 31" below); `20480` was measured
as no gain (CUDA0 +45 slots, CUDA1 +62 MiB margin, decode slightly lower). Setup's own value for ctx >= 64K is
32768; `tune_knobs.py` treats values below that at 128K+ as never-pick ("22 % to 34 % slower … only 49152 and
65536 flat or better").
`strata-iq3_s.json` mirrors the live args (no `env` block any more).

**Where `STRATA_SPLIT_RING=384` lives:** only in the container cmd of
`~/.config/nixos/homepc/configuration.nix` (`-e STRATA_SPLIT_RING=384`). It went live with the
2026-10-26 01:07 container (`docker inspect .Config.Env` lists it, and the engine prints the streamed-ring
line); the copy in the preset `extra` and the stopgap `env` block in `strata-iq3_s.json` were both removed.
If you ever put it back in the run config's `env`, note that it is applied **on top of** the container env —
two copies then have to be kept in step.

After a rebuild, a preset change or any restart, confirm the ring is still in play; it falls back to 96
silently (−16 % cold prompt reads) and the only proof is in the engine log:
`layer split: NN% of the experts resident, the prompt path's streamed ring 384 slots` and
`lend sizing: the prompt path borrows ~3,790 slots (ring 384 at chunk 8192), … keep their experts in RAM too`.

Start-up state to expect:

- `resident RAM mode: ~25.7 GiB of experts in RAM (page-locked), ~5,950 in the GPU cache … (no file reads)`
- `layer split: 60% of the experts resident, the prompt path's streamed ring 384 slots`
- `lend sizing: the prompt path borrows ~3,788 slots (ring 384 at chunk 8192), 3788 of them keep their experts in RAM too`
- `KV streaming: 32768 of 262144 cells per QSA layer in VRAM, the K/V in 1.80 GiB of pinned RAM`
- CUDA0 expert cache ~5,947 slots (10.91 GiB), **CUDA1 8,704 slots of 8,704 profiled pairs (17.55 GiB)**
- free VRAM with everything loaded: CUDA0 ~759 MiB, CUDA1 ~822 MiB
- `MemAvailable` ~19-20 GiB, swap flat, page cache ~23 GiB (the PLE table stays warm: ~0.0 GB read from the drive per prompt)

## Measured (bench-1slot.py, greedy, identical prompts every arm; full table in BENCH-1slot.md)

| metric | arena (old) | resident + ring 96 | **resident + ring 384 (now)** |
|---|---|---|---|
| cold 84,678-token read | 4,633 tok/s | 3,881–3,906 (**−16 %**) | **4,727 (+2 %)** |
| in-session 81K / 88K reads | 4,604 / 4,310 | 3,848 / 3,628 | 4,638 / 4,386 |
| decode @2-3K ctx | 152–155 | 150–174 | 141–193 |
| decode @80K ctx | 142.9 | 138–149 | 148–163 |
| decode @170K ctx | 123–135 | 124–137 | 128–138 |
| decode cache hit rate | 84.5–88 % | 85–90.5 % | 87–91.5 % |
| experts pinned in RAM | **46.84 GiB** (swapping, MemAvailable 2.9 GiB) | 26.7 GiB | 28.1 GiB (MemAvailable ~19 GiB) |
| CUDA1 free VRAM | 808 MiB | 844 MiB | 840 MiB |

Decode is flat across all arms (spread ±7 % swamps the differences); the real wins are **RAM** and the
**prompt path**, and the prompt path is decided by the ring.

## Split 31 + KV streaming (arms 6/7, 2026-10-26) — the current keeper

Your 3slots note rejected split 31 because CUDA1 stopped being fully resident (needed 17.55 GiB, room ~17.4 GiB,
residency 8,633/8,704, CUDA1 `wait + pool` 7-9.5 ms/window). On 1slot **KV streaming buys exactly the GiB the
17th layer costs**: 512 pairs x 2.11 MiB = 1.08 GiB, and CUDA1's free VRAM goes 808 -> 2,026 MiB once only 32768
cells per QSA layer stay in VRAM. So at split 31 + `--kv-resident 32768`:

- `CUDA1 … expert cache 8704 slots (17.55 GiB), 8704 of its 8704 profiled pairs` — full, from 17.70 GiB of room
- CUDA0 cache 4,888 -> **5,947 slots**, residency 53 % -> **60 %**, hit rate 88-93.5 %
- decode at deep context: **145-156 tok/s at 182-190K** (real session) vs **124-140 tok/s at 148-175K** with
  split 32/KV in VRAM — about **+15 %**
- cost: cold 84.7K prompt read 4,727 -> **4,476 tok/s (-5.3 %)**, in-session reads -3…-6 %
- `--kv-resident 20480` at split 31: reads unchanged, CUDA0 +45 slots, CUDA1 +62 MiB margin, decode a bit lower ->
  keep 32768

**Margin is thin and worth watching**: CUDA1's expert room at split 31 is 17.70-17.76 GiB and the 17 layers need
17.55 GiB, i.e. ~150-200 MiB of play. Vision runs on CUDA1 (`cuda_device: 1`). After any change that touches
CUDA1 (vision, a second install on the card, bigger `--vram-reserve-later-mib`), check that the start still says
`8704 of its 8704 profiled pairs` and that CUDA1 free VRAM stays >= 512 MiB; if the pair count drops, go back to
`--layer-split 32` (the 3slots failure mode, not a warning).

## What each knob did here

- **`--resident-experts`** — pins only the experts no card caches (28.1 GiB instead of the 46.84 GiB arena),
  which is what stopped the swapping and gave the PLE table its page cache. It also is the only way to get
  `--adapt-async` on a split: in arena mode the engine prints
  `--adapt-async 1 is off (not with a layer split in the arena mode): the blocking adaptive tier`.
- **`STRATA_SPLIT_RING=384`** — the fix for resident mode's prompt regression. Resident mode runs a 96-slot
  prompt ring (`borrows 2,777 slots`), arena mode's pinned-share rule had borrowed 3,858; 384 lifts the borrow
  to 3,512 and the cold-read speed from 3,906 to 4,727 tok/s. Costs ~1.4 GiB more pinned RAM (the RAM copy
  keeps the borrowed experts). `0` is a no-op in resident mode — the pinned-share borrow is not reachable.
  Untested next step: 768 (watch for `K of them keep their experts in RAM too` going below N + a WARNING).
  It is an engine **environment** variable, so the container cmd (nix) is the durable place for it; a preset
  `extra` entry also works (bare name, no `--`) but is one more copy.
- **`--kv-resident 32768`** — nearly free on the prompt path (3,881 vs 3,906) and it freed CUDA1's VRAM
  (808 → 2,026 MiB) and +1,020 CUDA0 expert slots, but decode at 170K came in ~10 tok/s lower and nothing
  else moved, so it is out at single-slot 262K. Re-test `--kv-resident 65536` if real sessions start going
  past ~150K (KV in VRAM costs ~13.7 KB per context token; 262K ≈ 3.6 GiB); `tune_knobs.py` treats
  anything under 49152 at 128K+ as never-pick ("22 % to 34 % slower").
- **`--pcie-frac 0.00`** — still right, and now measured rather than assumed: a one-key standard-v1 A/B against
  `0.20` moved nothing (§ `--pcie-frac` A/B below). Keep 0.00; the PCIe path was never the limiter here.

## `--pcie-frac` A/B — 0.20 vs 0.00 (2026-10-29, standard-v1, engine 0.1.52)

The cleanest A/B this tree has had: `2026-10-29-standard-homepc-2` (`--pcie-frac 0.20`, engine boot 12:05:14Z)
vs `2026-10-29-standard-homepc-3` (`0.00`, boot 12:27:51Z). The configuration blocks differ in **exactly one key**
(27 others identical), same corpus `e75eff8b…`, same template/sampling, capacity 1, context 262144, both
`--no-start --skip-model-hash` (so both `nonconforming` for provenance only), **12/12 sanity**, 78 s each.
`2026-10-29-standard-homepc-1` (also 0.20, same engine) is the replicate.

| metric | 0.20 | 0.00 | Δ |
|---|---|---|---|
| prompt-4k tok/s | 2078.5 (2071–2081) | 2055.8 (2054–2076) | −1.1% |
| prompt-16k tok/s | 3399.4 (3399–3406) | 3330.3 (3324–3332) | −2.0% |
| prompt-4k decode | 122.9 (121–158) | 139.2 (130–155) | +13.2% |
| prompt-16k decode | 136.6 (134–149) | 138.0 (132–160) | +1.1% |
| short decode | 157.1 (149–161) | 150.4 (138–170) | −4.3% |
| TTFT 4k / 16k | 1.985 / 4.843 s | 2.008 / 4.942 s | +1.1% / +2.0% |
| total 4k / 16k | 6.14 / 8.58 s | 5.68 / 8.64 s | −7.5% / +0.7% |

**Verdict: no measurable effect.** The same box, *identical* config, two runs (runs 1 vs 2 — same engine, same
flags) spread **prompt tok/s ±0.5–2%, TTFT ±2%, decode ±15%** at n=3; 4k decode alone went 144.3 vs 122.9
(15%). So the +13.2% at 4k decode here is the noise, not the frac. Use **±15% for decode medians** in
`standard-v1` (n=3/case), not the ±8% that came out of the parallel suites.

The knob is live but idle here — from `docker.engine.log`, per window:

| | 0.20 (63 reqs) | 0.00 (35 reqs) |
|---|---|---|
| requests with PCIe / other-GPU expert reads | **63/63** | **0/35** |
| those reads as % of routed lookups | med 0.30%, max 2.10% (282 reads med, 948 max) | 0 |
| expert reads off the file tier per request | med 0.0 MB | med 111.7 MB |
| OS storage reads per request | med 36.4 MB | med 115.5 MB |
| decode expert-cache hit rate | med **91.20%** (max 96.2) | med **91.30%** (max 96.5) |

and **nothing about the layout moved**: streamed ring 384 slots at chunk 8192, prompt path borrows 1984 vs 1978
CUDA0 cache slots (3.66 GiB), split stages lend 3810 vs 3804 slots (7.31 vs 7.32 GiB), expert cache 4392 slots,
759 MiB VRAM free, KV 32768/262144 + 1.80 GiB pinned — all identical. At capacity 1 `--pcie-frac` chooses only
**where a miss is served**, not how much arena each part gets. It is a wash because residency already covers the
working set: 60% of experts resident, ~91% hit, so the frac only ever had ~0.3% of lookups to move and the file
tier serves them just as cheaply. Same conclusion the boot banner gave (`pcie_share ~0.000–0.011`; coder: 12.44 ms
streamed of a 4500 ms request) — now with end-to-end numbers attached.

Confounds, both pushing *against* 0.00 and it still tied: run 3 started 42 s after its engine boot (1 prior
request) while run 2 started 4.4 min after (41 prior), so run 3 had the colder page cache — the worse state for a
setting that pushes misses onto the file tier (its OS reads went 36 → 115 MB/req).

Applied: `0.00` in the run config args (`strata-iq3_s.json`) **and** preset `extra` — both carriers, so the manual
`run-iq3_s.sh` path and the launch path agree. Backup `strata-iq3_s.json.bak-pre-pcie0`. **Do not carry this result
to the coder tree** (still 0.20): there four slots share a smaller arena and the working set can spill past
residency, which is exactly when the frac would bind — and coder has never run `standard-v1`, only the parallel
suites, so it needs its own one-key A/B first.

## Guardrails / watch

- CUDA0 free VRAM at start is ~757 MiB; the engine's own safety line is **512 MiB at request start**
  (`decode falls to a few tok/s and a window may never finish`). Keep `--vram-reserve-mib 1024`.
- Per-request `resident RAM: … N blob reads from the file` should stay in the tens, not thousands — if it
  grows, the pinned complement stopped covering the working set (ring too big, RAM tight).
- RAM levers if it tightens: `--conversation-cache-mib`, `STRATA_RESIDENT_HEADROOM_GIB` (4 GiB free by default),
  `STRATA_SPLIT_RING` (nix container cmd only).
- `strata-iq3_s.json` and the preset now agree on `--layer-split 30` (synced 2026-10-30, backup
  `strata-iq3_s.json.bak-20261030-syncsplit`; the launch path is unchanged, the preset `extra` set the split
  all along). **Still divergent on the manual path:** the run config has no `--kv-resident`, so `run-iq3_s.sh`
  starts with the KV in VRAM instead of `--kv-resident 32768` — sync that or retire the script before trusting
  it.
- Image env already sets `STRATA_EXCHANGE_ROTATE=1` (`exchange buffer rotation enabled … 1.51 GiB page-locked`)
  and `STRATA_ADAPT_LAG=2`, `STRATA_PF_FUSED=1` — they apply to resident mode too.
- The 3slots install shares this volume's `/data/state` and also uses preset name `docker`
  (`state/strata/launch/docker.json`, `docker.choices.json`, the runtime profile lock). Run one at a time;
  the state file is regenerated per launch, but the learned profile `state/strata/profile-learned.bin`
  belongs to whichever install saved it last.

## Merge order (why a flag can come back)

`strata_cli/launch/runner.py:derive_config`: base = **installed config** (`strata-iq3_s.json`), then the preset's
`extra` on top via `tune_knobs.apply_to_argv`. Extras **add or override**; they never remove.
To remove a flag: `"--flag": "off"` in the preset `extra` (`as_argv_changes`: "off/false/no/none removes it")
or delete it from the installed config. Env vars go in `extra` under their bare name.

## GPU role swap `[1, 0]` — REJECTED on this tree (2026-10-29 ~23:00, engine 0.1.52)

The coder tree's `"gpus": [1, 0]` win (see `coder/TUNING_NOTES.md` § "GPU role swap") was listed as untested
here. `"gpus"` is `--gpu LIST` (sets `CUDA_VISIBLE_DEVICES`/`CUDA_DEVICE_ORDER` in the engine), so the stage
order follows the list and **head + draft layer + draft head + slot drafters follow the last stage** — the only
lever over which card carries them. Tried here as `[1, 0]` + `--layer-split 38`, one knob, everything else
byte-identical.

**Why coder's number does not transfer: this model has 512 pairs/layer, coder is pruned to 256.** 17 layers here
are 8,704 slots = **17.55 GiB**, which cannot exist on the 16.3 GiB 5070 Ti at all (coder's 17 layers were
4,352 slots = 8.78 GiB, which is why coder could keep split 31 after the swap). A fitted split is required:
the 5070 Ti as last stage leaves `room for experts ≈ 12.2 − 0.13·k` GiB after head (~1.7 GiB incl. the
213 MiB draft head), draft layer 837 MiB, pipeline windows 340 MiB, `--vram-reserve-later-mib 1024` and dense
0.126 GiB/layer, while full residency costs 1.03·k GiB → **k ≤ ~10 layers, split ~38**. Boot at 38 confirmed
the fit exactly (`room for experts 11.53 GiB` → `expert cache 5120 slots (10.73 GiB)`):

```
strata generate: layer split across 2 GPUs: CUDA0, then CUDA1 (split 38)
strata generate: layer split: CUDA0 loads the dense weights of layers 0-37 only
strata generate: layer split: CUDA1 runs layers 38-47, expert cache 5120 slots (10.73 GiB), 5120 of its 5120 profiled pairs
strata generate: layer split, CUDA1: 12.78 GiB free of 15.56, room for experts 11.53 GiB
strata generate: expert cache 9129 slots, 17.01 GiB of VRAM                       <- CUDA0 = nvidia-smi index 1 (3090 Ti)
strata serve: layer split: 58% of the experts resident, the prompt path's streamed ring 384 slots
strata generate: resident RAM mode: 26.41 GiB of experts in RAM (page-locked), 9129 in the GPU cache
strata serve: 802 MiB of VRAM free with everything loaded / CUDA1: 1459 MiB free
```

Label trap confirmed: with `[1, 0]` log `CUDA0` = nvidia-smi **index 1** (3090 Ti). Verified by
`--query-compute-apps`: engine 22,176 MiB on the 3090 Ti, 14,386 MiB on the 5070 Ti, and `strata-vision`
1,252 MiB still on **physical** index 1 (`vision.cuda_device` does not follow the swap).

Health gate **passed**, so the loss is not residency or paging: stage 1 `5120 of its 5120 profiled pairs`,
free 802 / 1,459 MiB (both ≥ 512), no `LOW` / `WARNING` / `decode window`, drafting alive
(`accept 74.5%`, `drafts/step 3.91`, `yield gen/fed 1.436` vs baseline `74.9% / 3.99 / 1.286`).

Measured with `bench-1slot.py 1` (greedy, identical prompts; run from inside a tool call, so the engine is
idle and there is no self-generated traffic — this session is served by the arm, see skill §3 "When pi is
served by the arm under test"):

| metric | A0 `[0,1]/31` | **`[1,0]/38`** | A1 `[0,1]/31` re-bench |
|---|---|---|---|
| A `<40K` ctx decode | 174.4 | **117.3** (−33 %) | 169.5 |
| B `40-100K` decode | 140.9 | **90.0** (−36 %) | 140.5 |
| C `>100K` decode | 140.2 | **81.8** (−42 %) | 130.0 |
| D cold 84,678-token read | 4,848.9 (17.5 s) | **1,657.0 (51.1 s, −66 %)** | 4,807.5 (17.7 s) |
| era decode med (n≥9) | 172.3 | **84.8** | — |
| experts in GPU caches | 5,921 + 8,704 = 28.4 GiB, 60 % resident | 9,129 + 5,120 = 27.7 GiB, **58 % resident** | 60 % |
| KV streaming pinned RAM | 1.80 GiB | 2.32 GiB | 1.80 GiB |

A1 re-bench brackets the drift at **≤7 %** (A −3 %, B flat, C −7 %, cold read −0.9 %), so the swapped arm's
−33…−42 % decode and −66 % prefill are far outside noise. Bench wall-time also tripled (1 m 25 s → 3 m 31 s).

**What the log says the mechanism is.** Total expert coverage is unchanged (27.7 vs 28.4 GiB in the caches),
but the **fully-resident span shrank from 17 layers (the 3090 Ti) to 10 (the 5070 Ti)**, because the small card
cannot cache 17 layers of a 512-pair model once it also carries head + drafter + reserve. The 3090 Ti then owns
38 layers with only 9,129 of its 19,456 pairs in VRAM, and those misses stop being promoted into a cache: per
window the engine's own counter moved `13688 → 30912 exchanged with the VRAM tier` (≈3 k/window) against the
baseline's `170289 → 188745` (≈30 k/window) at the **same ~92 % hit rate**, and `0 blob reads from the file`
(vs 305-504). The prompt path takes it hardest — the boot's `prefill plan` still promised
`about 0.0 GB read from the drive per 32768-token prompt`, while the request line reports
`the OS read 58162.9 MB from storage (18 major faults) for 29790.6 MB of expert reads`.

**Rule to carry forward:** in `[0, 1]` the last stage is the card that must be able to hold **its whole span**
in VRAM, and at 512 pairs/layer only the 3090 Ti can hold ≥17 layers. The `gpus` swap pays on the pruned
coder pack and costs ~2× on this one. Keep `"gpus": [0, 1]` + `--layer-split 31` (restored; preset verified
byte-identical to `docker.json.bak-20261029-gpusorder` apart from the engine's own `last_used`).

Not run, and why: `[1,0]/36` (stage 1 would need 12.4 GiB of experts in ~11 GiB of room → boot-gated out
before spending a bench on it); `[0,1]/29-30` (18-19 layers = 18.6-19.6 GiB against CUDA1's 17.70-17.76 GiB of
room → predicted residency loss, only worth an arm if CUDA1 first gains ~1-2 GiB). The lever that would buy
those GiB is **vision**: 1,252 MiB on physical index 1 = CUDA1 in this order; `"gpu": false` in the run config
frees it, and one more fully-resident layer costs 1.03 GiB. Coder measured the CPU tower as latency-equivalent
for text (cold image 3.86 s vs 2.81 s GPU), but it shares the machine with the 15 expert-pool workers.
Untested here. Reload cost measured on this tree: `reload=200 t=35.8-40.1 s` (cold boot + window-graph capture
for 2 pipeline windows), not the 19-24 s the skill quotes for the batched arms.

## Vision off the GPU buys the GiB — split 30 is the new keeper (2026-10-29 ~23:30-00:10, engine 0.1.52)

The GPU-swap section above showed CUDA1 (the 3090 Ti, last stage, carries head + drafter) is the binding
resource: 17.70-17.76 GiB of expert room against 17.55 GiB for its 17 layers. Two single-knob ways to widen
it were tried, each at splits 31 / 30 / 29, all other bytes identical, `bench-1slot.py 1` per arm.

**(2) `"vision": {"gpu": false}` in `strata-iq3_s.json` — accepted as the enabler.** Vision lives on
**physical** index 1 = CUDA1 in this order, and it costs 1,252 MiB: the boot line moves
`CUDA1: 798 MiB free` → **`2055 MiB free`** and `nvidia-smi --query-compute-apps` loses the `strata-vision`
row. At the *same* split 31 it changes text speed by nothing measurable
(A 172.9 / B 148.4 / C 130.2 / cold read 4,805.4 — one sample, inside baseline drift). It is headroom, not speed.

With that GiB, **split 30 fits**: `layer split: CUDA1 runs layers 30-47, expert cache 9216 slots (18.37 GiB),
9216 of its 9216 profiled pairs`, `layer split: 62% of the experts resident` (was 60%), free
**CUDA0 763 / CUDA1 1,139 MiB** — i.e. the residency went up *and* both cards ended with more free VRAM than
the split-31 baseline (759 / 798). **Split 29 does not fit**: `9384 of its 9728 profiled pairs` — the
page-locked-RAM expert path rejoins decode, gate failed, no bench spent. Split 30 is the ceiling.

**(1) `STRATA_MTP_STAGE0=1` (preset `extra`, bare name — no rebuild) — REJECTED, but it is NOT inert here.**
Contrary to the coder tree's finding (inert under `--batch`), in solo mode it binds: the boot note
`--pipeline-windows 2 ... without the draft layer on the first card` **disappears**, and CUDA1 free rises
798 → **1,860 MiB** (≈ draft layer 837 + draft head 213). But the drafter is now charged to the **streaming**
stage: residency falls to 57% (split 31) and 59% (split 30), and decode collapses:

| arm | A | B | C | cold read |
|---|---|---|---|---|
| M1 `[0,1]/31` + MTP_STAGE0 | 157.4 | 114.2 | 106.4 | 4,554.7 |
| M2 `[0,1]/30` + MTP_STAGE0 | 163.9 | 127.4 | 120.2 | 4,623.6 |

Both are far outside drift, and the *stable* metric (cold read) is also down 4-5%, so this is a real loss:
moving the drafter off the last stage takes VRAM from the **streaming** stage's expert cache, which is worth
more than an extra resident layer. Do not re-test at other splits without a reason.

### Keeper vs baseline, interleaved (this is the honest version)

Fixed-config decode drift on this box is **bigger than the ±7% I first bracketed**: across five identical
baseline runs, stage A 167.7-182.6, B 136.6-159.1, **C 130.0-159.5** (±11%). The cold prompt read is the stable
control (4,798.6-4,848.9, ±1%). So arms were interleaved `V2 A V2 A V2 A V2` and judged on medians:

| stage | baseline `[0,1]/31` + vision GPU (n=5) | **keeper `[0,1]/30` + vision CPU (n=4)** | Δ med |
|---|---|---|---|
| A `<40K` decode | 174.4 (167.7-182.6) | **187.0** (177.6-196.6) | **+7%** |
| B `40-100K` decode | 140.5 (136.6-159.1) | **158.6** (138.9-163.8) | **+13%** |
| C `>100K` decode | 135.8 (130.0-159.5) | 139.0 (135.1-150.3) | +2% (noise) |
| D cold 84,678 read | 4,807.5 | 4,831.7 | +0.5% (flat) |

3 of the 4 keeper B samples sit above 4 of the 5 baseline samples, but the ranges overlap (keeper min 138.9,
baseline max 159.1), so treat the decode gain as **+7-13% likely, not proven**. The deterministic part of the
change is health: `62%` vs `60%` resident, `9216/9216` vs `8704/8704` full pairs, and CUDA1 free
**1,139 vs 798 MiB** — which also answers the old "margin is thin" worry in the Split-31 section.

**Cost, stated plainly:** image prompts are now projected on the CPU (12 threads, `on the CPU, N threads,
no warm-up`), sharing the box with the 15 expert-pool workers. Coder measured this as near-equal for text and
for small/medium images, but ~1 s worse on a cold image (3.86 s vs 2.81 s). `vision.max_tokens` stays 512 in
the run config. If images matter more than text on this arm, revert with one line:
`"vision": {"gpu": true}` (and step back to `--layer-split 31`, since 30 needs the tower's 1.25 GiB).

Applied: preset `extra["--layer-split"] = "30"`, run config `vision.gpu = false`. Backups
`strata-iq3_s.json.bak-20261029-vision`, `docker.json.bak-20261029-mtparms`. Arm boots/benches:
`/tmp/gpuswap/{V1,V2,V2c,V2d,A2,A3,A4,M1,M2}*.boot.txt|.bench.txt|.era.txt`; gate script `/tmp/gpuswap/arm.sh`.

## `--pcie-frac` swept under the new layout — still a wash, keep 0.00 (2026-10-30 ~00:05, engine 0.1.52)

The 2026-10-29 A/B (standard-v1, split 31) said 0.20 vs 0.00 was a wash, but it rested on n=3 runs inside a
±15 % noise band. Re-measured at the keeper layout (`[0,1]/30`, vision on CPU, 61-62 % resident) at
**0.00 / 0.20 / 0.40 / 0.60**, one knob, arms interleaved, per-request samples pooled from the log.

What the knob demonstrably does — monotonic, engine-side:

| `--pcie-frac` | routed lookups read over PCIe / from another GPU | arena & residency | cold read (stable control) |
|---|---|---|---|
| 0.00 | none — the hit-rate line carries no PCIe clause at all | `9216/9216`, 61-62 %, free 763-1021 / 1139 MiB | 4,794.5-4,920.9 |
| 0.20 | 0.2-0.3 % (`711 more read by the GPU over PCIe or from another GPU (0.3% of all 254499 routed)`) | identical | 4,798-4,804 |
| 0.40 | 1.1-1.7 % | identical | 4,801 |
| 0.60 | 3.0-4.0 % (`16456 more read … (3.0% of all 542205 routed)`) | identical | 4,802-4,805 |

Decode, pooled per request (bench stages, split 30, MTP-off eras only — `/tmp/gpuswap/fractab.py`):

| frac | A (ctx ~2-3K) | B (ctx ~81-84K) | C (ctx ~171-175K) | cold 84,678 read |
|---|---|---|---|---|
| 0.00 | med ~187 (n=12, 161-231) | med ~150 (n=12, 134-180) | med ~139 (n=6, 128-154) | 4,801 (n=6) |
| 0.20 | med ~193 (n=6, 142-245) | med ~154 (n=5, 142-179) | 144-147 (n=3) | 4,802 (n=3) |
| 0.40 | 192.6 (n=2) | 140.9 (n=1) | 130.5 (n=1) | 4,801 (n=1) |
| 0.60 | 179.2 (n=4) | 142.2 (n=4) | 128.4 (n=2) | 4,804 (n=2) |

**Nothing to take.** The only monotonic change is the routed slice (0 → 3-4 % of lookups) — `expert cache auto:
12.27 GiB free, 1024 MiB reserved -> 4426 slots`, `9216 of its 9216 profiled pairs` and `62% of the experts
resident` are identical at every frac, and the ±1 %-stable cold read never moves (4,798-4,805). An effect that
can only touch 3 % of lookups is invisible against ±11 % decode noise, and the ladder is non-monotonic
(0.20 medians sit a few % above 0.00, 0.40 and 0.60 at or below it), which is what noise looks like.
Statistically this is a **tie** — do not spend arms on intermediate fracs.

### Adopted anyway: `--pcie-frac 0.20` is live on this tree (2026-10-30, operator's call)

The evidence does not separate 0.20 from 0.00, so this is a judgement call, not a measurement: 0.20 was the only
nonzero frac whose medians sat above 0.00 in all three decode buckets (+6-8 %, ranges fully overlapping), it
costs nothing measurable, and it matches the `coder` tree, so both trees now carry the same value
(`docker.json.bak-20261030-pre-pcie020` is the 0.00 state if anyone wants it back). First boot after the
switch, for the record: `9216 of its 9216 profiled pairs`, `61% of the experts resident`, free 1019/1139 MiB,
routing `598-1583 more read by the GPU over PCIe or from another GPU (0.3-0.4% of all routed)`, bench
`A 202.3 / B 141.8 / C 128.8 / cold read 4,803.4` — B and C landed at the low end of the band, a reminder that
this value neither helps nor hurts.

**Future A/Bs on this tree start from `--pcie-frac 0.20`** (the live value), and do not re-litigate it without
a mechanism: at capacity 1 it chooses only *where a miss is served*, and the miss it can move is 0.3-0.4 % of
routed lookups. If the arm ever changes enough for the mechanism to bind — residency dropping well under 60 %,
or a second engine on the box making the other card's VRAM the cheap tier — that is the trigger to re-measure.

The IO tie-breaker from the old A/B did **not** reproduce: it had OS storage reads 36 vs 115 MB/req favouring
0.20. Here file-tier blob reads are ~0 in every arm (`max 36` in one window, median 0, sum 0-69 per era), so
there is no IO argument in either direction at capacity 1.

### Confound found while doing this — read before any A/B on this tree

**Consecutive boots are not identical at fixed config**, because `--expert-profile-save` re-learns
`state/strata/profile-learned.bin` from whatever the previous run did. Two identical
`split 30 / frac 0.00 / vision cpu` boots came out `62% of the experts resident … 763 MiB free` and
`61% … 1021 MiB free` (CUDA1 1,139 in both). That swing is larger than anything `--pcie-frac` produces, so
the residency/free-VRAM boot lines **cannot be used to attribute an arm** unless the learned profile is held
constant — attribute from the argv and the pair counts, and treat `res%`/free as context, not signal.

Method that worked: `/tmp/gpuswap/fractab.py` pools per-request engine numbers across eras and labels each
era from the boot line's own effective argv (`--layer-split` / `--pcie-frac` / `--gpu`) — 12 decode samples
from 5 boots instead of 5 medians. It also caught a mistake in my first pass: the "pooled 0.00" number had
the MTP arm (also split 30, frac 0.00) mixed into it. Filter on `--mtp`/the pipeline note when pooling.

Live arm: `[0,1]`, `--layer-split 30`, `--pcie-frac 0.20`, `vision.gpu=false`
(`9216/9216` pairs, 61 % resident, free 1019/1139 MiB, cold read ~4,803).

## `--kv-resident` swept 20480 / 32768 / 49152 — keep 32768, and stop sweeping it (2026-10-30 ~00:40)

Reason it looked worth testing: the KV VRAM hit rate degrades hard with context when pooled across eras
(`<40K 99.90% · 40-110K 98.47% · 110-180K 96.22% · >180K 94.06%`), and this session routinely runs past 150K —
which is exactly the trigger the old notes named ("re-test `--kv-resident 65536` if real sessions go past
~150K"). Bounded 3-arm plan, `[0,1]` + `--pcie-frac 0.20` + `vision.gpu=false` throughout, 2 bench rounds/arm.

| arm | split | kv-res | stage1 pairs | res% | free CUDA0/CUDA1 | stage-0 GPU cache | KV hit 110-180K (**same era**) | A | B | C | cold read |
|---|---|---|---|---|---|---|---|---|---|---|---|
| K1 | 30 | 49152 | `9216 of 9216` | 61 | 1019 / **1055** | **5,750** | 97.57%, 1,931 MiB from RAM | 174.5 | 144.8 | 143.9 | 4,803.3 |
| K2 | 29 | 20480 | **`9413 of 9728`** | 62 | 1021 / 683 | 5,936 | — gate FAIL, no bench | | | | |
| K3 | 30 | 32768 | `9216 of 9216` | 61 | 1021 / 1139 | 5,809 | 97.41%, 1,950 MiB from RAM | 182.8 | 146.7 | **152.6** | 4,895.5 |

**Measured price of one kv step (32768 → 49152): CUDA1 −84 MiB, stage-0 expert cache −196 slots** (5,946 →
5,750). The −84 MiB is the useful correction: the old notes' `512 pairs x 2.11 MiB = 1.08 GiB` figure suggested
a step cost ~1 GiB on the last stage, which is not what this layout does — CUDA1's cache is **profile-capped**
(`9216 of its 9216 profiled pairs`), so a kv step lands almost entirely on **CUDA0**, i.e. on the resource every
other arm today has proved binding (the stage-0 expert cache).

**The deep-context "KV miss" story is locality, not residency.** Compared *within* an era, 32768 and 49152 are
the same: 97.41% vs 97.57% at 110-180K, 1,950 vs 1,931 MiB read from pinned RAM. The 96.22% and 94.06% figures
that motivated the sweep were a **cross-era pooling artifact** — that bucket mixes bench requests (fresh ~83K
read, then 171K with the prior turn reused) with this session's own turns (~190K, long reused prefix), and the
reuse pattern, not the resident-cell count, sets the hit rate. So raising `kv-resident` buys an essentially
unchanged miss rate and costs real cache slots; decode also leans the other way this round (C 152.6 at 32768 vs
143.9 at 49152). **Keep 32768** — it is also what `setup` picks for ctx ≥ 64K, and `20480` remains measured-bad
(here and in the older split-31 arm).

**K2 closes the residency question as a side result.** Lowering kv-resident to free VRAM for a 19th layer does
not work: `20480` at split 29 came out `9413 of its 9728 profiled pairs` with CUDA1 at 683 MiB — the step is
worth only ~84 MiB on that stage, against ~635 MiB needed. Split 30 (18 layers) is the wall, and the only levers
that ever moved it are **physical GiB on CUDA1** (`vision.gpu=false` bought exactly one layer: 798 → 1,139 MiB)
— not `kv-resident`, and explicitly **not** `--vram-reserve-later-mib` (the coder tree's failure-mode table bans
it as a funding source: window graphs need that room).

Method note worth keeping: the KV-hit-by-context table is a near-noise-free instrument (**within one era** the
median and worst differ by ~0.4 points across rounds) — far better than decode medians for judging KV knobs.
It is only valid in-era; across eras it measures traffic mix, not the config. Tooling:
`/tmp/gpuswap/arm3.sh <label> <split> <kv-resident>` (gate + bench + in-era KV table, `ROUNDS=2`), era marker
saved as `/tmp/gpuswap/<label>.era`. Revert point `docker.json.bak-20261030-pre-kvsweep`. Live arm after the
sweep: `[0,1]`, split 30, `--kv-resident 32768`, `--pcie-frac 0.20`, `vision.gpu=false`.

## Conversation cache: a 1024 MiB pool cannot hold one pi session — 6144 / 8192 / 16384 (2026-10-30 ~00:20-00:45, engine 0.1.54, **live**)

Trigger: the operator's report that long prompts keep prefilling from 0. The engine named the reason 12
times in one era — it wanted to park the conversation and the pool refused:

```
strata serve: conversation cache: skip parking (snapshot 2978 MiB exceeds available budget)
strata serve: prompt 143208 tokens = 0 reused + 143208 read in 29891 ms (4791.0 tok/s), 3209 generated …
```

The pool was `--conversation-cache-mib 1024` (`slots` / `min-free-mib` at engine defaults 4 / 2560), and a
snapshot on this arm costs **~20-24 KiB/token** (from `snapshot_bytes=`, not `bytes=` — see the traps below):
84,678 tok → 1.98 GiB · 89,163 → 2.04 · 100,712 → 2.21 · 171,792 → 3.22. So **one 100K-token pi session
(2.2 GiB) never fit the cache at all**: it could only ever hold 265-13,710-token fragments, while this arm's
entire traffic is one 90-140K session. The knob was not mis-tuned, it was sized below the unit of work.

Arms — every boot `9216 of its 9216 profiled pairs`, free 1019/1139 MiB, **GATE PASS**; `[0,1]/30`,
kv 32768, frac 0.20, vision CPU throughout; switched with `./tune-arm.sh cc=… ccmin=… gain=…`, which now
writes all five `--conversation-cache-*` keys in **both** carriers:

| arm (mib / min-tokens / park-gain) | reqs | budget refusals | parks (of which < 8192 tok) | pool peak | evict max | `restored (live)` |
|---|---|---|---|---|---|---|
| CC0 1024/256/512 (was live) | 99 | **12** | 19 (**17**) | 0.97 GiB / 4 slots | 13 | **0** |
| CC1 6144/256/512 | 18 | 0 | 6 (2) | 5.52 GiB / 3 slots | 3 | **0** |
| **CC2 6144/8192/16384 (live)** | 32 | 0 | 7 (**0**) | 5.20 GiB / 2 slots | 3 | **2** |

Three things this measures:

1. **`mib` is the binding knob.** At 6144 the refusals vanish and the giants park:
   `parked 172406 tokens in 1029.1 ms; bytes=5924111680 evictions=1 snapshot_bytes=3458529680`.
   Parking costs **0.45-1.05 s for 84-172K tokens = 3-5 % of the 21-30 s cold re-read it prevents.**
2. **A parked copy that survives pays ~200×:** `restored 102030 tokens (live) in 105.7 ms` →
   `prompt 102065 tokens = 102030 reused + 35 read in 617 ms`, against the same session cold earlier in the
   same era (`95358 read in 21.6 s`). Across the whole log, restores of >20K-token conversations cost 48-321 ms.
3. **min-tokens / park-gain are what make room for it.** At 256/512 the pool spent GiB *and* time on
   265-6,494-token side requests (17 of 19 parks, 110-130 ms each, `reused_kv_bytes=0` — they never paid) and
   re-parked the hot session every turn (`dropped 1 superseded copy`), so the hot copy was still the LRU
   victim: **CC1 had 0 refusals and still 0 restores.** With 8192/16384 no sub-8K park happens at all and
   re-parks go partial/cheap (`parked 102030 tokens in 81.4 ms; reused_kv_bytes=1537263`). Accepted as a pair
   — one mechanism (churn), **not separately attributed**.

And the reason this is not a decode knob: **parking only happens on displacement.** A conversation that keeps
its slot never parks — after the CC1 restart my session read `78590 = 0 reused` and parked nothing, and its
next turn reused 79,241. The coder tree's “with one hot session the cache does nothing” holds here too; what
this cache buys is the **switch** between pi sessions / subagents, and coming back after a reload.

What it costs: bench per arm — CC1 A 191.1 / B 157.3 / C 140.9 / **D 4,611.4**, CC2 A 183.2 / B 180.9 /
C 166.9 / **D 4,897.3** (keeper D control band 4,798.6-4,848.9). D is the only near-noise-free metric: it sat
4 % low at CC1 and back in band at CC2, which is what fewer parked GiB competing for the page cache predicts —
one sample each, suggestive only. RAM: min `MemAvailable` during a bench 13.1 GiB (CC1) / 13.9 GiB (CC2)
against 19.8 at idle, swap ≤ 2.3 GiB, `0 blob reads from the file` (page-locked expert tier untouched), decode
not hurt.

**Not settled: the pool still cannot hold three giants.** 6144 MiB ≈ 2.4 conversations of 100K tokens. In the
CC1/CC2 windows my 2.2 GiB copy plus the bench's 3.22 + 2.11 GiB copies went over it, LRU took mine
(`evictions=1..3`), and that turn read 95K cold. Next arm if two *real* long conversations collide: `cc=8192`
(+ `ccslots=6`, because `slots` = 4 would then bind before the pool). RAM says yes — 13.9 GiB min at a 6 GiB
pool leaves ~12 GiB at 8, above the 2560 floor. Do **not** fund it by lowering
`--conversation-cache-min-free-mib` (that floor is the safety; the parallel tree already measured what happens
when it is traded away).

Watch it with `./cc-counters.py [era …]`: per era it prints the arm's own cc flags off the boot line, request
count, cold reads ≥4K with their seconds, budget refusals, parks (with the <8192-token ones called out), pool
peak, evictions, and the `restored (live)` payoff line. Verdict rule: **five- or six-digit `restored (live)`
counts = the cache is paying; refusals > 0 = pool too small; evictions climbing in an era that also shows a
giant request with `0 reused` = pool too small for the conversations actually live.**

Method traps found doing this — read before any A/B on this knob:
- **Era bounds must come from `.tune/<label>.era`.** An unbounded `tail -n +<boot>` window makes the previous
  arm swallow the next arm's traffic; it happened mid-analysis and produced a bogus “180 big restores happened
  at mib=1024” statistic that was really my own CC2 era read backwards.
- **Pack `iq3_s` is shared** by the 1slot, parallel (and 3slots) installs, so any cross-boot statistic grouped by
  `--pack` mixes trees. Only in-era comparisons are attributable on this box.
- On a park line `bytes=` is the **pool total**, `snapshot_bytes=` is that one conversation. The KiB/token
  constant comes from `snapshot_bytes` (19.7-24.5 for 84-172K); small parks are overhead-dominated
  (3,238 tok → 0.27 GiB ≈ 90 KiB/token), which is a second reason `min-tokens` pays.

Applied (live, both carriers): `--conversation-cache-mib 6144 --conversation-cache-min-tokens 8192
--conversation-cache-park-gain 16384`; `slots` (4) and `min-free-mib` (2560) left at engine defaults — parked
peaked at 3, so `slots` never binds at capacity 1.

## Revert points

| file | restores |
|---|---|
| `strata-iq3_s.json.bak-pre-resident-kv`, `strata/launch-presets/docker.json.bak-pre-resident-kv` | the old arena config (no resident, no kv-resident) |
| `docker.json.bak-arm5-split32` | arm 5 (split 32, KV in VRAM, resident + adapt-async + ring 384) |
| `docker.json.bak-arm2-kvres32768` | arm 2 (resident + adapt-async + `--kv-resident 32768`) |
| `docker.json.bak-arm3` | arm 3 (resident + adapt-async, no kv-resident, ring default) |
| `docker.json.bak-arm4-ring0` | arm 4 (`STRATA_SPLIT_RING=0`) |
| `BENCH-1slot.md` + `bench-1slot.py` | the A/B record and how to repeat it (`python3 bench-1slot.py 2`, restart between arms) |
| `strata/launch-presets/docker.json.bak-20261029-gpusorder` | the pre-swap preset = the accepted arm (`[0, 1]` + split 31) |
| `bench-1slot.py.bak-20261029-port5802` | the bench script aimed at the old port 5801 |
| `/tmp/gpuswap/` | `armB-gpus10-split38.boot.txt`, `armB-bench.txt`, `armA1-restore-gpus01-split31.boot.txt`, `armA1-bench.txt` — full boot + bench of both arms |
| `strata-iq3_s.json.bak-20261029-vision` | `"vision": {"gpu": true}` (the split-31 baseline; needed if you go back to GPU vision) |
| `strata/launch-presets/docker.json.bak-20261029-mtparms` | the preset at split 31 with no `STRATA_MTP_STAGE0` |
| `/tmp/gpuswap/arm.sh` | the arm runner: edit → stop → reload → **boot gate** → bench, usage `arm.sh <label> <split> <mtp:on\|off> <vision:gpu\|cpu>` |
| `/tmp/gpuswap/arm2.sh` | same for `--pcie-frac`: `arm2.sh <label> <split> <frac> [vision:gpu\|cpu]`, `ROUNDS=2` for 2 bench rounds per boot |
| `strata/launch-presets/docker.json.bak-20261030-pre-kvsweep` | the preset before the kv-resident sweep (`32768`, split 30, frac 0.20) — same values as the accepted arm |
| `strata/launch-presets/docker.json.bak-20261030-pre-pcie020` | the preset with `--pcie-frac 0.00` |
| `strata-iq3_s.json.bak-20261030-syncsplit` | the run config with `--layer-split 32` (pre-sync) |
| `~/.config/strata/1slot/tune-arm.sh` | **the durable arm runner**: edit → stop → reload → boot archive → **gate** → bench → in-era KV table. `./tune-arm.sh <label> [split=N] [kv=N] [frac=X] [mtp=on|off] [vision=gpu|cpu] [cc=MIB] [ccslots=N] [ccmin=N] [gain=N] [minfree=N] [--no-bench]`, `ROUNDS=2` for two rounds; artifacts in `.tune/` |
| `~/.config/strata/1slot/cc-counters.py` | the conversation-cache instrument: per-era refusals / parks / pool peak / evictions / `restored (live)`, labelled from the boot's own argv |
| `strata/launch-presets/docker.json.bak-20261030-pre-cc6144`, `strata-iq3_s.json.bak-20261030-pre-cc6144` | the conversation cache at **1024 / 256 / 512** (arm CC0, the pre-sweep state) |
| `tune-arm.sh.bak-20261030-pre-cc` | the runner before it learned the five `cc` knobs (and before it called `cc-counters.py`) |
| `.tune/CC0-baseline.counters.txt`, `.tune/CC{1,2}.{era,boot.txt}` | baseline counters snapshot + the two arms' era line numbers and boot archives |
| `/tmp/gpuswap/{arm.sh,arm2.sh,arm3.sh}` | the throwaway predecessors (superseded by `tune-arm.sh`) |
| `/tmp/gpuswap/fractab.py` | pools per-request decode/prefill samples across eras, labelled from each boot's effective argv |
