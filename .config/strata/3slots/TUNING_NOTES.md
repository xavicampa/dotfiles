# Strata 3slots — tuning notes (qwen3.8-flash-next-iq3_s)

Box: RTX 5070 Ti (CUDA0, 15.92 GiB) + RTX 3090 Ti (CUDA1, 23.99 GiB), 62 GiB RAM.
Engine 0.1.48 linux-x86_64-cuda-cuda13. Container `qwen3.8-flash-next-iq3_s-parallel`, port 5802, preset `docker`.
Model pack `IQ3_S`; 48 layers, **512 expert pairs per layer**, CUDA1 expert-cache cost ≈ **2.11 MiB/slot**, CUDA0 ≈ 1.94 MiB/slot.

Measure with: `python3 ~/.config/strata/3slots/bench-batch-mtp.py` (solo / 2-stream / 3-stream medians,
plus the engine's own `strata batch:` window accounting).

## Current best config (2026-10-25, "leg C")

Live and durable in both `strata-iq3_s.json` and `strata/launch-presets/docker.json`:

```
--max-context 131072   --kv int8   --kv-resident 20480
--layer-split 32       --pcie-frac 0.00
--resident-experts     --adapt-async 1 --adapt-every 1 --adapt-swaps 160 --adapt-decay 0.97
--batch 3 (preset "parallel": 3)   --batch-mtp   --spec 4 --spec-min-p 0.70 --mtp rt
--vram-reserve-mib 896 --vram-reserve-later-mib 896 --trim-stage-weights
--conversation-cache-mib 8192 --conversation-cache-slots 6
--conversation-cache-park-gain 2048 --conversation-cache-min-tokens 256
```

Result: solo **137.4 / 136.6** · 2 streams **143.7 / 150.2** · 3 streams **163.2 / 167.1** tok/s.
CUDA0 expert cache 5,558 slots (10.25 GiB), CUDA1 8,192/8,192 pairs (16.52 GiB, 100 % resident).
Free VRAM: CUDA0 545 MiB, CUDA1 1,376 MiB. `MemAvailable` ≈ 13 GiB under load.

## The layer-split experiment (2026-10-25)

CUDA1 holds layers `split..47`, so its expert demand is `512 × (48 − split)` pairs:

| split | CUDA1 pairs | VRAM needed | verdict on this box |
|---|---:|---:|---|
| 32 | 8,192 | 16.52 GiB | **fits**, 100 % resident |
| 31 | 8,704 | 17.55 GiB | **does not fit** with `--batch 3` + `--batch-mtp` (room ≈ 17.4 GiB) |
| 30 | 9,216 | 18.37 GiB | far out (old single-slot runs only barely held it) |

Three legs, two bench runs each:

| | baseline<br>32 / kvres 32768 / res 1024 | leg A<br>31 / 20480 / 700 | leg C<br>32 / 20480 / 896 |
|---|---|---|---|
| solo | 137.8 / 137.4 | 133.2 / 129.9 | 137.4 / 136.6 |
| 2 streams | 149.7 / 144.0 | 143.4 / 142.6 | 143.7 / 150.2 |
| 3 streams | 156.6 / 162.6 | 156.0 / 158.7 | **163.2 / 167.1** |
| CUDA0 expert cache | 5,278 / 9.73 GiB | 5,782 / 10.65 | 5,558 / 10.25 |
| CUDA0 CPU experts / window | 3.6–5.8 ms | 2.6–4.4 ms | 2.9–4.4 ms |
| CUDA1 residency | 8192/8192 | **8633/8704 ✗** | 8192/8192 |
| CUDA1 wait + pool / window | 0.00 ms | **7.1–9.5 ms ✗** | 0.00 ms |
| ms/window @3 streams | 26.8–27.9 | 27.3–28.4 | **26.4–26.6** |
| KV streaming VRAM hits | 96.8 % | 93.4 % | 94.4 % |
| free VRAM CUDA0 / CUDA1 | 671 / 1182 MiB | 351 ⚠ / 246 ⚠ | 545 / 1376 MiB |
| engine VRAM warnings | none | 2 (`below 512 MiB`, CUDA1 `LOW`) | none |

Readings:

- **Split 31 is a net loss at `--batch 3`.** CUDA0 gains cache (+504 slots, CPU-expert time −25 %) but CUDA1
  stops being fully resident and its zero `wait + pool` term becomes 7–9.5 ms/window. Net −4 % solo, −3 % 2-stream,
  no gain at 3 streams. The engine also warns about the resulting VRAM tightness.
- **Split 32 is the cliff edge for this config.** 17 layers need 17.55 GiB; with 3 slot sessions
  (0.22 GiB each) + 3 batch-MTP drafters (50 MiB each) + CUDA1's dense weights and KV, CUDA1's room is ~17.4 GiB.
- **The CUDA0 cache gain came from the trims, not the split.** `--kv-resident 20480` shrinks each slot session's
  resident KV (`0.50 → 0.40 GiB` per slot on CUDA0, `--batch 3` total `1.50 → 1.20 GiB`) and `--vram-reserve-mib 896`
  hands back 128 MiB — that is where the +280 slots come from, and it costs nothing on CUDA1.
- Do **not** chase the CUDA0/CUDA1 utilisation asymmetry (≈55 % / 38 %). The batch window shows CUDA0's cost is
  `GPU-reach wait ~9.8 + CPU experts ~4.4 ms`, i.e. *feeding* experts, not compute — moving layers to the 3090 Ti
  does not attack that.

## Other measured decisions on this box

- **`--batch-mtp` — keep ON.** Strict A/B: without it, 2-stream 117 tok/s and 3-stream 138; with it, 137 and 148–155.
  It does *not* help solo (that regime is already covered by the shared drafter), and per-request
  `drafts accepted 0 of 0` lines are misleading — batched acceptance shows up only as
  `strata batch: MTP proposals accepted N of M`. Costs ~103 CUDA1 expert-cache slots.
- **`--adapt-async 1 --adapt-every 1` — keep** (committed report `2026-10-11-community-rtx3090-5600x-arena-async`
  measured ×1.071; here it took `adapt wait` 1.0 ms → 0.15 ms and window 24–27 ms → 18–25 ms). It requires
  the resident RAM mode (`--resident-experts`) and is incompatible with `--batch-groups` / `--pipeline-windows 2`.
  If the engine declines it, it prints `adapt-async 1 is off (<reason>): the blocking adaptive tier`.
- **`--kv int8` over `q4_0`** once `--kv-resident` pays for the VRAM (committed `2026-09-27-kv-q4`: q4_0 keeps only
  91.3 % of fp16's top-1 on a 1,024-token doc vs int8's 95.6 %, and +0.078 ± 0.011 nats/token perplexity).
- **`--pcie-frac 0.00` is correct while `--resident-experts` is on** — expert blobs come from pinned RAM
  (`file_blobs: 0`), so there is no file tier to prefetch into. Revisit (0.2–0.6) only if resident experts are removed.
- **`--batch 3` is above the break-even for concurrency.** Committed `2026-10-06-community-rtx4090-opt-ins`:
  `parallel: 2` cost 28 % of single-client decode and "only pays when a third or fourth client appears".
  Here 3 streams reach ~167 tok/s aggregate vs ~137 solo, at ~66 tok/s per stream. `--batch 2` is the next
  thing to A/B if per-stream latency matters more than aggregate.
- **Avoid** (measured negative in committed reports): `--batch-groups 2` (−15 %),
  `--pipeline-windows 2` with `STRATA_MTP_STAGE0=1` (−13 %), `--pipeline-windows 1` (−1 %).
  `--pipeline-windows 2` is off anyway with `--batch` slots.
- **Disk-persisted sessions are impossible with `--batch`/`parallel`** —
  `slot save/restore is not available with parallel requests ("parallel" / --batch)` (HTTP 501).
  Needs a separate `parallel: 1` install with `slot_save_path`; the RAM conversation cache never spills to disk.

## Guardrails

- Engine's own VRAM safety line is **512 MiB free at request start**; below it, `decode falls to a few tok/s and a
  window may never finish (#2065)`. CUDA0 currently sits at ~545 MiB. If it warns, set
  `--vram-reserve-mib 1024` and keep `--kv-resident 20480` (costs only ~66 expert slots).
- `--kv-resident` minimum is **20480**; a context ≤ N cells is not streamed.
- CUDA1's cache is **profile-capped** at split 32: it already holds all 8,192 profiled pairs, so its ~1.4 GiB of
  free VRAM cannot be spent on experts. Raising `--kv-resident` back toward 32768 spends CUDA1 VRAM but *removes*
  CUDA0 expert slots — the opposite of what leg C measured.
- Vision runs on CUDA1 (`--vision`, `strata-vision --gpu --max-tokens 512`, `CUDA_VISIBLE_DEVICES=1`); it has not
  regressed CUDA1 headroom.
- Watch `MemAvailable` (≈13 GiB under load): pinned footprint is ~26.2 GiB experts + ~1.0 GiB K/V. Levers if it
  tightens: `--conversation-cache-mib`, `STRATA_RESIDENT_HEADROOM_GIB`, context, batch slots.

## Revert points

| file | restores |
|---|---|
| `strata-iq3_s.json.bak-pre-legC` + `strata/launch-presets/docker.json.bak-pre-legC` | baseline leg (split 32 / kv-res 32768 / reserve 1024) |
| `*.bak-pre-split31` | pre-split-experiment (same as baseline leg) |
| `*.bak-pre-batch-mtp` | before `--batch-mtp` |
| `*.bak-pre-adapt-kv` | before `--adapt-async` / `--kv-resident` / `--kv int8` |
| `*.bak-int8-262k` | 262,144 ctx + int8 KV, no resident experts |

Config edits must go in **both** `strata-iq3_s.json` and `strata/launch-presets/docker.json`; the launcher
regenerates `state/strata/launch/docker.json` from the preset, so preset `extra` entries are authoritative
(boolean flags as `"--flag": "on"`). Restart is required for changes to go live.
