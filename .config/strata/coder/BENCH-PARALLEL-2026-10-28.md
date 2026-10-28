# Parallel bench ladder — coder iq1_m, 2026-10-28

Engine under test: `qwen3.8-flash-next-coder-iq1_m-parallel` (port 5801,
4 slots, ctx 131072, `max_queue 3` → **admission_limit 7**, engine 0.1.52).
It is the model serving the live Pi session, so every run below was issued
against the live server with `--no-start` (never restarts it).

## Commands (repeat verbatim; `--out` is required for serving suites)

```sh
C=qwen3.8-flash-next-coder-iq1_m-parallel
strata bench run --profile launch-docker --no-start --suite parallel-mixed-v1  \
  --concurrency 5 --repeat 5 --require-managed-match --out /data/bench/2026-10-28-coder-mix-c05
# ... c=8 mixed (--repeat 3, out ...-mix-c08)   -> FAILED BY DESIGN, see below
# ... parallel-overload-v1 --concurrency 8 --repeat 3  out ...-overload-c08
# ... parallel-overload-v1 --concurrency 12 --repeat 2 out ...-overload-c12
```
Already on disk from today: `2026-10-28-serve-homepc-2` = mixed c=4 --repeat 5
(1 warmup + 5 serial + 10 mixed). Bench dirs live on the host at
`~/.local/share/containers/storage/volumes/strata-data/_data/bench/`.

## Steady-state mixed phases (first mixed phase of a run is cold — discard it)

```
engine/slots            c   agg tok/s   lat p50   lat p95   ttft p50   per-stream   rej
coder iq1_m  4 slots    4   111.5      1.525      2.29       0.307      27.9        0
coder iq1_m  4 slots    5   115.4      2.078      2.49       0.464      23.1        0
coder iq1_m  4 slots    8   n/a        3.641      4.18        —         suite refuses (rej 1)
coder iq1_m  4 slots    8*  (overload) 7.35-8.46   ttft 0.93-1.24   126-139 agg   rej 1   recovery 0.22 s
coder iq1_m  4 slots   12*  (overload) 7.30-7.44   ttft 0.66-0.67   144-149 agg   rej 5   recovery 0.51 s
iq3_s  5 slots         4   129.9      1.240      1.96       0.245      32.5        0
iq3_s  5 slots         5   126.5      1.593      2.27       0.451      25.3        0
iq3_s  5 slots         8   121.6      3.393      4.21       0.887      15.2        0   (admission was 8, so c=8 fits)
iq3_s  4 slots         8*  (overload) 6.93-7.94   ttft 0.54-1.46   135-149 agg   rej 1   recovery 0.60 s
serial baseline       today: 145.7 tok/s, lat p50 0.220 s, ttft 0.047 s
```

## Findings

1. **`parallel-mixed-v1` ceiling is the admission limit, not the slot count.**
   On 4 slots + 3 queue it survives c=7; at c=8 it emits `mixed: 7/8 requests`,
   `rejected delta 1`, `output -- tok/s`, and the run reports **failed** after
   one phase. That is expected behaviour of the mixed suite (it treats any
   rejection as a failure), and yesterday's `mix-c08` passed only because that
   engine had 5 slots → admission 8. For anything past the admission limit use
   `parallel-overload-v1`.

2. **The 5th stream on a 4-slot engine is paid for by everyone.** c=4 → c=5 costs
   latency +36% (1.53 → 2.08 s), TTFT +51% (0.307 → 0.464 s) and per-stream
   −17% (27.9 → 23.1 t/s) for only +3.5% aggregate. Queue back-pressure does
   absorb it with zero rejections (`peak_active 5 / occupied 4 / waiting 4`),
   but it is not a win. **4 is the right operating point for the Pi budget of
   3 children + 1 parent.**

3. **Aggregate throughput on this suite never beats serial.** Serial 145.7 t/s;
   best concurrent number on the box is 148.9 (overload c=12, where 5 of 12
   requests were rejected outright and 7 ran). With outputs capped at 32/96
   tokens against 1824-char prompts, prefill dominates: **use these suites for
   latency and admission, not for throughput scaling** — that is what
   `bench-cc-curve.py` measures (see `parallel/TUNING_NOTES.md`).

4. **Overload behaves exactly as tuned, on a model I never tuned.** c=8 →
   `peak_active 7 / occupied 4 / waiting 6`, `rejected 1`, `timed out 0`,
   `queue_timeouts 0`; c=12 → `rejected 5`; recovery is instant (0.218 s, 146
   tok/s). The `max_queue 3 / queue_timeout 90` semantics carry over from the
   iq3_s tree to the coder tree unchanged.

5. **The coder engine prefills worse than iq3_s under contention.** At c=4 its
   TTFT is better than iq3_s at c=5 (0.307 vs 0.451 s), but its c=5 TTFT (0.464)
   matches iq3_s c=5, and its overload-phase TTFT (0.93-1.24 s) is worse than
   the iq3_s overload runs (0.54-1.46 s). Decode is fine: live session shows
   105.5 t/s median, 97.1% KV VRAM hit, 83.7% draft acceptance, reuse ~100%.

## The live margin is zero — the engine has already warned

`nvidia-smi` right now: **CUDA0 488 MiB free** (below the engine's own 512 MiB
paging guard), CUDA1 892 MiB. Post-boot the log carries **one**
`WARNING: only 507 MiB of VRAM free ...` line, advice `--vram-reserve-mib 768`.
The coder tree passes **no `--vram-reserve-mib`** at all, and pins
`--kv-resident 86016` of 131072 cells, which is what fills the card.

No paging damage yet — 297 post-boot requests, `major faults` median **0** and
max **0**, `MemAvailable` 26.7 GiB (IQ1_M is light; the iq3_s engine ran at
5.9 GiB). Earlier iq3_s measurements are the reason the reserve exists there
(`parallel/TUNING_NOTES.md` § VRAM margin: 1280 chosen from measured dips).
### Applied 2026-10-28: 1024 MiB on both cards

`~/.config/strata/coder/strata/launch-presets/docker.json` → `extra` gained
`"--vram-reserve-later-mib": "1024"` and `"--vram-reserve-mib": "1024"` (keys stay
alphabetically sorted inside `extra`). Backup: `docker.json.bak-pre-vram`.

**The preset `extra` is the only carrier this needs** — proven on the iq3_s tree,
where 1280/1024 live in `extra` and appear nowhere in `strata-iq3_s.json`'
as `args`/`user_args` (`user_args` only holds what the operator passed on the
CLI), yet both reach the engine's argv at start. So the run config was deliberately
left alone: less to keep in sync, and setup passes that rewrite it cannot drop these.
The preset is safe from the tuner here: `"tune": "skip"`.

Verified without touching the live engine (in-container derive, same path the launcher
uses at start):

```sh
podman exec -i -e PYTHONPATH=/opt/strata/terminal qwen3.8-flash-next-coder-iq1_m-parallel \
  /opt/strata/terminal/python/bin/python3 -c "
from pathlib import Path
from strata_cli.launch import store, runner
from strata_control import tune_knobs
base=runner.read_config(Path('/data/install/strata-coder-iq1_m.json'))
d=runner.derive_config(base, store.load('docker'), bool_flags=tune_knobs.BOOL_FLAGS)
a=d['args']; print(len(a), [(x,a[i+1]) for i,x in enumerate(a) if 'vram' in x], d.get('max_queue'))"
```

→ `58` derived args (from 41 installed), each vram flag **exactly once** at
`1024`, `duplicates: []`, `--kv-resident 86016`, `--max-context 131072`,
`--layer-split 21`, cache 8192/10/1536/4096 all intact, `max_queue 3 / queue_timeout
90` preserved.

**Activation: the next container start, not now.** Engine args are re-derived only
on the launch path; `strata runtime restart --profile launch-docker --plan` answers
`launch-docker: ready` (nothing to do). Expect roughly 571 CUDA0 slots
(1024 MiB / 1.83, from "the prompt path borrows 1965 CUDA0 cache slots (3.53 GiB)")
and ~504 CUDA1 slots (~2.03 MiB/slot) to go unfree'd as the cost, i.e. free VRAM
moves from 488/892 MiB to ~1024 on each card.

### Verified live after the restart (engine boot 16:22 UTC / 17:22 CET)

Both flags are in the engine's own argv, exactly once each at 1024
(`tr '\0' '\n' < /proc/<engine>/cmdline | grep -c vram-reserve` → 2).

| | before (15:35 boot) | after (16:22 boot) |
|---|---|---|
| CUDA0 expert arena | `700 MiB reserved → 4001 slots` | `1024 MiB reserved → 3873 slots` (−128 slots, −0.23 GiB) |
| CUDA0 free at boot | 675 MiB | 711 MiB |
| CUDA1 free at boot | 1343 MiB | 1343 MiB (unchanged — CUDA1's arena is pinned at 6912 slots / 13.78 GiB, so the later-card reserve costs nothing) |
| free under load | 488 / 892 MiB | 638 / 1254 MiB |
| margin over the 512 guard | **−24 MiB** (it was running *below* the guard) | **+126 MiB** |

The cost is the arena, not the free number: the reserve shrinks the expert arena,
it does not push free VRAM up by the full 1024 (free moved only +150 MiB).

Nothing regressed. Post-boot: **0 WARNING / 0 ERROR**, 9 engine requests,
`major faults` max **0**, KV VRAM hit **99.0%** (was 97.1%), decode **125.9 t/s**
median (was 105.5), drafts 79.5%, reuse ~100%. KV reads from RAM rose to
334 MiB median (was 1.9) — the expected side of a smaller on-card arena; RAM
headroom is enormous here (`MemAvailable` 32.2 GiB, `SwapFree` 32.4 GiB).
Proxy side: 42 requests, all 200, max input 88,598 tokens, no errors.
`max_queue 3 / queue_timeout 90` still declared (lines 67/68 of the run config).

One config difference to note between trees: the coder preset sets
`--conversation-cache-min-tokens 4096` (iq3_s uses 256), so short conversations
never park — the only conversation-cache line since boot is
`skip parking (53 tokens, below the 4096 minimum; parked=0)`, which is benign.

If the margin thins again the next step is **1280** (the iq3_s tree's value),
costing another ~128 CUDA0 slots.

## Not covered / next

- No cancel suite on the coder tree (`parallel-cancel-v1`, `parallel-prefill-cancel-v1`).
- The 131072 context here is uncapped, unlike the iq3_s tree's 98304 cap. Max
  live request through llama-swap so far: 95,262 input tokens (65.3 s), max
  prompt at the engine 113,869. No 400s, and no engine refusal — but the RAM
  wall the iq3_s tree hit at 4×100k has not been probed on this model.
- Numbers for `parallel-overload-v1` c=4 (i.e. never rejecting, all-slots) would
  complete the curve against recovery latency.
