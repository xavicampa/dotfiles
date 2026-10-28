# Strata coder — tuning notes (qwen3.8-flash-next-coder-iq1_m-parallel)

Tree: `~/.config/strata/coder/`, forked from `parallel/` on **2026-10-28**. Model
`ISTA-DASLab/Qwen3.8-Flash-Next-GSQ-RCO-Coder-GGUF`, size **IQ1_M** (the only size that
repo offers). Preset `docker`, profile `launch-docker`, **port 5801**, engine **0.1.52-cuda13**
(`--pull newer`, so a switch can move the engine under you — every number here is 0.1.52).
Backend shape is the parallel tree's: `--batch 4`, two GPUs, exclusive GPU group.

Entry-level rationale (env vars, blob mounts, `capabilities.context`, the `/nix/store` mount) lives in
`~/.config/nixos/homepc/NOTES.md` § llama-swap/strata-coder; the RAM-wall arithmetic the parallel tree measured
is § the RAM wall in `../parallel/TUNING_NOTES.md`. The direction of travel is one-way: **tuning numbers live
here**, `configuration.nix` carries one-line pointers only (trimmed 2026-10-28, pre-trim copy kept as
`configuration.nix.pre-notes-trim`).

## Where each setting lives (read this before editing anything)

Three layers, and the middle one wins.

1. **Preset** `strata/launch-presets/docker.json` → `extra` dict. This is where the tuning
   flags normally go, and it *does* govern `--layer-split`, `--kv-resident`, `--pcie-frac`,
   `--max-context`, `--spec*`, `--adapt*`.
2. **Run config** `strata-coder-iq1_m.json` → `user_args` list. The launcher **appends this after the
   preset's `extra`**, so for any flag in both, `user_args` wins.
3. **Entrypoint env** (`-e PARALLEL`, `-e MODEL`, `-e FAMILY`, `-e PORT`, from
   `configuration.nix`): overrides the preset *and* writes it back with `--save-preset`.

**The trap, observed live on 2026-10-28:** I set the conversation-cache flags in the preset alone
(8192 / 10 / 4096) and the start logged `--conversation-cache-mib 6144 --conversation-cache-slots 6
--conversation-cache-min-tokens 256` — the stale `user_args`. The *same* preset edit did move
`--kv-resident 86016` and `--layer-split 21`, because those flags are absent from `user_args`. Rule:
**edit both layers, or strip the flag from `user_args` to make the preset the single source.**
`args` / `args_written` in the same file are an old launch's argv (they said `--kv-resident 32768`,
`--spec-min-p 0.5`); they are not re-derived at start, so stale values there are a trap for any future
flow that reads them verbatim — they were aligned to 86016 / 0.70 on 2026-10-28.
Backup of the pre-edit run config: `strata-coder-iq1_m.json.pre-conv-cache`.

Check the derived argv **without** restarting the live engine:

```bash
podman exec -i -e PYTHONPATH=/opt/strata/terminal qwen3.8-flash-next-coder-iq1_m-parallel \
  /opt/strata/terminal/python/bin/python3 -c '<derive_config probe>'   # see § parallel/TUNING_NOTES.md
```

Careful with `args.index(flag)`: that is the **flag** index, the value is `+1`. An earlier edit of mine
wrote the value over the flag name and orphaned `131072`, which would have broken the next start.

## Model shape (why coder behaves nothing like IQ3_S)

Coder is the expert-**pruned** coding build: **256 of 512** routed experts per layer survive.

- Whole expert set = `12288` ranked pairs (48 layers × 256) ≈ **23980 MiB**, slot size ~1.83 MiB.
- Shard 1 (the expert mass) is **29.6 GB** against the base model's 54.8 GB (IQ4_NL 9.2 vs 18.4 GB,
  IQ3_XXS 5.5 vs 10.9). That ~25 GB is what makes 4 × 128k fit in RAM at all (§ the RAM wall in
  `../parallel/TUNING_NOTES.md`: ~3.5 GiB per 128k slot, engine HWM 55.9 of 62.3 GiB).
- The two cards together offer ~29 GiB of expert room, so coder leaves **~5 GiB of expert capacity no
  split can fill**. That surplus is structural, not a tuning miss — do not chase it with the split.
- The run config points `--expert-profile` at `expert-profile-coder.bin` — coder is the only family in `FAMILIES`
  (`setup.py:586`) that overrides it (`"profile": "expert-profile-coder.bin"` at `setup.py:592`). The shipped
  base profile **mispredicts coder's routing**, and the whole residency picture (12288 pairs, 6912/5376 per card)
  is read off that file.
- Packs are *downloaded*, not built — the manifest entries in `setup.py` (279-292) name `pack/dense.bin`,
  `pack/index.txt`, `pack/native_experts.txt` with byte sizes and sha256. That is why IQ3_S starts without ever
  running the GPU fit ("qwen IQ3_S is already installed with these choices"), and why coder needed the `-v
  /nix/store:/nix/store:ro` mount before its own `packs/coder-iq1_m` could be prepared (§ llama-swap/strata-coder).

## Layer split

Under `--layer-split N`, CUDA0 owns layers `[0, N)` and CUDA1 `[N, 48)`, **and each card may hold only
its own layers' experts**. That is why the preset's inherited `32` was wrong: it is a fit answer for
IQ3_S, which has 512 experts per layer and can never hold everything.

At **32** (inherited): CUDA1 owned 32-47 = 4096 pairs, filled them (8.26 GiB) and sat with
`CUDA1: 7263 MiB of VRAM free with everything loaded`, while CUDA0 at 965 MiB free held **5138 of its
8192 pairs** — log `layer split: 75% of the experts resident`, decode hit rate 63.5%.

Per-layer cost of handing one layer to a card:

| term | cost |
|---|---|
| experts | 256 slots × 1.83 MiB = **469 MiB** |
| dense weights | **77 MiB** (measured: CUDA1 lost 0.83 GiB over 11 extra layers) |
| KV | `kv-resident × 1056 B` (89 MiB at 86016, 139 MiB at 131072) |
| batch slot sessions | scales with `kv-resident`, see § kv-resident — this is the dominant term |

**Split 21 is the 5070 Ti's ceiling** (as long as CUDA0 also carries 4 batch sessions): 22 layers would
need 10.3 GiB experts + 1.7 dense + 1.9 KV + 2.4 GiB sessions = **16.3 GiB in a 15.9 GiB card**.

Compute is nearly split-invariant — 0.42 ms/layer on the 5070 Ti (70 SM @2.48 GHz) vs 0.45 on the 3090
Ti (84 SM @1.91 GHz), every layer runs once, so moving a layer is worth 0.03 ms/token (~0.14%). Loading
the fast card is really **PCIe insurance**: link 26.7 vs 6.6 GB/s, a miss on CUDA1 costs **×4.07**, and
the engine reports `expert tiers: GPU 0 hits this request`, so CUDA0 is where routing concentrates.

## kv-resident — and why the split cannot be tuned without it

`--kv-resident N` keeps N cells per QSA layer in VRAM (floor 20480, which is what the parallel preset
ships). Cell cost is **1056 B/cell**, charged over each card's *own* layer count. The term people miss:
**`--batch 4` slot sessions grow with `kv-resident`** — measured 0.41 → 0.57 GiB per slot on CUDA0 and
0.57 → 0.78 on CUDA1 as kv went 49152 → 81920. Four of those per card is why the ladder below is not
linear, and why my first ceiling estimate (91.8k, cells alone) was wrong.

| split / kv-resident | free "with everything loaded" (CUDA0 / CUDA1) | residency | decode |
|---|---|---|---|
| 32 / 20480 (inherited) | 965 / 7263 MiB | 75% (5138/8192 on CUDA0) | 118.3 tok/s |
| 21 / 49152 | 1605 / 2643 | 100% | 124.8 |
| 21 / 81920 | 775 / 1483 | 100% | 145.7 (`99.06% of 9651185 block reads hit VRAM, 364.4 MiB from RAM`) |
| 20 / 98304 | 875 / **397 → LOW** | 100% | 149.3 |
| 20 / 90112 | 1085 / 687 | 100% | — (window mean, not comparable) |
| **21 / 86016 (deployed 2026-10-28)** | **675 / 1343** | 100% | 137.7-154.5 |

Reading the ladder: **demand exceeds the two cards combined**, so the split only chooses *which* card is
the tight one — 98304 at split 20 starved CUDA1 (`397 MiB … - LOW`), 21/90112 would put CUDA0 at ~440
MiB. 86016 at split 21 is the balance point: CUDA0 ~620-675 MiB (under the engine's own **700 MiB** auto
reserve, above the 512 MiB paging threshold), CUDA1 ~1.3 GiB. And 86016 still covers the longest prompt
observed here (**84789 tokens**), so nothing streams KV in practice.

**`kv-resident = max-context` (131072) does not fit at any split**: CUDA1 would need +2.3 GiB of session
state plus 28 layers × 49152 × 1056 B on top of 1483 MiB free, and CUDA0 goes short as soon as it sheds
layers (a layer moved to CUDA1 adds expert demand *and* KV demand). Best case is ~10% of each card's experts
dropped, and that trade is measured: 100% coverage = 145.7 tok/s, 63-75% = 118.3. Full KV residency would
buy the last 0.94% of KV reads and spend ~18% of decode. **The lever that pays for a bigger window is
`--parallel`, not the split** (`PARALLEL 3` frees ~1.7 GiB of session state).

**Do not accept the engine's own suggestion** `add --vram-reserve-later-mib 1071`: CUDA1's room is 14.31
GiB against 14.19 needed, so a 1.05 GiB reserve costs ~590 expert slots (~8% coverage) to buy margin that
shaving KV returns for free. `--vram-reserve-mib` / `--vram-reserve-later-mib` are deliberately **absent**
from the preset so the engine keeps its built-in 700 MiB margin.

`--max-context` stays **131072**: with `kv-resident` set explicitly, extra cells land in *pinned RAM*
(`the K/V in 0.64 GiB of pinned RAM`), not VRAM. Raising it to 196608 would cost ~7-8 GiB of the 31 GiB
available for prompts pi trims at 131072 anyway. It has to agree with three other places
(`capabilities.context` in `configuration.nix`, pi's `contextWindow`, preset `"context"`) — § llama-swap/strata-coder.

## Conversation cache (RAM, not VRAM)

`--conversation-cache-mib` is a **RAM budget** ("sized from the free RAM, up to 8192"; 0 = off).
Deployed 2026-10-28: **8192 MiB / 10 slots / min-tokens 4096**, `min-free-mib 1536` and `park-gain 2048`
unchanged.

The shipped 6144 / 6 / 256 thrashed: `parked=6 bytes=1445358032 evictions=11` with **every** park 144-965
tokens and `restores: 0` — six slots holding snapshots that save ~0.07 s of prefill each, while evicting
the 70k conversations that would save ~20 s (prefill runs at 3551-3671 tok/s here). `slots` was binding
(1.36 GiB of the 6 GiB budget), not RAM.

Sizing arithmetic: a snapshot is **~230 MiB of session overhead + ~50 KB/token**, so a 70k conversation is
~3.4 GiB and the **budget**, not the slot count, caps how many long ones fit — which is why `mib` went up
*with* `slots`. `min-tokens` is the real fix: park only what pays (4096 tokens ≈ 1.1 s of prefill).

Honest caveat, measured the same day: with one hot session the cache does nothing — `parks 0`, `restores 0`,
yet reuse was `625964 of 713525` (87.7%) from the live session path. So this is **insurance for the
multi-conversation case**, and if `restores` stays 0 over a real working day, drop `slots` back to 6 and
leave 8192 as headroom. Check:

```bash
podman exec qwen3.8-flash-next-coder-iq1_m-parallel grep -cE "conversation cache: parked" \
  /data/state/strata/launch/docker.engine.log      # compare against telemetry `restores`
```

RAM: engine `ram_used` ~31.1 GiB of 62.3, `MemAvailable` ~30.3 GiB → the worst-case 8 GiB of snapshots
lands ~41 GiB, comfortably above the `min-free-mib 1536` floor. The parallel tree's HWM of 55.9 of 62.3 GiB
is the number to respect before raising the budget further.

## Boot verification checklist (grep the engine log)

Log: `/data/state/strata/launch/docker.engine.log` (inside the container); take everything after the
last `engine started` line.

1. argv carries `--kv-resident 86016 --layer-split 21 --max-context 131072 --pcie-frac 0.20 --batch 4`
   **and** `--conversation-cache-mib 8192 … --conversation-cache-min-tokens 4096` — if those three are
   6144/6/256, `user_args` shadowed the preset (§ Where each setting lives).
2. `layer split: layers 0-20 (CUDA0), 21-47 (CUDA1)` and
   `CUDA1 runs layers 21-47, expert cache 6912 slots (13.78 GiB), 6912 of its 6912 profiled pairs`.
3. `expert cache 5376 slots, 9.64 GiB of VRAM` on CUDA0 and **`layer split: 100% of the experts resident`**.
   Metrics must read `expert_slots 12288`, `expert_slots_primary 5376`.
4. Both `N MiB of VRAM free with everything loaded` ≥ 512 — expect **~675 CUDA0 / ~1343 CUDA1**, and
   **no `- LOW`** on either card.
5. `resident RAM: 7.06 GiB of experts in RAM, 0 exchanged with the VRAM tier, 0 blob reads from the file`.
   (`since the start RAM 36600 blobs` is *not* decode missing VRAM: `the split stages lend 3739 slots to
   the prompt path … keep their experts in RAM too`.)
6. `KV streaming: 86016 of 131072 cells per QSA layer in VRAM`.
7. `arena_mib ~7226`, `ram_used ~31 GiB`, and `skip parking (N tokens, below the 4096 minimum)` for short
   side requests.

## Failure modes, in the order they will bite

| symptom in the log | meaning | lever, in order |
|---|---|---|
| `CUDA1: N MiB … - LOW: its window graphs are captured on first use and need room too, and a full card can stall a request` | that card is out of working room (window captures take ~87 MiB each, vision buffers more) | `kv-resident` −8192 cells; then `PARALLEL 4 → 3`; **not** `--vram-reserve-later-mib` |
| `WARNING: only N MiB of VRAM free … the driver can page GPU memory to system RAM, decode falls to a few tok/s and a window may never finish (#2065)` | below the paging threshold on that card | smaller `--kv-resident` or `--max-context` — **never** more experts |
| expert slots below 5376/6912, `layer split: <100% …` | KV or sessions ate expert room | step `kv-resident` down; if residency still will not close, `--layer-split auto` and read the split search's `best of N placements` line |
| `skip parking (physical RAM admission)` + flushed snapshots | RAM, not VRAM, is the wall | `--conversation-cache-slots 10 → 6`, then `-e PARALLEL 4 → 3` (needs a switch) |
| `no NVIDIA GPU found (nvidia-smi did not answer)` → `adopt` fallback, exit 5 | the image's `nvidia-smi` PT_INTERP is missing in the container | the `-v /nix/store:/nix/store:ro` mount (§ llama-swap/strata-coder) |
| `expert cache auto: X GiB free, 700 MiB reserved` shrinking below its layer count | the engine is trading coverage for KV | back off `kv-resident` to the last measured-good row in the ladder |

Do not read `tok_s_mean` as a config A/B: it is a **per-window** mean and reports `0.0` on a window with
no request in flight. Compare with a fixed prompt (the probe script) instead.

## Applying changes

`~/.config/strata/coder` is bind-mounted at `/data/install`, so preset and run-config edits are read at
**container start** — `podman restart qwen3.8-flash-next-coder-iq1_m-parallel` is enough. A `-e PARALLEL`,
`capabilities.*` or mount change needs `nixos-rebuild switch` instead (llama-swap regenerates its YAML).

Restart reloads the model, which **cuts this session mid-generation** — this box is usually serving the
agent that is doing the tuning. Restart when the current turn can afford it, and verify the checklist above
before doing more work.
