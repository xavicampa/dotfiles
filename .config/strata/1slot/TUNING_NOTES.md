# Strata 1slot — tuning notes (qwen3.8-flash-next-iq3_s)

Box: RTX 5070 Ti (CUDA0) + RTX 3090 Ti (CUDA1, 23.6 GiB), 62.3 GiB RAM, 24-core CPU (15 pool workers).
Container `qwen3.8-flash-next-iq3_s`, preset `docker`, port 5801, engine 0.1.48 linux-x86_64-cuda-cuda13.
Single slot (no `--batch`), 262,144 ctx, IQ3_S (46.8 GiB experts, 48 layers, 512 pairs/layer), PLE table 26.8 GiB.
Config lives in **two** places: `strata/launch-presets/docker.json` (preset `extra`) **and** `strata-iq3_s.json`
(the installed config, which is the base every launch is built from — see "merge order").

## Current best config (2026-10-26, arm 5) — live now

preset `extra`:

```
--resident-experts on     --adapt-async 1   --adapt-every 1   --adapt-swaps 160   --adapt-decay 0.97
--layer-split 31          --kv-resident 32768
--pcie-frac 0.00          --pipeline-windows 2
--spec 4                  --spec-min-p 0.70 --trim-stage-weights
--vram-reserve-mib 1024   --vram-reserve-later-mib 1024
--conversation-cache-mib 1024 --conversation-cache-min-tokens 256 --conversation-cache-park-gain 512
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
- `strata-iq3_s.json` still carries `--layer-split 32` and no `--kv-resident`; the preset `extra` overrides
  both at launch (live argv: `--layer-split 31 --kv-resident 32768`), but `run-iq3_s.sh` reads the installed
  config directly and would start split 32 with the KV in VRAM. Sync that file or retire the script before
  trusting the manual path.
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

## Revert points

| file | restores |
|---|---|
| `strata-iq3_s.json.bak-pre-resident-kv`, `strata/launch-presets/docker.json.bak-pre-resident-kv` | the old arena config (no resident, no kv-resident) |
| `docker.json.bak-arm5-split32` | arm 5 (split 32, KV in VRAM, resident + adapt-async + ring 384) |
| `docker.json.bak-arm2-kvres32768` | arm 2 (resident + adapt-async + `--kv-resident 32768`) |
| `docker.json.bak-arm3` | arm 3 (resident + adapt-async, no kv-resident, ring default) |
| `docker.json.bak-arm4-ring0` | arm 4 (`STRATA_SPLIT_RING=0`) |
| `BENCH-1slot.md` + `bench-1slot.py` | the A/B record and how to repeat it (`python3 bench-1slot.py 2`, restart between arms) |
