# Strata coder — tuning notes (qwen3.8-flash-next-coder-iq1_m-parallel)

Tree: `~/.config/strata/coder/`, forked from `parallel/` on **2026-10-28**. Model
`ISTA-DASLab/Qwen3.8-Flash-Next-GSQ-RCO-Coder-GGUF`, size **IQ1_M** (the only size that
repo offers). Preset `docker`, profile `launch-docker`, **port 5801**, engine **0.1.52-cuda13**
(`--pull newer`, so a switch can move the engine under you — every number here is 0.1.52).
Backend shape is the parallel tree's: two GPUs, exclusive GPU group. As tuned on **2026-10-28**: `--batch 3`
(`-e PARALLEL 3` in `configuration.nix`), `--kv int8`, `--kv-resident 86016`, conversation-cache budget 12 GiB (§
Applied below). The last two are restart-only; `--batch` needs a `nixos-rebuild switch`. (`--kv-resident` spent 2026-10-28
at 86016 -> 131072 -> 114688 and came back to **86016** on 2026-10-29 after § Decode throughput measured the bump as a
~10% decode cost that bought no hit rate.)

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
unchanged. Superseded by § Re-tuned 2026-10-28 ~18:10 below — read that first.

The shipped 6144 / 6 / 256 thrashed: `parked=6 bytes=1445358032 evictions=11` with **every** park 144-965
tokens and `restores: 0` — six slots holding snapshots that save ~0.07 s of prefill each, while evicting
the 70k conversations that would save ~20 s (prefill runs at 3551-3671 tok/s here). `slots` was binding
(1.36 GiB of the 6 GiB budget), not RAM.

Sizing arithmetic: a snapshot is **~230 MiB of session overhead + ~50 KB/token**, so a 70k conversation is
~3.4 GiB and the **budget**, not the slot count, caps how many long ones fit — which is why `mib` went up
*with* `slots`. `min-tokens` is the real fix: park only what pays (4096 tokens ≈ 1.1 s of prefill).

**Correction measured under load later the same day:** an 80k park cost `snapshot_bytes=1633553800` — **~20
KiB/token**, not 50 — so a 83k conversation is **1.6 GiB** and the 8 GiB budget holds only ~5 of them, which is
exactly why the eviction showed up once four slots went hot (§ Re-tuned 2026-10-28 ~18:10).

### Re-tuned 2026-10-28 ~18:10 — the budget binds, not RAM and not slots

Measured on the **live agent load** (engine start 16:51:53, `--batch 4`, ~1 h of real pi traffic):

| signal | value |
|---|---|
| parks / restores / evictions | **56 / 3 / 16** |
| parked slots | 6 of 10 — `slots` never binds |
| bytes | **7.4 GiB of the 8192 MiB budget** (92%) |
| `skip parking (physical RAM admission)` | **none** (the only skip is `53 tokens, below the 4096 minimum`) |
| RAM | `MemAvailable` 22.3 GiB, engine `ram_used` 40.3 of 62.3 GiB |

So eviction is **`mib`-budget-driven**, not the physical-RAM failure mode in § Failure modes. Mechanism:
**29 of the 56 parks are `dropped 1 superseded copy of this conversation`** — pi resends the whole conversation
each turn, so `park-gain 2048` re-parks on almost every turn; the new copy is counted while the superseded one is
still resident, so **the re-park itself** blows the cap and LRU evicts the *other* parked conversations — the
70-84k ones that would save ~45 s each at 1.8k tok/s prefill.

Deployed now, **both layers** (`docker.json` → `extra` **and** `strata-coder-iq1_m.json` → `user_args`, with
`args` / `args_written` kept honest; backups `*.bak-pre-cache-tune`):

| flag | old | new | why |
|---|---|---|---|
| `--conversation-cache-mib` | 8192 | **12288** | engine help says `up to 8192` only for the auto default sized from free RAM — not a clamp; an explicit value is honoured |
| `--conversation-cache-min-tokens` | 4096 | **16384** | side requests of 6.8k-21.2k tokens parked 0.15-0.5 GiB each to save 4-12 s; the 80k ones they evicted save ~45 s |
| `--conversation-cache-park-gain` | 2048 | **12288** | kills the superseded churn, and removes ~230 ms of copying per turn (48 parks cost 10.9 s in the window) |
| `--conversation-cache-slots` | 10 | 10 | unchanged — parked 6 of 10, never binding |
| `--conversation-cache-min-free-mib` | 1536 | 1536 | unchanged |

RAM headroom for +4 GiB of budget: peak ≈ budget + one in-flight 1.6 GiB re-park double, which leaves ~18 GiB
available — far above the `min-free-mib 1536` floor. `--cgroup-conf memory.swap.max=0` means an overrun **stalls
rather than swaps** (host swap already 1.5 GiB used); the 55.9 of 62.3 GiB HWM in `../parallel/TUNING_NOTES.md`
§ the RAM wall is IQ3_S mass — coder carries ~25 GB less.

Expected after restart, same window: `superseded` ~0-2, parks ≈ restores, `evictions` near 0. **If `restores`
stays ≤3 over a full working day, set `--conversation-cache-mib 0`** — the 91.7% reuse measured here comes from
the live slot path (`slot 0 gave back 54155 tokens … copied in 202 ms`), not from the cache.

Separate signal seen the same day, **not** fixable by this cache: `KV streaming: 30-87% of N block reads hit VRAM`
in the decode windows — see § KV streaming under 4-slot load (my first reading of it, comparing those percentages
against the 99% at 21/86016, was wrong: different window sizes).

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

## KV streaming under 4-slot load (2026-10-28 ~18:20, live `--batch 4`)

What the flag actually does (engine help): `--kv-resident N` keeps N cells of **each QSA layer** in VRAM **and the
whole K/V in pinned RAM** — boot says `KV streaming: 86016 of 131072 cells per QSA layer in VRAM, the K/V in
0.64 GiB of pinned RAM` — and "the freed VRAM goes to expert slots". So a miss in `KV streaming: N% of M block reads
hit VRAM, X MiB read from RAM` is a **pinned-RAM read of bytes the engine already owns**, not a file read and not a
paging fault. That is a tiering choice, not a failure.

The percentages are **per reporting window and not comparable across window sizes** — same trap as `tok_s_mean`
(§ Do not read `tok_s_mean` as a config A/B). Bucketed over this run:

| window size (block reads) | hit% | miss bytes |
|---|---|---|
| 2.6k-12.8k (decode windows) | **0-75%** (mean 33.6% at 2 rows, 61.7% at 5) | **10-20 MiB/window** |
| 300k-3M (prefill / long decode) | 83-99.8% | 60-400 MiB, amortised over tens of seconds |
| 9.65M (the § kv-resident ladder datapoint) | 99.06% | 364 MiB |

Cost check under the real load: per-request decode is **110.7-137.5 tok/s** (`2696 generated in 24198 ms (111.4
…`, `394 in 2866 ms (137.5 …`) against 137.7-154.5 for one hot session — so the misses cost ~10-20% of per-request
decode, and `strata batch: avg 3.4 rows` buys that back several times in aggregate. The dominant term in each window
is `run 25.7-27.5 (CUDA0 GPU-reach wait 10.3-12.0 ms)`, not the 10-20 MiB from RAM.

And the 4 sessions do **not** starve the experts, despite taking VRAM from them: boot says `--batch 4: the slot
sessions take 2.37 GiB of VRAM on CUDA0 that the expert cache would otherwise hold` (0.59 GiB each on CUDA0, 0.81
on CUDA1), the expert cache therefore lands at **5356 slots (9.60 GiB)** — 20 short of the 5376 that 21 layers
want — and `-e STRATA_SPLIT_RING=384` closes it: `layer split: 100% of the experts resident, the prompt path's
streamed ring 384 slots`. So metrics reading `expert_slots_primary 5356 / expert_slots 12268` instead of the
5376 / 12288 in § Model shape is **expected**, not a regression. Keep `--split-ring` ≥ the 20-pair gap; do not
read it as a miss.

What to watch instead: `per layer-window: CPU experts X ms` and `routed entries per window: VRAM … %` in the
`strata batch:` line. The one sample at `avg 2.01 rows` read `CPU experts 3.62 … VRAM 14.74 … PCIe 0.31` with
`VRAM 75.6% / CPU 22.8%` — 22.8% of routing on CPU experts in a prefill-heavy stretch (it followed a cold 31370
prompt). Expert tier, not KV, is what degrades first.

Levers, cheapest first:

| lever | what it does | cost |
|---|---|---|
| `-e PARALLEL 4 → 3` | frees 0.59 GiB (CUDA0) / 0.81 (CUDA1) of session state; § kv-resident already calls `--parallel` "the lever that pays for a bigger window" | needs `nixos-rebuild switch`; gives up ~1 row of throughput |
| `--kv k8v4` | 816 B/cell vs int8's 1056 → 23% smaller KV, and it "streams with `--kv-resident` too": ~0.13 GiB per session, ~0.5 GiB per card back to expert slots | keeps INT8 K (exact scores), rotates V to Q4_0; preset + `user_args` + `args` (`--kv int8` is in `args`), restart-only |
| `--kv q4_0` | halves KV again | 4-bit after a Hadamard rotation on a model already at IQ1_M weights — not worth the quality risk here |
| raise `--kv-resident` | buys the last ~40% of decode-window KV reads | **do not**: 90112 puts CUDA0 at ~440 MiB per § kv-resident, under the 700 MiB auto-reserve and near the 512 MiB paging cliff (#2065), to save 10-20 MiB/window |
| `--kv-grow` | exists, but the help scopes it to one GPU with `--expert-profile` | not applicable at `--layer-split 21` |

```bash
# bucket the KV series by window size before quoting a percentage (host side)
podman exec qwen3.8-flash-next-coder-iq1_m-parallel sh -c \
  'sed -n "111456,\$p" /data/state/strata/launch/docker.engine.log' | grep -oE "KV streaming: [0-9.]+% of [0-9]+" \
  | awk "{print int(\$5/2565)}" | sort -n | uniq -c
```

## Applied: 3 slots + `--kv k8v4` (2026-10-28 ~18:30)

Both changes feed the same scarce resource — CUDA0 VRAM — and both follow from the measurement above: the KV **tier**
is cheap to feed (10-20 MiB/window from pinned RAM), the *expert* tier is what degrades first.

| layer | edit |
|---|---|
| `strata/launch-presets/docker.json` | `"kv": "int8" → "k8v4"`, `"parallel": 4 → 3`, and `extra["--kv"] = "k8v4"` so the preset-derived argv carries it too |
| `strata-coder-iq1_m.json` | `args` and `args_written`: `--kv int8 → k8v4` (that pair came from the preset's `kv` **field**, not from `extra`), and `--kv k8v4` prepended to `user_args` — the layer that wins |
| `~/.config/nixos/homepc/configuration.nix` | coder entry `-e PARALLEL=4 → 3`. The parallel tree's `-e PARALLEL=4` above it is untouched |

Backups: `strata-coder-iq1_m.json.bak-pre-kv3`, `strata/launch-presets/docker.json.bak-pre-kv3`,
`configuration.nix.bak-pre-kv3`.

Why 3 slots: slot sessions are pure overhead per row — 0.59 GiB each on CUDA0, 0.81 on CUDA1 — and
`strata batch: avg 3.4 rows` was the observed ceiling, so the 4th row bought ~0 throughput and ~0.6 GiB of CUDA0
room. § Parallel tree and llama-swap's "`--parallel` only pays for a bigger window" still holds (it is why 21/81920
was chosen); 3 is the point where it pays.

int8 → k8v4 is 816/1056 = **0.773** on every KV term, so recompute rather than reusing the ladder's numbers:

| term | before | expected after |
|---|---|---|
| KV term in the split search, per card-layer at 86016 | 89 MiB (§ kv-resident) | **69 MiB** |
| slot sessions | 4 × 0.59 = 2.37 GiB on CUDA0 | 3 × ~0.46 = **~1.37 GiB** |
| expert cache on CUDA0 | 5356 slots / 9.60 GiB — 20 short of the 5376 the split wants, closed only by `STRATA_SPLIT_RING=384` | **5376 slots / 9.64 GiB**, ~1.0 GiB of freed room left over |
| metrics | `expert_slots 12268`, `expert_slots_primary 5356` | **12288 / 5376** — § Model shape's numbers, so "the other half sits in RAM (7148 of it)" becomes 7168 |
| CUDA0 free under load | 711 MiB | **1681 MiB measured** (`strata serve: 1681 MiB of VRAM free with everything loaded`) |

### Measured boot at 3 slots + k8v4 (2026-10-28 ~17:30) — every prediction above confirmed

```
KV streaming: 86016 of 131072 cells per QSA layer in VRAM, the K/V in 0.50 GiB of pinned RAM   (was 0.64)
--batch: 3 slot sessions on CUDA0 (0.50 GiB each); 11.60 GiB free          (was 4 × 0.59, 10.62)
--batch: 3 slot sessions on CUDA1 (0.67 GiB each); 17.97 GiB free
--batch 3: the slot sessions take 1.49 GiB of VRAM on CUDA0                (was 2.37)
expert cache 5376 slots, 9.64 GiB of VRAM; layer split: 100% of the experts resident, the prompt path's streamed ring 384 slots
serve: 1681 MiB of VRAM free (CUDA0) / CUDA1: 2777 MiB
metrics: expert_slots 12288, expert_slots_primary 5376, kv k8v4, batch_slots 3, arena_mib 7166
resident RAM mode: 7.00 GiB of experts in RAM (was 7.06), 5376 in the GPU cache
```

Decode came back *better* than the 4-slot snapshot: per-request 141.5 tok/s (`decode_tok_s` in metrics, was
110.7-137.5) and `drafts accepted 292 of 334` (87%). The 4th row was not buying throughput — § Parallel tree and
llama-swap's "`--parallel` only pays for a bigger window" is now measured both ways on this box.

### How much `--kv-resident` can be raised (measured 2026-10-28 ~17:35)

The cost is knowable exactly, because the pack says which layers stream. `packs/coder-iq1_m/index.txt` gives **12
full-attention (QSA) layers** at `blk.3, 7, 11, 15, 19` and `23, 27, 31, 35, 39, 43, 47` (the other 36 layers carry
fused `attn_qkv` and are not streamed). With `--layer-split 21` that is **5 QSA layers on CUDA0 and 7 on CUDA1**, so
raising `--kv-resident` by Δcells costs, per session:

```
CUDA0:  Δcells × 816 B × 5  =  Δcells × 4,080 B
CUDA1:  Δcells × 816 B × 7  =  Δcells × 5,712 B
```

Multiply by **`--batch + 1`**, not `--batch`: the solo/verify session keeps its own resident window too, and the
A/B below proves it (CUDA0 lost 676 MiB at full residency, which is 4 × 174 MiB, not 3 ×).

| `--kv-resident` | Δcells | CUDA0 free | CUDA1 free | CUDA0 above the 1 GiB `--vram-reserve-mib` |
|---|---|---|---|---|
| 86016 | 0 | 1681 | 2777 | 657 MiB |
| 98304 | 12288 | 1490 | 2509 | 466 MiB |
| **114688** | 28672 | **1235** | 2152 | 211 MiB |
| 131072 (full residency) | 45056 | **980 (measured 1005)** | 1795 (measured 1821) | **−19 MiB** |

So **full residency fits** — nothing about the expert cache is at risk, because at 3 slots the cache sits at its cap
(`5376 slots` = 21 × 256, metrics `expert_slots 12288 / expert_slots_primary 5376`) and the extra VRAM simply stays
free. RAM does not move either: the whole K/V lives in pinned RAM at every `--kv-resident` value, so the 0.50 GiB
tail is already paid for.

The honest reason to be conservative is not throughput, it is what else wants CUDA0 room later — the ~87 MiB per
window capture, vision buffers, and the paging cliff (#2065). Full residency leaves CUDA0 with only **131 MiB above**
the 1 GiB reserve; the engine's own `--vram-reserve-mib 1024` is inside the 1681 figure, so read the reserve, not
the raw number, when the next feature loads.

And the gain is small on purpose: the long windows already read **99.10% of 6,369,970** and **99.46% of 11,540,960**
block reads from VRAM (231.5 / 252.1 MiB from RAM). Going to full residency buys those last ~0.5-0.9%, i.e. ~250 MiB
of pinned-RAM reads per long window — the same order as one window capture.

Rule for the next step: pick the largest row whose **CUDA0 above-reserve column stays ≥ ~300 MiB**, boot it, then
confirm the two `N MiB of VRAM free with everything loaded` lines and `- LOW` absence before stepping again.

### Applied: `--kv-resident 131072` — full residency (2026-10-28 ~17:40)

Chose the top of that ladder anyway. The reasoning that holds: at 3 slots the expert cache is pinned at its cap
(`5376 slots` = 21 × 256), so KV growth eats only the free pool and cannot cannibalize experts; RAM is unchanged because
the whole K/V sits in pinned RAM at every value of `--kv-resident`.

| layer | edit |
|---|---|
| `strata/launch-presets/docker.json` | `extra["--kv-resident"]: "86016" → "131072"` — the preset *is* the governing layer here: the flag is **absent from `user_args`**, unlike `--kv` (§ Where each setting lives) |
| `strata-coder-iq1_m.json` | `args` / `args_written` set to 131072 as well (cosmetic — a past launch's argv, not re-derived at start), and `--kv-resident 131072` prepended to `user_args` so the winning layer can never silently fall back |

Backups: `strata-coder-iq1_m.json.bak-pre-fullkv`, `strata/launch-presets/docker.json.bak-pre-fullkv`. Restart-only
(`podman restart qwen3.8-flash-next-coder-iq1_m-parallel`) — nothing in `configuration.nix` involved.

Expected boot, from the arithmetic above:

```
--batch: 3 slot sessions on CUDA0 (0.67 GiB each); 10.93 GiB free     (was 0.50 each, 11.60)
serve: 1005 MiB of VRAM free (CUDA0) / CUDA1: 1821 MiB                (was 1681 / 2777)
metrics: kv_resident 0  <-- the engine reports 0 when --kv-resident >= --max-context
         arena_mib 6963 (was 7166), expert_slots 12288 / primary 5376 unchanged
hardware: gpu mem_used 16.09 GiB of 17.09 (CUDA0), 23.93 of 25.76 (CUDA1)
          ram_used 24.06 GiB of 62.3, page-locked complement 6.80 GiB (was 7.00), MemAvailable 39 GiB
no `- LOW`, no WARNING, no paging warning
```

It works, and decode improved slightly: cold 86,434-token prompt at **144.7 tok/s** (141.5 at 86016), aggregate
`tok_s` 123.8, `drafts accepted 1625 of 2046` (79%), prefill 1378.5 tok/s. `arena_mib` giving 203 MiB back is not an
extra budget item — the arena is carved out of remaining free VRAM, so it simply shrinks as KV takes room.

**No `KV streaming:` line is expected at all** — the help says "a context of N cells or fewer is not streamed", and
N == `--max-context`. Treat that as a checklist change, not a regression: confirm `kv_resident: 131072` in `/metrics`,
then judge the result on `decode_tok_s` (141.5 at 86016) and on `- LOW` staying absent.

This is the thin end of the budget, and **by more than my arithmetic predicted**: CUDA0 sits at 1005 MiB free, which
is **19 MiB *below*** the `--vram-reserve-mib 1024` figure — effectively zero above-reserve room, and **493 MiB** above
the 512 MiB paging threshold (#2065). That passes the ≥512 checklist gate but breaks the "stay ≥300 MiB above the
reserve" rule in the table above, so treat full residency as a *deliberate* exception justified only by the expert cache
being pinned at its 5376 cap. Fallback if vision, another GPU-using process, or `- LOW` ever bites CUDA0: **114688**
(measured-rule cost +261 MiB on CUDA0 → ~1266 free, +256 on CUDA1 → ~2077), worth only ~0.5% of block reads.


Two traps that still apply:

1. **Full residency is a k8v4-only luxury: 131072 fits at `--kv k8v4` (1005 MiB free) and does not fit at `--kv int8`**
   (405 MiB, below the 512 MiB paging threshold). It was safe with k8v4 *only because* the expert cache is at its cap at
   3 slots, so KV eats free VRAM and nothing else. The ~300 MiB above-reserve gate in § How much `--kv-resident` can be
   raised is what to hold if anything else ever wants CUDA0 room — vision, `--batch` going back up, or another entry
   landing on these GPUs. Use the § Applied (int8) arithmetic for any future step: **Δcells x 5,280 B (CUDA0) / x 7,392 B
   (CUDA1), times `( --batch + 1 )`**. The k8v4 multipliers (4,080 / 5,712) stay in the log above because that boot is
   the headroom measurement they came from.
2. **k8v4 was a quality trade never measured on this box — that is exactly why the live config is int8 again.** Nearest
   datapoint, parallel § Other measured decisions: `q4_0` keeps only 91.3% of fp16's top-1 on a 1,024-token doc vs int8's
   95.6%, at +0.078 +/- 0.011 nats/token. k8v4 keeps **INT8 K** (exact attention scores) and rotates V to Q4_0 — less
   exposure than q4_0, not zero, and the weights are already IQ1_M. If VRAM ever gets tight (CUDA1 `- LOW`, another entry
   landing on these cards), `int8 -> k8v4` is the cheapest way to buy 600 MiB back on CUDA0: one edit per layer plus a
   container restart, no `nixos-rebuild switch`.

Because `--kv` lives in `user_args` **and** `-e PARALLEL` lives in the container config, the two halves of this change
are independent: reverting only the KV tier is a restart, changing slot count is a `nixos-rebuild switch`.

### Applied: `--kv int8` + `--kv-resident 114688` (2026-10-28 ~17:55) — exact V, paid in residency

Motivation is trap #2 above: the k8v4 V=Q4_0 exposure had never been measured here, and the weights are already IQ1_M,
so stacking an unmeasured V quantization on them was the risk I would revert first. The question was whether int8's
+29.4% of KV bytes fits, and whether **lowering `--vram-reserve-mib` could pay for it. It cannot.**

Measured CUDA0 pool above KV = 1005 + 4 x 510 MiB = **3045 MiB**; CUDA1 = 1821 + 4 x 714 MiB = **4677 MiB**. With
int8's per-cell-per-card cost (5280 B on CUDA0, 7392 B on CUDA1) and the `( --batch + 1 )` rule from § How much:

| `--kv-resident` R, int8 | CUDA0 free | CUDA1 free | verdict |
|---|---|---|---|
| 131072 | **405** | 981 | CUDA0 **107 MiB below** the 512 MiB paging threshold — reject |
| **114688** | **737** | **1443** | applied: 225 MiB above the cliff, 12.5% of the context streamed |
| 98304 | 1067 | 1733 | step-back if anything else wants CUDA0 room |
| 86016 | 1312 | 2251 | int8 with the old margin; 34% streamed |

**Why the reserve is not the lever.** It is honoured only for the *expert-cache step*, and that step is not what eats
CUDA0: `expert cache auto: 10.93 GiB free, 1024 MiB reserved -> 4003 slots` then the cache takes its **5376-pair cap
(9.64 GiB)** and leaves 1321 MiB — the last 316 MiB went to post-load window captures (~87 MiB each) and drafter buffers.
The free pool is therefore already unallocated, and at 3 slots the expert cache cannot grow into it. Dropping the reserve
to let int8 live at 131072 needs reserve <= ~700 MiB (10.34 - 9.64 GiB) and would leave CUDA0 at **~390 MiB**: paying in
the guard to land inside #2065's paging zone. `--vram-reserve-later-mib` is the guard for exactly those post-load consumers,
so cutting it is what actually removes the 316 MiB. `--vram-elastic` (`vram_elastic: 0`) releases VRAM only **between**
requests, so it cannot lower the decode-time peak either — it is the lever for a *co-resident program*, not for KV.

| layer | edit |
|---|---|
| `strata/launch-presets/docker.json` | `kv: "k8v4" -> "int8"`, `extra["--kv"]: k8v4 -> int8`, `extra["--kv-resident"]: 131072 -> 114688` |
| `strata-coder-iq1_m.json` | `user_args`, `args`, `args_written`: `--kv int8`, `--kv-resident 114688` (all layers agree) |

Backups: `strata-coder-iq1_m.json.bak-pre-int8kv`, `strata/launch-presets/docker.json.bak-pre-int8kv`. Restart-only
(`--kv` and `--kv-resident` are both engine flags here; `-e PARALLEL 3` from `configuration.nix` is unchanged).

Cost actually paid: the streamed tail is 16384 cells = **12.5% of `--max-context`**. Measured elasticity is ~2.2% of
decode for 34% streamed (141.5 tok/s at 86016 vs 144.7 at 131072) -> linear, so **~0.8% of decode, about 1.2 tok/s of 145.**
RAM rises but is nowhere near binding: the whole K/V sits in pinned RAM at every R, int8 = 1.55 GiB per session ->
4 units = 6.19 GiB (k8v4 was 4.78 GiB), i.e. +1.4 GiB against `MemAvailable` 39 GiB.

Expected boot: `--batch: 3 slot sessions on CUDA0 (0.73 GiB each); 10.64 GiB free` and CUDA1 `(1.00 GiB each)`; free
**~711 / ~1415 MiB**; `kv_resident 114688` in `/metrics` (non-zero again, since R < `--max-context`) and `KV streaming:`
lines **come back**. The session-size arithmetic: CUDA0 KV per session = 114688 x 1056 x 5 = 577 MiB plus ~0.17 GiB of
non-KV state = 0.73 GiB; CUDA1 = 114688 x 1056 x 7 = 808 MiB plus ~0.21 GiB = 1.00 GiB. (My first pass said 0.82 / 1.11
by applying int8's cost to the *full* 131072 context instead of the 114688 resident window — the same mistake the ladder
makes, and it also inflated the free prediction by ~26 MiB.)

### Measured boot at `--kv int8` + `--kv-resident 114688` (2026-10-28 ~18:05) — clean, with one checklist deviation

```
KV streaming: 114688 of 131072 cells per QSA layer in VRAM, the K/V in 0.64 GiB of pinned RAM
--batch: 3 slot sessions on CUDA0 (0.73 GiB each); 10.64 GiB free          (0.67 / 10.93 at k8v4+131072)
--batch: 3 slot sessions on CUDA1 (1.00 GiB each); 16.64 GiB free          (0.91 / 16.06)
--batch 3: the slot sessions take 2.20 GiB of VRAM on CUDA0 that the expert cache would otherwise hold
expert cache 5372 slots, 9.63 GiB of VRAM          <-- 4 SHORT of 5376 (auto estimated 3884 slots)
layer split: CUDA1 runs layers 21-47, expert cache 6912 slots (13.78 GiB), 6912 of its 6912 profiled pairs
serve: 711 MiB of VRAM free (CUDA0) / CUDA1: 1415 MiB                      (predicted 737 / 1443)
serve: 100% of the experts resident, the prompt path's streamed ring 384 slots
no `- LOW`, no WARNING, no paging warning
metrics: kv int8, kv_resident 114688, expert_slots 12284 / primary 5372, arena_mib 7232, vram_free_mib 711
traffic: decode_tok_s 128.8 on a 64,216-token prompt (63,505 reused), aggregate tok_s 127.6,
         drafts 798 of 1013 (78.8%)
KV streaming hit rates: 95.3% of 834435, 97.3% of 1979535, 98.6% of 5.0M, 99.1% of 7.8M, 99.4% of 13.5M reads
```

Three things the numbers corrected:

1. **CUDA0 has 199 MiB above the paging threshold, not 225.** The `( --batch + 1 )` formula over-predicts by ~26 MiB on
   each card (shared buffers already counted once), so treat it as +/- 30 MiB and gate on the *measured* number.
2. **The expert cache lands at 5372, not 5376, at 114688.** Metrics read `expert_slots 12284 / expert_slots_primary
   5372`, the `100% of the experts resident` line still prints, CUDA1 is full (6912/6912), and the ring is 384 slots, so
   4 short is noise — compare the 4-slot era's 12268 / 5356 (20 short, also covered). The `expert cache auto -> N slots`
   estimate is a search intermediate and has never matched the final count (3884 / 4003 / 4270 across the three boots).
3. **Streaming's real cost is reads ~1%, not 12.5%.** 12.5% of the *cells* are streamed, but reads concentrate on recent
   cells, so misses run 0.6-4.7% of block reads. The residency step-back for int8 is nearly free on throughput.

The RAM side, which is the term full residency hides: with streaming on, the **whole** K/V of every unit also lives in
pinned RAM (help: "keep N cells ... in VRAM and the whole K/V in pinned RAM") — `--max-context` x 1056 B x 12 QSA layers
= **1.55 GiB per unit, 6.2 GiB across 4 units** at int8. Measured: `ram_used 31.76 GiB of 62.26`, host `MemAvailable`
**18.5 GiB** — versus 24.06 GiB / 39 GiB available at full residency, where the pinned K/V tier is not allocated at all.
The log's "the K/V in 0.64 GiB of pinned RAM" is that stage's 5 QSA layers only (x 12/5 = 1.55 GiB per unit), so do not
size RAM from that line. Still nowhere near the wall: parking needs `--conversation-cache-min-free-mib 1536` plus ~1.6
GiB for an 80k-conversation snapshot, i.e. ~11x more headroom than required — but if `-e PARALLEL` goes back up, this is
the term that moves (one more unit = +1.55 GiB RAM **and** +600 MiB CUDA0 VRAM).


## The queue 429 — `the inference queue wait deadline expired; retry later` (2026-10-28 ~23:45)

**The listener on 5801 is not the engine.** It is the terminal wrapper:

```
LISTEN 0.0.0.0:5801  users:("python3")   python3 -m serve.server --engine strata \
    --config /data/state/strata/launch/docker.json --port 5801 --parallel 3 --shutdown-timeout 30.0
```

The engine is its child, so **some errors are the wrapper's, not the engine's** — grep `serve/server.py`
(`/opt/strata/terminal` inside the container) instead of the engine log for these. Line 1730 reads
`raise QueueWaitExpired("the inference queue wait deadline expired; retry later")`, and the package's own
test name tells you the status code: `test_queue_timeout_serial_fifo_returns_429_and_recovers`.

**The knobs are run-config JSON keys, not argv.** `strata-coder-iq1_m.json` holds

```json
"max_queue": 3, "queue_timeout": 90,      ->  --max-queue 3 --queue-timeout 90
```

Validator (server.py:8785/8787): `queue_timeout` must be finite in **0.1..600** and
`--queue-timeout requires --max-queue` — set both or neither. **Restart-only**, no `nixos-rebuild switch`.
The wrapper's `--parallel 3` is handed the same number as `-e PARALLEL` (it appeared beside `--batch 3` in
that cmdline), so the queue width and the engine's slot count are the same lever seen from two sides.

**Capacity arithmetic.** N slots + `max_queue` waiters, and a waiter dies at `queue_timeout`. The window
where it fired: slots holding `45932 / 54940 / 46230` tokens, request durations `7.2 / 13.8 / 30.0` s —
so a 4th client sits roughly three generations deep, which is 90 s. pi's session log confirms the failed
call burned exactly the deadline: `durationMs 90030`, `errorMessage "the inference queue wait deadline..."`.
Nothing is broken: capacity is 3 + 3 and the workload touched it.

**Decision 2026-10-28: leave it, monitor.** The error is a capacity signal, not damage. The two ways to
buy a 4th slot are both expensive, and the arithmetic says so (KV units = `--batch + 1`, so 4 slots means
**5** units of KV):

| `-e PARALLEL` | KV units | `--kv-resident` | CUDA0 free MiB | verdict |
|---|---|---|---|---|
| 3 | 4 | 114688 | **711** (measured) | live config |
| 4 | 5 | 114688 | **~302** | ✗ — 210 MiB under the 512 paging cliff (#2065) |
| 4 | 5 | 98304 | **~714** | ✓ — costs +1.55 GiB RAM and a switch |

Non-KV CUDA0 baseline at 5 units is ~3189 MiB (measured pool 3019 MiB at 4 units + ~170 MiB of session
state per extra unit); treat the free figures as ±30 MiB. RAM: whole-K/V pinned is `(batch+1) x 1.55 GiB`,
so 4 slots = 7.75 GiB instead of 6.2.

The cheaper lever is `queue_timeout 90 -> 180` (restart-only, `max_queue` must stay set) — pi then waits
instead of taking a 429. Not applied: the user chose to monitor.

**How often it actually happens (measured 2026-10-28 23:55): once in 7.5 h.** pi's session records hold
exactly one real error record (`2026-10-28T21:34:41Z` UTC = 22:34 local, `durationMs 90030`) — the other 25
mentions of the phrase in the session files are my own prose. llama-swap's journal for the same window reads
**6918 x 200, 21 x 404, zero 429**, and **zero** chat/completions calls longer than 60 s. So the access log
*undercounts* this event: the SSE headers go out before the wrapper gives up, so the abort never appears as a
status line. Do not conclude "no problem" from the journal — count it in pi's session files instead.

### The act-on-it ladder (each row is one edit + the restart class)

| monitor warning | do | cost |
|---|---|---|
| `queued > 0` a few times a day | `queue_timeout 90 -> 180` in `strata-coder-iq1_m.json` (`max_queue` must stay set) | restart-only, no VRAM/RAM change |
| `log ram-skip > 0` | `--conversation-cache-mib 12288 -> 8192` (both layers) | restart-only; loses ~4 GiB of parked tier |
| `vram < 512` | `--kv-resident 86016 -> 65536` (both layers) | restart-only; buys CUDA0 room and, per § Decode throughput, usually *raises* ms/fed efficiency |
| queue pressure chronic | `-e PARALLEL 3 -> 4` **and** `--kv-resident 98304` together | `nixos-rebuild switch`, +1.55 GiB RAM, CUDA0 lands ~714 MiB |

**Not recommended, measured:** raising the cache's holding capacity — the PAIR and its 389-park/66-restore
rationale are in § Parked-conversation counters. If evictions ever DO start costing, go the other way: the offenders
are the big snapshots (`parked 97497 tokens in 238.3 ms; snapshot_bytes=1726669456` = 1.65 GiB per park), so cut
`--conversation-cache-mib` and let the LRU keep the small ones, rather than buying more budget.

## Parked-conversation counters — what "14 parked, 2 evicted" actually meant

`parks` counts park **events**; `parked` counts what is held. Both samples below are cumulative **per
boot**, so never compare across boots:

```
23:45  parks 46   parked 9   restores 17   evictions 4    bytes 10.26 GiB / 12288 MiB budget
23:55  parks 89   parked 9   restores 21   evictions 39   bytes 11520 MiB / 12288 MiB budget  (93.8%)
```

- **Both** limits are live, and the steady band is `parked 7-10 of 10` with `bytes` at **76-99.6%** of the
  12288 MiB budget — the LRU cycle, not a ratchet. A `99.6%` reading at `parked=10` is an instant where both edges
  coincide (45 min later the same boot read `parked=10 76.5%`, big snapshots replaced by 0.9-1.9 GiB ones). Capacity
  really is capped at both ends, so more holding needs the PAIR: `--conversation-cache-slots 10 -> 12` **and**
  `--conversation-cache-mib 12288 -> 16384` (+~2.5 GiB RAM into 19 GiB of MemAvailable, restart-only). Not bought:
  389 park attempts against 66 restores means the extra capacity would mostly re-park conversations that never
  get restored.
  The `parked=10` readings are NOT an older era's leftovers — they occur in the current boot too (the log-scoping
  caveat further down is about the **RAM-admission** counters, where the era difference is 178 vs 0).
- Is the parked tier earning its RAM? **Yes, by 22:1** (measured over the 21:19->00:08 boot with `monitor.py`):
  102 park lines copied 7.09M tokens in **24.7 s**, 22 restores brought back 1.35M tokens in **1.65 s**, and 1.35M
  tokens of prefill is **553 s** at the measured prefill speed (13819 tokens read -> first engine token in 5.641
  s = 2450 tok/s). Net **+528 s**. Note the counters disagree by design: `/metrics parks` (362) counts park
  *attempts* including superseded re-parks, the log has 102 `parked N tokens in X ms` lines — price the log's
  seconds, not the metrics counter.
- So a 93-97% budget reading is the LRU working at the edge, not a fault: `evictions 88` against 102 parks means
  most snapshots are written for a conversation that will be re-parked before it is needed, and the ones that DO
  get restored save ~30 s each. Do not "fix" the percentage.
- Slot release is not free though: `slot 2 gave back 98544 tokens of this conversation (all it holds) in
  602.2 ms` — a 98k conversation leaving a slot costs 600 ms.
- RAM is the term that limits buying more budget: engine `ram_used 41.3 GiB of 62.3` = parked 11.5 + whole-K/V
  pinned 6.2 + experts 7.06 + arena; container 35.65 GiB; host **MemAvailable 19 GiB** (was 22.0 ten minutes
  earlier). `--conversation-cache-mib 12288 -> 16384` spends ~+4 GiB of that. The guard `--conversation-cache-min-free-mib
  1536` has **not** fired this boot (`physical RAM admission` after the last `engine started:`: **0**), but the same
  file holds **178** such lines from older boots where the floor was 2560 MiB and available RAM had fallen to
  ~4 GiB — so the guard works, and 4 GiB available is a state this box has actually reached. Do not read the 178 as
  current.

**The parallel entry is not serving.** `ss -ltnp` shows only 5801 (coder) and 8080 (llama-swap). The
`admiring_booth` container (strata image, up 7 h, 43 MB) has **no bind mounts, no `MODEL`/`PARALLEL`
env, no engine process and no engine log inside** — it is a bare image launch, not the
`qwen3.8-flash-next-iq3_s*` recipe. Consequence: routing to IQ3_S makes llama-swap cold-start a full
engine load (~40-90 s), which alone exceeds `queue_timeout 90` and produces this same red error.

**Decision 2026-10-28: leave it.** It costs 43 MB and an anonymous volume; nothing routes to IQ3_S. If it ever
does, llama-swap starts the real recipe container (`--replace --name ${MODEL_ID}`) on demand — the stray is not
what serves that model, and it does not block that name.

Watch item, not a verdict: MTP acceptance in that window was `630 of 955 (66.0%)` against 78.8% aggregate
and 87% at the k8v4 boot. Attribute only with the fixed-prompt probe.

### Reading the engine log per boot (a trap I hit while writing this section)

`docker.engine.log` accumulates every boot of the container, so a plain `grep -c` mixes eras: the current
config (`min-free-mib 1536`) has **0** RAM-admission skips while the file holds **178** from a 2560-floor era. Scope
the read to the last boot first — the checklist says this for a reason:

```bash
C=qwen3.8-flash-next-coder-iq1_m-parallel; L=/data/state/strata/launch/docker.engine.log
S=$(podman exec $C grep -n 'engine started:' $L | tail -1 | cut -d: -f1)
podman exec $C sh -c "sed -n '$S,\$p' $L | grep -c 'physical RAM admission'"
podman exec $C sh -c "sed -n '$S,\$p' $L | grep -o 'parked=[0-9]* bytes=[0-9]* evictions=[0-9]*' | tail -1"
```

Note the quoting: inside double quotes `$p` expands to nothing, so the `sed` program must be single-quoted
(a `$p` in double quotes silently yields an empty read, which reads as "0 events" — that is how I first got this
section wrong). `./monitor.py` in this directory does the scoping for you: one line every 30 s with queue, cache
budget %, CUDA0 free vs the 512 MiB cliff, host MemAvailable and the three log guards, plus a `^` warning when any
of them crosses (budget >= 95%, `queued > 0`, free VRAM < 512, RAM-admission skips > 0).

## Boot verification checklist (grep the engine log)

Log: `/data/state/strata/launch/docker.engine.log` (inside the container); take everything after the
last `engine started` line.

1. argv carries `--kv int8 --kv-resident 86016 --layer-split 21 --max-context 131072 --pcie-frac 0.20 --batch 3`
   **and** `--conversation-cache-mib 12288 --conversation-cache-min-tokens 16384 --conversation-cache-park-gain
   12288`. `--kv k8v4` in argv = the int8 revert did not land (§ Where each setting lives — `--kv` is also in `user_args`,
   which wins); `--kv-resident 114688` or `131072` = the residency step-back to 86016 did not land (§ Decode throughput
   is why 86016 is the target); `--batch 4` = only the preset was changed,
   `-e PARALLEL` in the container config wins.
2. `layer split: layers 0-20 (CUDA0), 21-47 (CUDA1)` and
   `CUDA1 runs layers 21-47, expert cache 6912 slots (13.78 GiB), 6912 of its 6912 profiled pairs`.
3. `expert cache 5376 slots, 9.64 GiB of VRAM` on CUDA0 and **`layer split: 100% of the experts resident, the
   prompt path's streamed ring 384 slots`**. Metrics must read `expert_slots 12288`, `expert_slots_primary 5376`.
   At 4 slots they read 12268 / 5356 instead — 20 short, covered by the ring, **not** a regression (§ 4-slot load).
   At int8 + 86016 it is expected to land at **5376 / 12288** (where the int8/86016 era sat). The 4-slot eras read 12268 /
   5356 and the int8 + 114688 boot read **5372 / 12284** — 4 short, covered by the ring, **not** a regression (§ Measured
   boot at `--kv int8` + `--kv-resident 114688`). Do not chase 5376: the `expert cache auto -> N slots` estimate is only a
   search intermediate (3884 / 4003 / 4270 seen).
4. Both `N MiB of VRAM free with everything loaded` >= 512. Measured: **711 CUDA0 / 1415 CUDA1** at 3 slots + int8 +
   114688; ladder on this box: 1005/1821 at k8v4 + 131072, **1681/2777 at k8v4 + 86016**, 675-711 at 4 slots + int8 +
   86016 — so expect **~0.9-1.7 GiB free** at int8 + 86016 on 3 slots and confirm it on the first boot after the step-back
   (§ Decode throughput says that step is also the faster one). **No `- LOW`** on either card. Gate on CUDA0's distance
   above **512**; `--vram-reserve-mib 1024` is nominal, not a floor (measured: free landed at 1005 with the reserve set
   to 1024). If even 86016 is too tight for what runs here, step `kv-resident` down again (`65536`) — do not touch the
   reserve flags.
5. `resident RAM: 7.06 GiB of experts in RAM, 0 exchanged with the VRAM tier, 0 blob reads from the file`.
   (`since the start RAM 36600 blobs` is *not* decode missing VRAM: `the split stages lend 3739 slots to
   the prompt path … keep their experts in RAM too`.)
6. `KV streaming:` lines **present** at 86016 (they should be — streaming is the intended state at R < `--max-context`,
   and § Decode throughput measured it as the *faster* config), and `/metrics` reports `kv_resident: 86016`. Full
   residency (131072) removes the line entirely and reports `kv_resident: 0` — that sentinel is the pass condition for
   full residency, not a failed edit (§ Applied: `--kv-resident 131072` — full residency).
7. `arena_mib` rises as `kv-resident` steps down (6963 at full residency, **7166 at 86016**). `ram_used` should come
   **down** a few GiB versus the 3-slot int8 + 114688 boot (`ram_used ~31.8 GiB`, host `MemAvailable` 18.5 GiB), because
   streaming allocates the whole K/V per unit in pinned RAM (§ Measured boot at `--kv int8` + `--kv-resident 114688`).
   Check host `MemAvailable` too, not just the engine's number.

## Decode throughput — where the tok/s actually goes (measured 2026-10-29 ~01:15, current boot)

The per-request line is the source of truth; everything else is derived:

```
strata serve: prompt 64216 tokens = 63505 reused + 711 read in 727 ms (978.5 tok/s), 1406 generated in 10918 ms (128.8 tok/s), drafts accepted 798 of 1013
```

From that, two independent terms and one identity. A **step** is one forward pass over
`1 target + drafts offered`; an accepted draft is free output:

``
steps        = generated - accepted
fed          = steps + offered            (tokens pushed through the GPU)
output tok/s = 1000 / ms_per_fed_token x generated / fed
```

Current boot (207 requests, 81,373 steps, 199,535 tokens fed, 1453 s decode):

| term | measured | meaning |
|---|---|---|
| ms per fed token | **7.12** -> feed ceiling **140 tok/s** | the hardware path |
| generated/fed | **0.867** (accept 79.6%, drafts 1.45/step) | the draft yield |
| output | **120.2 tok/s** average | the product |

Distribution over the same boot: median 122.8, p90 145.7, **max 173.0** -- and 173 belongs to the request with `drafts accepted 486 of 502` (**96.8% acceptance**). The slowest (100.2 tok/s) had 62/94 (**66%**). So the per-request spread is **draft acceptance**, not context or VRAM: an average of 160 tok/s needs ~93% acceptance on every request, and typical coding traffic sits at 79-84%. Perfect acceptance would raise the ceiling to **193 tok/s** (`feed x (1 + drafts/step)`); nothing in the VRAM budget can get there.

### Per-config comparison (same identity, matched context 40-100k)

| config | n | output tok/s | ms/fed | drafts/step | accept |
|---|---|---|---|---|---|
| `k8v4/131072` b3 | 24 | **144.0** | **6.36** | 2.05 | 84.8% |
| `int8/86016` b4 | 180 | **133.5** | **6.70** | 1.81 | 82.6% |
| `k8v4/86016` b3 | 18 | 136.0 | 6.70 | 1.94 | 84.5% |
| **`int8/114688` b3 (live)** | 170 | **120.2** | **7.12** | 1.45 | 79.6% |
| `int8/20480` b3 | 382 | 119.3 | 7.34 | 1.67 | 78.2% |
| `q4_0` b3 | 222 | 110.8 | 7.80 | 1.58 | 77.5% |
| `--spec-min-p 0.5` b3 | 37 | **78.7** | 10.13 | 2.16 | 69.1% |

Readings:

1. **The `--kv-resident 114688` bump cost decode, and bought nothing.** `int8/86016` = 6.70 ms/fed,
   `int8/114688` = **7.12** (+6% per token). Meanwhile the KV streaming hit-rate median went the wrong way:
   99.3% (86016 era) -> **81.4%** (114688 boot). The extra 28,672 resident cells per QSA layer did not even
   raise the hit rate, so the residency edit is a net loss. Revert to `86016`.
2. **`int8` exactness costs nothing.** At 86016, int8 and k8v4 are both **6.70 ms/fed**. The quant only mattered
   through VRAM headroom, not per-token time. Keeping `--kv int8` is free.
3. **Expert tier is not the variable.** Every boot loads `expert cache 5372-5376 slots, 9.63 GiB` and
   `resident RAM mode: 7.06 GiB of experts in RAM` -- identical at 20480, 86016 and 114688. Raising
   `--kv-resident` never moved a single expert slot, which is why the reserve flags are not the KV lever (§ How
   much `--kv-resident` can be raised).
4. **Context length costs ~0**: 7.02 ms/fed at 70-100k vs 7.18 at 40-70k (noise). **Concurrency costs ~0 per
   stream** too -- feed ceiling stays 140 with three slots decoding at once, because concurrent MoE tokens
   share the weight reads (`--batch-mtp`). The engine says so at load: `--batch 3: the slot sessions take
   2.20 GiB of VRAM on CUDA0 that the expert cache would otherwise hold`.
5. **`--spec-min-p 0.70` is right.** The 0.5 eras offered 2.16-2.20 drafts per step but acceptance fell to
   66-69% and the era read **78.7 tok/s** at 10.1 ms/fed. More offers at that acceptance is strictly worse.
6. **KV streaming at the heavy requests is nearly free**: `99.9% of 125637985 block reads hit VRAM, 478 MiB
   read from RAM` for a 97k-token request. The scary-looking `57.10% of 12840 block reads, 22.2 MiB from RAM`
   lines are 1-2 token requests: tiny absolute cost.

**What is NOT throughput but feels like it:** the per-turn slot handoff.
`strata batch: slot 0 gave back 59401 tokens of this conversation (its turn checkpoint) in 191.2 ms` followed
by `slot 0 takes 62882 tokens (copied in 404.2 ms)` -- ~0.6 s of every turn is conversation-cache handoff on
the current boot (`parked 10/10`, `evictions 134`). That is TTFT, not tok/s.

### Recommended edit from this section

`--kv-resident 114688 -> 86016` in **both** layers (`strata/launch-presets/docker.json` -> `extra` and
`strata-coder-iq1_m.json` -> `user_args`), restart-only, keeps `--kv int8` exactness. Expected: 6.70 ms/fed
(feed ceiling ~149 tok/s), output **128-134 tok/s** at the current draft mix, KV hit back near 99%, and CUDA0
free rises a few hundred MiB (measured 675-711 MiB free at `int8/86016/--batch 4`; the 3-slot `k8v4/86016` boot
sat at 1681 MiB). Do NOT chase `k8v4` for the extra ~10 tok/s -- the 144.0 row is real but it is Q4_0 V, which
was rejected on exactness grounds (§ Applied: `--kv int8` + `--kv-resident 114688`).

### Applied: `--kv-resident 86016` (2026-10-29 ~01:25)

Both layers edited to `--kv-resident 86016 --kv int8` (`strata/launch-presets/docker.json` -> `extra`,
`strata-coder-iq1_m.json` -> `user_args` / `args` / `args_written`); copies kept as `*.bak-pre-kvres86016`. Restart-only,
so the live container still runs 114688 until the next restart. On that boot verify: **ms/fed back to ~6.7** (from 7.12),
output **128-134 tok/s** at the current draft mix, KV-streaming hit median back near **99%**, CUDA0 free up several hundred
MiB, and host `MemAvailable` a few GiB higher. If CUDA0 ever prints `< 512` at 86016, step down again (`65536`) — do not
raise the reserve flags (§ How much `--kv-resident` can be raised — the expert cache sits at its cap either way).


## Failure modes, in the order they will bite

| symptom in the log | meaning | lever, in order |
|---|---|---|
| `CUDA1: N MiB … - LOW: its window graphs are captured on first use and need room too, and a full card can stall a request` | that card is out of working room (window captures take ~87 MiB each, vision buffers more) | `kv-resident` −8192 cells; then `-e PARALLEL` −1 (needs a switch); **not** `--vram-reserve-later-mib` |
| `WARNING: only N MiB of VRAM free … the driver can page GPU memory to system RAM, decode falls to a few tok/s and a window may never finish (#2065)` | below the paging threshold on that card | smaller `--kv-resident` or `--max-context` — **never** more experts |
| expert slots below 5376/6912, `layer split: <100% …` | KV or sessions ate expert room | step `kv-resident` down; if residency still will not close, `--layer-split auto` and read the split search's `best of N placements` line |
| `skip parking (physical RAM admission)` + flushed snapshots | RAM, not VRAM, is the wall | `--conversation-cache-slots 10 → 6`, then `-e PARALLEL` −1 (needs a switch) |
| `no NVIDIA GPU found (nvidia-smi did not answer)` → `adopt` fallback, exit 5 | the image's `nvidia-smi` PT_INTERP is missing in the container | the `-v /nix/store:/nix/store:ro` mount (§ llama-swap/strata-coder) |
| `expert cache auto: X GiB free, 1024 MiB reserved` shrinking below its layer count | the engine is trading coverage for KV | step `kv-resident` down one row of the int8 table in § Applied: **114688 -> 98304** (adds 330 MiB on CUDA0). If it still will not close, that is a `--batch` problem, not a KV one: `-e PARALLEL` 3 -> 2 buys a whole unit's worth (5280 B per cell on CUDA0). |

| `the inference queue wait deadline expired; retry later` (a 429 from the **wrapper**, not the engine) | 3 slots busy with 45-98k conversations and a 4th client queued past `queue_timeout 90` | nothing (it is a capacity signal), or `queue_timeout 90 -> 180` with `max_queue` kept (restart-only), or `-e PARALLEL 3 -> 4` **only together with** `--kv-resident 98304` (see § The queue 429 — at 114688 it lands CUDA0 ~302 MiB, below the paging cliff) |

Do not read `tok_s_mean` as a config A/B: it is a **per-window** mean and reports `0.0` on a window with
no request in flight. Compare with a fixed prompt (the probe script) instead.

## Applying changes

`~/.config/strata/coder` is bind-mounted at `/data/install`, so preset and run-config edits are read at
**container start** — `podman restart qwen3.8-flash-next-coder-iq1_m-parallel` is enough. A `-e PARALLEL`,
`capabilities.*` or mount change needs `nixos-rebuild switch` instead (llama-swap regenerates its YAML).

Restart reloads the model, which **cuts this session mid-generation** — this box is usually serving the
agent that is doing the tuning. Restart when the current turn can afford it, and verify the checklist above
before doing more work.
