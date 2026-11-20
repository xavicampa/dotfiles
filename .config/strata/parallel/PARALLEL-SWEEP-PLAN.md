# Parallel tree — A/B plan for the batch-slot family (engine 0.1.62 / image 0.2.16)

> **DONE 2026-11-20 08:00–08:18 — results are in `TUNING_NOTES.md`, § "The batch-slot pipeline:
> `--batch-groups 3` + `STRATA_PIPED_MTP=2` is +21…+26 % at 2–3 streams".** Headline: the pipelined
> groups + `STRATA_PIPED_MTP=2` (+ `STRATA_BATCH_SELF_COMMIT=0`, which the engine needs to accept the
> drafts) is the biggest single win measured on this tree: +26 % agg tok/s at 2 streams, +21 % at 3,
> +6.5 % solo, against four control boots. `STRATA_PW_WITH_BATCH=1` gives +12 % solo on the serial path
> and does not stack with the groups path. **The tree now runs the new config** (`--batch-groups 3`,
> `STRATA_PIPED_MTP=2`, `STRATA_BATCH_SELF_COMMIT=0`), depth probed at `=1/2/3`; see the notes section.
> Below is the plan as written before the first boot.

Written 2026-11-19, before the first arm booted. The 1slot route-tail sweep is closed
(`../1slot/BENCH-1slot.md`, 2026-11-19 section); this file governs the parallel tree.

## Why this family, why now

The whole `STRATA_PIPED_MTP` / batch-slot-pipeline family (#5860, #5864) has **0 hits** in
`TUNING_NOTES.md`. It is exactly the machinery this tree runs (`--batch 3 --batch-mtp`), and the
live boot leaves two of its levers inert:

```
strata generate: --pipeline-windows 2 is off: not with --batch slots (STRATA_PW_WITH_BATCH=1 keeps it for the solo path)
strata batch-groups auto: 1 group of 3 slots
```

`--batch-groups 2` was rejected in the notes (−15 %, "Other measured decisions"), but that boot had
pipelined groups with **no drafts at all** (`STRATA_PIPED_MTP` off = no `--batch-mtp` in the
pipeline). That rejection does not cover `groups + PIPED_MTP`.

## Ground truth from the live boot (era 297534, 22:40:35)

- `--batch 3`, `--batch-mtp`, `--pipeline-windows 2` (inert), `--layer-split 32`, `--pcie-frac 0.00`,
  `--kv-resident 20480`, `--spec 4 --spec-min-p 0.70`, `--resident-experts`, `--adapt-async 1`.
- Env pins: `STRATA_ADAPT_LAG=2`, `STRATA_PF_FUSED=1`, `STRATA_SPLIT_RING=384`, `STRATA_EXCHANGE_ROTATE=1`.
- VRAM at end of boot: **CUDA0 1179 MiB free**, **CUDA1 2621 MiB free**.
  expert cache 5233 slots (CUDA0, 9.65 GiB) / 8192 slots (CUDA1, 16.52 GiB, profile-capped, not VRAM-capped).
- 55 % of experts resident; pinned RAM 27.72 GiB; prompt-path ring 384 slots; lend 3652 slots (K==N healthy).
- Suffix drafts are active and accepted (65/81, 23/28) — the `STRATA_PIPED_LOOKUP` arm has a substrate here.
- `STRATA_NV_CHUNK` note in the boot: auto may take chunks up to 32768, `STRATA_NV_CHUNK=0` keeps 8192.
  The plan still chose chunk 8192 (same as the 1slot tree) — so 16K/32K is *offered*, not used.

## Register facts that gate the arms (v0.2.16 `terminal/data/settings-register.json`)

| setting | status | gate / note |
|---|---|---|
| `STRATA_PW_WITH_BATCH=1` | opt-in, since v0.2.10 | CUDA/HIP only; keeps pipeline windows for the solo path while batch slots run |
| `STRATA_PIPED_MTP=N` | opt-in, since v0.2.7 | needs `--batch-mtp` **and ≥2 batch groups** |
| `STRATA_PIPED_LOOKUP=1` | research | needs `STRATA_PIPED_MTP` **and `--suffix-draft`** |
| `STRATA_BATCH_SLOT_RUNS=1` | opt-in, new (#5864) | CUDA/HIP; 15 launches/layer/slot/window → 8; 512 MiB CUDA scratch ring, 2112 MiB with 4 cards |
| `STRATA_SLOT_READ*` | opt-in | needs a **non-resident** expert cache → inert here (`--resident-experts`) |
| `STRATA_SLOT_CKPT_KV_DIRECT`, `STRATA_KV_COPY_RESIDENT` | opt-in, new | direct pinned-RAM K/V copies |
| `STRATA_PIPELINE_HIT_MIN/LAZY_CHAIN/LOOKUP_RUN` | opt-in | the notes' −15 % was a `LAZY_CHAIN`-era measurement (notes line 707) |
| `STRATA_SPEC_FIXED[_TABLE]` | opt-in, **new in 0.1.62** | fixes verify windows per length → makes arms comparable |
| `STRATA_FOLLOW_DIR`, `STRATA_DUMP_TOKENS_DIR` | measurement only, new | force two arms to decode the **same tokens** |
| `STRATA_DRAFT_COSTS_LEARN=1` | test harness | learns the draft-cost table in one start |
| `STRATA_NUMA_CARD/POOL/SPLIT` | opt-in | **no-op here**: 1 NUMA node, both GPUs `numa_node -1` |
| `STRATA_MEM_CREDIT_INACTIVE` | opt-in | **no-op here**: container `Memory=0` (no cgroup limit) |
| route-tail-skip | — | docs: never with `--batch` → closed on this tree by arithmetic |
| `--lookup-max-t >8` | — | gated to one conversation on one GPU; split/batch stay at 8 |
| `STRATA_PF_FUSED=1` | default only for gfx1151/sm_121 | our cards are sm_120 + sm_86 → verify whether the pin still does anything now that MMQ is gone (0.2.16 boot says "48 of 48 layers on the fused kernels") |

VRAM budget for the arms: pipeline stage buffers were 55.7–70.3 MiB each on the 5070 Ti; the piped-MTP
save graph is ~6.4 MiB per stage at 4 slots. CUDA0's 1179 MiB is the binding card. If an arm prints a
cache shrink ("cache N slots, was M"), the arm is **confounded** — stop and re-plan.

## Arms (ranked), 2 boots each, interleaved control after every arm

- **C-a / C-b** control — re-measure at 0.1.62 first. All decisions are relative to these.
- **A** `STRATA_PW_WITH_BATCH=1` — quality-neutral; overlap in the solo path. Upstream (2× A6000 IQ3_S):
  lone request +14 % code / +9 % file rewrite / +3 % long decode; 2 requests not slower. Bench: solo + 2 streams.
- **B1** `--batch-groups 2` **alone** — cheap, and it calibrates what pipelined groups cost on 0.1.62.
- **B2** `--batch-groups 2 --batch 3` + `STRATA_PIPED_MTP=1` — the real question. Upstream, same model and
  quant on 2× A6000: serial 60.7 / piped-no-MTP 55.1 / **piped+MTP 70.4 (+16 %)** at 2 streams, +15 % at 4.
  Constraint: `slots × (1 + N)` ≤ 8 → with `--spec 4` (N=3) three slots need groups of two at most.
- **B3** `--batch-groups 3` (2 slots/group) + `STRATA_PIPED_MTP=1` — if B2 pays.
- **E** `STRATA_BATCH_SLOT_RUNS=1` — orthogonal, 8 launches instead of 15 per slot per layer. Needs 512 MiB
  CUDA0 scratch: only if A/B2 leave ≥ ~800 MiB free.
- **F** `STRATA_PIPELINE_HIT_MIN=0.35` / `STRATA_PIPELINE_LAZY_CHAIN=1` / `STRATA_PIPELINE_LOOKUP_RUN=1`.
- **D** `STRATA_PIPED_LOOKUP=1` on top of B2.
- Later, solo-path only: `STRATA_NV_CHUNK=16` on the parallel tree (the 1slot tree rejected 16K/32K with
  n=1, 213.1 → 203.7 → 205.7; not re-run here unless the cc≥8.0 32768 auto changes the plan).

## Bench protocol for this family (differs from the 1slot file)

`bench-cc-curve.py` drives **n parallel clients** at `--batch 3`: it is the only instrument in this
directory that matches the family being tested (the 1slot one-shot file measures solo decode only).
Per arm: solo pass (n=1) + n=2 + n=3, medians of tok/s, plus `erastats.py` for the era.
Report `D` (cold read) **within-arm only** — proven not comparable across boots this machine:
two identical 0.1.62 controls read 4777.0 and 4976.2 (+4.2 %).

Assertion that the knob reached the engine (per boot):
1. `/proc/<engine pid>/environ` contains the pin (engine child, argv[0] = `strata`, not the `bash -c` wrapper).
2. boot log prints the effect: `--pipeline-windows ...` line gone/changed for A; `batch-groups auto:` /
   group rows for B; a `slot runs` line for E. Grep the era slice of `docker.engine.log`.
3. `--adapt-async 1` still accepted ("adaptive tier asynchronous") — the notes say it is incompatible with
   `--batch-groups` / `--pipeline-windows 2`, so an arm that silently loses the async tier is confounded.
4. no cache-shrink / `LOW` / `WARNING` lines.

Noise control (new, because the 1slot sweep proved decode drift is ±6–11 %): for any arm whose expected
effect is < ~7 %, add `STRATA_SPEC_FIXED=1` to **both** the control and the arm, and/or drive the arms with
`STRATA_FOLLOW_DIR` from a dumped token stream so both boots decode the same tokens.

## Cost accounting

One boot ≈ 38 s reload. Arms A, B1, B2 (+2 controls) ≈ 6 boots ≈ 4 min of reload, plus bench time.
`pi` is served by this tree: the whole sweep takes ~15 min during which the assistant's own engine is down.
