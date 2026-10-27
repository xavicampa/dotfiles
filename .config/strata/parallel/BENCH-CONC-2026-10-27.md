# Concurrency bench — parallel / `qwen3.8-flash-next-iq3_s-parallel` (2026-10-27)

> Measured while this tree was still `5slot/` and the backend was still `…-parallel5` (renamed the same day);
> the run dirs under `/data/bench/` keep whatever name the container had at the time.

Engine `0.1.48-linux-x86_64-cuda-cuda13`, preset `docker` (`parallel: "5"`, port 5802, ctx 131072,
`--batch 5 --batch-mtp --spec 4 --layer-split 32 --kv int8 --resident-experts`), instance
`7fb470110f0b427fa3017c51454c28a6`. Both cards: RTX 5070 Ti + RTX 3090 Ti.

Runs below are saved under `/data/bench/` (volume `strata-data`): `2026-10-27-mix-c{01,02,03,04,05,05-r5,08,16}`,
`2026-10-27-parallel-prefill-cancel-v1`, plus the operator's own `2026-10-27-serve-homepc-1`.
Every bench run used `--profile launch-docker --no-start --require-managed-match` — `--no-start`
so the harness can never restart the live engine (Pi is served by it).

## 1. Steady-state throughput curve (new: `bench-cc-curve.py`)

`python3 ~/.config/strata/parallel/bench-cc-curve.py` — streaming, temperature 0, 300 tok/stream,
distinct prompts, 3 rounds per level, medians. Extends `bench-batch-mtp.py` past `--batch`.

| streams | agg tok/s | per-stream med | per-stream min | med latency s |
|---:|---:|---:|---:|---:|
| 1 | 141.5 | 141.5 | 89.5 | 2.12 |
| 2 | 149.3 | 75.3 | 67.3 | 3.98 |
| 3 | 169.4 | 56.6 | 50.8 | 5.30 |
| **4** | **175.1** | 44.0 | 40.6 | 6.82 |
| **5** | **174.0** | 34.9 | 33.3 | 8.60 |
| 6 (over) | 156.2 | 32.6 | 26.0 | 9.20 |
| 8 (over) | 142.5 | 24.9 | 17.7 | 12.08 |

Second probe (non-streaming, 300 tok, 3 rounds) with the engine's own `strata batch:` window
accounting aligned to each leg:

| streams | agg tok/s | per-stream med | med / max latency s | rows/window | ms/window | MTP accepted | slot take / give-back |
|---:|---:|---:|---:|---:|---:|---:|---:|
| 1 | 129.6 | 129.7 | 2.31 / 3.44 | — | ~18–21 | ~78 % | 0 / 0 |
| 5 | 178.9 | 36.3 | 8.27 / 10.33 | 6.95 | 35.1 | 77.6 % | 15 / 10 |
| 10 | 145.0 | 19.2 | 16.01 / 21.45 | 6.93 | 34.9 | 75.1 % | 30 / 6 |

**The aggregate knee is at 4–5 streams (~170–179 tok/s ceiling), confirmed against the 2026-10-26
table (166.7 @4).** The fifth stream is free at the aggregate level and costs 44 → 35 tok/s per
stream. **Past `--batch` the box does not just slow down, it loses throughput: 174 → 156 (6) → 142–145
(8–10), i.e. −10…−19 %**, and the per-stream tail reaches 17.7 tok/s. Window cost itself does not grow
(35 ms/window at 5 and at 10 streams); the loss is slot churn — the extra conversations are not resident,
so each pays `slot takes N tokens (copied in ~116–120 ms)` + `gave back … in ~47 ms` of dead wall time,
and MTP acceptance slips 77.6 → 75.1 %.

## 2. Official suite: latency / TTFT / admission (`--suite parallel-mixed-v1 --repeat 3`)

Mixed phase = `concurrency` requests released at once, 3× 32-token + 2× 96-token caps; medians over the
6 mixed phases, with the max phase in parentheses-style `/` second column.

| conc | TTFT p50 s | TTFT p95 s | lat p50 s | lat p95 s | `output_tok_s` | peak active | peak waiting | peak occupied slots | queued | fails |
|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|
| 1 | 0.04 | 0.04 | 0.21 | 0.21 | 148.9 | 1 | 0 | 0 | 0 | 0 |
| 2 | 0.14 | 0.36 | 0.80 | 1.33 | 96.4 | 2 | 1 | 2 | 0 | 0 |
| 3 | 0.35 | 0.50 | 1.01 | 1.54 | 103.7 | 3 | 2 | 3 | 0 | 0 |
| 4 | 0.25 | 0.61 | 1.25 | 1.96 | 130.5 | 4 | 3 | 4 | 0 | 0 |
| 5 | 0.44 | 0.82 | 1.56 | 2.29 | 125.5 | 5 | 4 | 5 | 0 | 0 |
| 8 | 0.91 | 2.88 | 3.54 | 4.23 | 120.9 | 8 | 7 | **5** | 0 | 0 |
| 16 | 2.51 | 7.03 | 5.02 | 8.44 | 121.3 | 16 | 15 | **5** | 0 | 0 |

- **Do not read scaling from `output_tok_s` on this suite.** It is tokens ÷ phase wall time, and the
  phase ends when the *longest* stream ends while the 32-token streams stopped long before; that is why
  it dips at c=2/3 and looks flat from 5 to 16. For the same runs, per-stream
  `completion_tokens/(latency−ttft)` = 33–42 tok/s at c=5, which agrees with the steady-state 35 tok/s —
  the suite is fine for latency/TTFT/admission, not for throughput.
- **TTFT is what oversubscription actually destroys**: p95 0.82 s at 5 streams → 2.88 s at 8 → 7.03 s at 16.
  These are 66-char prompts; with real Pi prompts (10k+ token prefills) the queue wait is worse.
- **Admission is unbounded**: at c=8/16 `peak_active` = the full concurrency while `occupied_slots` stays
  pinned at 5 and `waiting` = c−5, `queued` 0, no rejections. The extra load is absorbed silently as churn.

## 3. Repeatability (`strata bench compare`)

Operator's 11:09 run (`--repeat 5 --concurrency 5`, condition `parallel-5`) vs an identical rerun
(`2026-10-27-mix-c05-r5`), both `managed_launch_checked`:

| median mixed metric | 11:09 run | rerun | change |
|---|---:|---:|---:|
| p95 TTFT s | 0.899 | 0.743 | −17.3 % |
| p95 latency s | 2.353 | 2.204 | −6.4 % |
| output tok/s | 122.1 | 130.4 | +6.8 % |

Within-run spread of the mixed phase was 93.3–131.9 tok/s; the first mixed phase after warm-up is the
outlier in both runs (114.7 / 93.3). So **treat ~±8 % as the noise floor for this suite at c=5**, and
warm up before comparing. `bench compare` refuses runs with different `--repeat`, so keep repeat fixed
for A/B.

## 4. Suites that did not run, and why

`parallel-overload-v1` (c=10, 16) and `parallel-cancel-v1` (c=5) both refused:

```
strata: overload suite requires a server with max_queue and queue_timeout configured
strata: cancellation suite requires max_queue >= 1 and queue_timeout >= 2 seconds
```

This instance runs with `max_queue = None`, `queue_timeout_s = None` (visible in the reports'
`environment`), i.e. no admission back-pressure — the same fact that makes §2's silent oversubscription
possible. `serve.server` accepts `--max-queue` (0..4096) and `--queue-timeout` (0.1..600 s, requires
`max_queue`); `strata serve` maps them to the preset keys `max_queue` / `queue_timeout`. Setting e.g.
`max_queue: 3`, `queue_timeout: 30` in `strata/launch-presets/docker.json` would (a) make the two suites
runnable and (b) make the engine reject/shed instead of thrashing slots — **but it needs an engine
restart, which drops the Pi session on 5802.** Not applied.

`parallel-prefill-cancel-v1 --repeat 2 --concurrency 5` did run and **passed**: after the prefill
cancel, the recovery request had TTFT 0.50 s / latency 0.73 s, so a cancelled conversation releases its
slot promptly (relevant for Pi `timeoutMs` churn).

## 5. Readings

1. **5 slots is correctly sized for the Pi budget** (4 subagent children + parent = 5 streams,
   `~/.pi/agent/extensions/subagent/config.json`). Aggregate at 4 and 5 streams is the same (175.1 vs
   174.0 / 178.9) — the box saturates at ~175.
2. **Client concurrency must stay ≤ 5.** Going to 6–10 costs ~10–19 % aggregate *and* doubles-to-quadruples
   latency; there is no back-pressure to save you. If a second async subagent run ever lands alongside the
   first, this is the cliff.
3. **If 5 streams rarely co-occur, `parallel: "4"` is free**: c=4 measured 175.1 agg / 44.0 per-stream —
   same ceiling, +26 % per-stream. This closes the "untested middle" in the notes (§ Expectations) without
   touching the CUDA0/CUDA1 memory budget.
4. **Do not chase more slots**: `--batch` caps at 8, and +3 slots ≈ +1.2 GiB on CUDA0 with the expert
   cache shrinking further (the notes already see the cache cut in the feed path: 78.9 % hit @5).
5. Regression tracking recipe: `strata bench run --suite parallel-mixed-v1 --repeat 5 --concurrency 5`
   (latency/TTFT/admission) **+** `bench-cc-curve.py` (throughput curve), same repeat, and compare only
   like with like.

Caveat: the bench client and this Pi session share the engine. Runs were issued in tight sequential
batches so the engine had no other active stream, but Pi traffic before/after each batch is part of the
numbers' ±8 % noise floor.

## Postscript (same day) — batch 4 + queue bound is LIVE

Acted on §5.3, and the restart taught something worth more than the numbers: a container start **re-derives** the
profile (`launch/runner.py:ensure_profile` replaces the overrides with exactly host/port/parallel, taken from the
preset), so the first `strata profile set` was silently reverted at the 11:31 restart — the running engine came
back `--batch 5` again. Final state, applied 11:4x via `strata runtime restart --profile launch-docker`
(instance `8e0c3703ed2749abb65178745c27460b`): engine `--batch 4`, serve `--parallel 4 --max-queue 3
--queue-timeout 90.0`, `admission_limit 7`; `parallel: "4"` now lives in the **preset** so it survives restarts,
while the queue knobs live only in the profile and must be re-applied + `runtime restart`ed after any container
start. pi budget cut to 3 children (`globalConcurrencyLimit: 3`, `parallel.concurrency: 3`).

Re-measured at batch 4 (`bench-cc-curve.py 1 2 3 4 5 6 7`): 4 streams **179.3 agg / 45.0 per-stream** (the best
point seen on this box), 5 → 150.2 / 37.9, 6 → 143.5 / 33.2, 7 → 143.1 / 31.0. So the table above still holds in
shape — oversubscription past slots is pure loss — but the pathology is now bounded instead of silent: at 7
concurrent TTFT stays ≈0.01 s (unbounded batch 5 measured p95 2.88 s at c=8, 7.03 s at c=16), and 8 clients get
`peak_active 7` plus **one 429** with `queue_timeouts: 0`. `parallel-overload-v1` and `parallel-cancel-v1` now run
and passed. Boot at 4 slots is cheaper than 5 as predicted: expert cache 5270 (was 5051), CUDA1 residency still
8192/8192 pairs, free VRAM 667/998 MiB — and note the old 5-slot boot was logging repeated
`only 179/249/379/509 MiB of VRAM free … below 512 MiB` (#2065) warnings, i.e. it was running inside the paging
guard. Full record: `TUNING_NOTES.md` § batch 4 + queue back-pressure.

## Postscript (2026-10-27 12:09) — the `-parallel5` container name is gone

The llama-swap key, and therefore the podman name, is now `qwen3.8-flash-next-iq3_s-parallel`; the tree is
`~/.config/strata/parallel/`. The move itself is free — podman binds the directory's inode, so the engine kept
serving through the `mv` and `strata launch --status` reported `docker: ready` the whole time. What needs care is
the *name*: see the dotfiles NOTES § llama-swap/strata-parallel (a stale `…-parallel5` container would bind a
nonexistent path and go through setup's defaults rewrite).
Re-verified after the system switch (`/data/bench/2026-10-27-rename-check`, instance `a590532e`,
`managed_launch_checked`): `slots_effective 4`, `max_queue 3`, `queue_timeout_s 90.0`, `admission_limit 7`,
`peak_active 7` / `occupied 4` / one 429 / `queue_timeouts 0`, boot 4 slot sessions + expert cache 5270 +
8192/8192 pairs + 667/998 MiB free — identical to the pre-rename run, as expected.
