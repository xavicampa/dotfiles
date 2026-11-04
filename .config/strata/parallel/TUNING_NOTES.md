# Strata parallel — tuning notes (qwen3.8-flash-next-iq3_s)

> **Renamed 2026-10-27:** this tree is `~/.config/strata/parallel/` — it used to be `5slot/`, and the llama-swap
> backend `qwen3.8-flash-next-iq3_s-parallel5` is now `qwen3.8-flash-next-iq3_s-parallel`. The slot count left the
> name because it is no longer 5: `-e PARALLEL=4` in `configuration.nix` sets it (§ Where each setting lives).
> Everything written as `5slot/` before that date, here or in the dotfiles NOTES, means this same tree.

> **Everything below was written before the rename.** Commands and paths quoted with the old names
> (`5slot/`, `…-parallel5`) mean this tree and this backend; retype them with `parallel/` and `…-parallel`.

> **This tree is a 2026-10-26 fork of `3slots/` for the `--batch 5` experiment.** Only the deltas below are
> specific to it; everything further down is inherited from the old `3slots/TUNING_NOTES.md` and still true unless
> noted. `3slots/` **was deleted later the same day** (§ Removed: 3slots) — the inherited section at the bottom of
> this file is now the only copy of it, byte-identical to the file that was removed.

## Deltas vs 3slots

- Preset `docker`: `"parallel": "5"` (was "3"); **port stays 5802** — the port the retired 3-slot entry held
  (5801 = 1slot), reused because the exclusive GPU group means only one of them runs at a time. Verified live:
  `ss -ltn` shows 5802 answering `/health` from the `…-parallel5` container, nothing on 5803. The profile edit to
  5803 exists in `strata/profiles/.history/launch-docker/` (19:48:05) but the live profile reverted to 5802; any
  5803 mention below that predates that revert describes 5802.
- Install JSON args are unchanged — `--batch` comes only from the preset's `parallel` field.
- `bench-batch-mtp.py` drives solo/2/3/4/5 streams against **127.0.0.1:5802** and parses `rows` for tok/s/slot.
- Backup of the pre-fork preset: `strata/launch-presets/docker.json.bak-pre-batch5`.

## Why it fits (budget from the 3slots boot 2026-10-26 17:27)

| card | +2 slots cost | where it comes from |
|---|---|---|
| CUDA0 | 2 × 0.40 GiB sessions + 2 × ~50 MiB drafters ≈ 0.9 GiB | `--expert-cache auto` shrinks **5,488 → ~5,050 slots (−8 %)**; free-at-boot stays ≈669 MiB |
| CUDA1 | 2 × 0.22 + 2 × 0.05 ≈ 0.54 GiB | room for experts 17.22 → **~16.68 GiB vs 16.52 needed → residency holds with ~160 MiB slack**; free ≈740 MiB at boot |
| RAM | CUDA0 cache cut pushes ~0.85 GiB of experts into the pinned complement (~28.1 GiB) | MemAvailable 8.8 GiB now; guard floor 2.5 GiB |

## Boot verification checklist (grep the engine log)

1. `--batch: 5 slot sessions on CUDA0 (0.40 GiB each)` and the CUDA1 twin.
2. `expert cache ~5,0xx slots` (smaller than 5,488 is expected; much smaller = trouble).
3. **`CUDA1 runs layers 32-47, expert cache 8192 slots (16.52 GiB), 8192 of its 8192 profiled pairs`** — if N < 8192,
   auto-drop `vision.max_tokens` 1024 → 512 (hands back ~90 MiB), re-check; if still short, go `parallel: "4"`.
4. `lend sizing: ... 3655 ... in RAM too` with **no WARNING** — K==N must survive the cache shrink (STRATA_SPLIT_RING=384).
5. Both `MiB of VRAM free with everything loaded` ≥ 512 (expect ~650 CUDA0 / ~700 CUDA1).
6. Memory guard line + `MemAvailable` ≥ ~3 GiB under load; levers: `--conversation-cache-mib 8192→6144`,
   `STRATA_RESIDENT_HEADROOM_GIB`. **Never lower `--vram-reserve-mib 1024`** (3slots guardrail).

## Expectation

3 streams ≈ 167 agg / 66 per-stream. 5 streams will trade per-stream speed (≈35–38 tok/s expected) for two more
concurrent clients, at −8 % CUDA0 expert cache (the feed-bottleneck side). A/B with the 5-leg bench; if the
CUDA0 cache cut stings, `parallel: "4"` keeps ~half the CUDA1 slack back and costs only ~220 cache slots.

## Measured: batch 5 boot + bench (2026-10-26 17:56 boot, bench 19:0x)

Boot verified against the checklist — **all six items pass, vision stays 1024** (no fallback needed):

- `--batch: 5 slot sessions on CUDA0 (0.40 GiB each)` / CUDA1 `(0.22 GiB each)`; slot sessions take 2.01 GiB on CUDA0.
- `expert cache auto: 10.31 GiB free ... -> 3756` then **`expert cache 5051 slots, 9.31 GiB`** (prediction ~5,050).
- CUDA1: `room for experts 16.67 GiB` and **`8192 slots (16.52 GiB), 8192 of its 8192 profiled pairs`** — residency
  holds, slack ~150 MiB as budgeted.
- `lend sizing: ... borrows 3662 slots ..., 3662 of them keep their experts in RAM too` — K==N, no WARNING.
- Free at boot **CUDA0 665 / CUDA1 708 MiB**; deepest captured window 607/652 — above the 512 floor throughout.
- Pinned complement **28.07 GiB** (predicted ~28.1); guard saw 56.8 GiB at boot, MemAvailable ~8.1 GiB after bench.

Bench (`bench-batch-mtp.py`, 5 legs, medians of 3) vs the 3slots keeper:

| streams | 3slots (batch 3) | parallel (batch 5) | per-stream @parallel |
|---|---:|---:|---:|
| solo | 137.4 / 136.6 | 135.2 | — |
| 2 | 143.7 / 150.2 | 148.7 | — |
| 3 | **163.2 / 167.1** | 161.3 | 53.8 |
| 4 | — (caps at 3) | **166.7** | 41.7 |
| 5 | — | 166.3 | 33.3 |

Window accounting @5: rows 6.79–6.91, **34.1–35.1 ms/window** (vs 26.4–26.6 at 3slots/3-stream), acceptance 75–83 %.
Decode expert cache hit rate under load **78.9 %** (vs 83–89 % at batch 3) — the −8 % CUDA0 cache, visible exactly
where the notes said it would bite (the feed path, not compute).

**Readings:**

- **The aggregate knee is at ~4 streams: 166.7; the fifth stream adds nothing (166.3) and only costs latency**
  (per-stream 42 → 33). Both hit the same ~166–167 tok/s ceiling as 3slots at 3 streams — the box saturates there.
- **A 3-stream client is slightly slower on this tree** (161.3 vs 163–167): the smaller CUDA0 cache is paid
  whether or not five clients show up.
- So parallel is the right preset **when 4–5 concurrent clients are real**; at ≤3 concurrency 3slots remains the
  per-stream keeper — but that tree and its llama-swap entry are gone now, so the fallback costs a restore
  (§ Removed: 3slots). Cheaper first step if 3-stream per-stream speed bothers you: `parallel: "4"` on this tree.
- Untested middle: `parallel: "4"` here (cache would land ~5,270, CUDA1 slack +0.27 GiB) — expected to match
  the 166 ceiling while keeping 4-stream per-stream at ~42; run it only if 5-stream latency actually matters.
- MemAvailable after a full bench: 8.1 GiB — conversation-cache and headroom levers not needed.

## Conversation cache 10 slots / 10 GiB (2026-10-26, **live** since 18:04 boot)

`--conversation-cache-slots 6 → 10`, `--conversation-cache-mib 8192 → 10240`, in **both** `strata-iq3_s.json`
and `strata/launch-presets/docker.json` (backups `*.bak-pre-cc10`). NOT live until the engine restarts.

Flag semantics (`strata --help`): slots = *max parked conversations* (cap only, no RAM); mib = *total pool*
(allocated eagerly at boot — it is part of the 42 GiB `shared`, alongside 28.07 pinned experts + 1.5 exchange
+ ~1 KV); `--conversation-cache-min-free-mib 2560` (default) = parking refuses under that MemAvailable floor.

Sizing constants measured here (engine log `conversation cache:` lines):

- **~29 KiB/token parked** (int8 KV): a 62,420-token pi session parks at **1.66–2.0 GiB** (observed
  `parked 62420 tokens ... bytes=1784280808`); park takes ~0.7 s at that size.
- The pool is shared, `evictions=0` so far — eviction is by pool pressure, not per-slot budgets.
- Proportional scaling (10 × 1.37 GiB ≈ 13.7 GiB, or the old 5120/3 ratio ≈ 17 GiB) **does not fit**: idle
  MemAvailable is 8.0 GiB and the pool is eager; +5.3 GiB would park the machine on the 2560 guard floor.
  10240 (+2 GiB) leaves ~6 GiB available — the engine's floor still decides how many big sessions fit.
- Expected: ~1 GiB average per slot; big pi sessions (>50k tok) fit ~5 concurrent, medium conversations ~10.
  Watch `parked=N ... evictions=M` — if evictions stay 0 the old 8192 pool was already enough.
- Post-restart check (18:04:09 boot): args live, all batch-5 boot lines unchanged (cache 5051, CUDA1 8192/8192,
  lend 3662=3662, free 665/708 MiB); idle **MemAvailable 10 GiB** (better than the ~6 predicted — a fresh
  engine also shed ~3 GiB of old anon/page-cache pressure). Recheck evictions under real multi-session load.
- Restart cost to warn about: reload ~90 s, then this session's 60k-token prefix re-prefills cold at
  ~145 tok/s ≈ 7 min for the first request. To restart: `podman stop qwen3.8-flash-next-iq3_s-parallel`
  (name before 2026-10-27: `…-parallel5`) — llama-swap re-runs the cmd (`--replace`) on the next request to that
  model name.
- Measured cheaper than feared (2026-10-26 19:22:51, `nixos-rebuild switch` restarted llama-swap -> the preload
  re-ran `--replace`): engine healthy on 5802 in **~40 s**, and the next pi request took **62 s**, not 7 min — the
  parked 60k-token prefix survived the container replace. Read the 7-min figure as the *cold-cache* case; a warm
  park makes the restart roughly one reload + one short re-prefill.

## To run it (llama-swap)

Done: the `qwen3.8-flash-next-iq3_s-parallel5` entry lives in `homepc/configuration.nix:375` — the only batched
entry since 2026-10-26 (`-v /home/javi/.config/strata/parallel:/data/install`, `capabilities.context = 131072`).
Requesting that model name through the proxy swaps the group — the gpu group is exclusive, so it evicts whatever
else it has loaded (Maya, the 1-slot tree).

Preload now names this tree: `hooks.on_startup.preload = [ "qwen3.8-flash-next-iq3_s-parallel5" ]`
(`configuration.nix:496`, activated 2026-10-26 19:22; engine healthy on 5802 in ~40 s). Two gotchas:

- Keep it a **single member**. `services.llama-swap.settings` is a submodule, so a module-level override
  **appends** instead of replacing — a draft overlay adding this preload rendered `[parallel5, parallel]`, i.e. two
  boots with the exclusive group evicting the first. Edit the literal in the file, then check the rendered yaml
  (`grep -A4 on_startup` on the `--config=` path in `systemctl cat llama-swap`).
- Preloading 3slots was the old default, so every boot paid a group swap on the first request to `-parallel5`.
- **No boot-warm units exist** (decided 2026-10-26). A transient `strata-boot-warm.service/.timer` pair was used
  briefly that afternoon; it was never in nix, died on the switch, and was deliberately not re-added — preloading
  `-parallel5` boots the model Pi targets, so the boot-time path that produced the wrong context length is closed.
  Watch for the symptom instead: if `/model` reports **262144** for this 131072 engine, llama-swap answered from a
  model other than the loaded one — that is the missing warm request (fix = one small completion after /health,
  re-run whenever the group swaps).

## pi-subagents budget on this tree (2026-10-26, **superseded 2026-10-27** — see § batch 4 + queue back-pressure: the product rule is ≤ 3 now, not ≤ 4)

The consumer that decides how many streams arrive is `~/.pi/agent/extensions/subagent/config.json`:

```json
{ "timeoutMs": 1800000, "checkpointBeforeDeadlineMs": 180000,
  "maxActiveAsyncRunsPerSession": 1, "globalConcurrencyLimit": 4,
  "parallel": { "maxTasks": 12, "concurrency": 4 } }
```

- **Ceiling: 4 children + the interactive parent = 5 streams.** pi-subagents *multiplies* its two knobs —
  `maxActiveAsyncRunsPerSession` (top-level async runs) x `globalConcurrencyLimit` (children **inside one** run).
  The previous `3 x 2 = 6` oversubscribed the 5 slots. Keep the **product <= 4** so one slot stays free.
  1 run x 4 was chosen over 2 x 2 so one `/parallel-review` fan-out gets the box; a second async launch is then
  refused until the first settles (capacity releases on terminal state + process proof, else the 20-min
  `capacity.abandonedSlotReleaseAfterMs` policy).
- **This is the load the preset exists for:** 4 streams = 166.7 agg (the knee), 5 = 166.3. If the child budget goes
  back to <= 3, 3slots is the per-stream keeper again — that tree is deleted, so it is a restore now
  (§ Removed: 3slots); `globalConcurrencyLimit: 3` on this tree is the cheaper first move (161.3 agg / 53.8 each).
- **`timeoutMs` tracks the per-stream drop, not the slot count.** 135 -> 41.7 tok/s at 4 streams is 3.2x slower
  decode, so the old 900000 killed a child that finished solo in 5 min. Now 1800000, with
  `checkpointBeforeDeadlineMs` 180000 so the checkpoint steer can still write its report at 33-42 tok/s.
- **Pi settings paired with it** (`~/.pi/agent/settings.json`): `httpIdleTimeoutMs: 900000` bounds one model
  response, which must cover a cold 60k re-prefill (~7 min at 145 tok/s); `modelThinkingLevels` and the
  `models.json` `modelOverrides` entry both need the exact model name — `-parallel` since the 2026-10-27 rename,
  `-parallel5` before it — and the sibling overrides do **not** carry over to a newly discovered model name, so the
  session silently runs at the `medium` default. Both were renamed with the backend (`settings.json.bak-pre-rename`,
  `models.json.bak-pre-rename`).
- **Do not point agents at another group member.** Children inherit the parent model (`…-parallel`) by default;
  setting `subagents.defaultModel` or an agent's `model` to the single-stream `qwen3.8-flash-next-iq3_s`, the 262k
  name or Maya evicts this engine through the exclusive gpu group on that child's launch. (Until 2026-10-26
  `-parallel` was a *different* entry, since removed; the name is the live batch one now — this warning used to say
  the opposite.)
- Workflow scripts may pass their own `globalConcurrencyLimit` per call (workflow-only, not forwarded to child
  calls) — a script asking for 8 lanes oversubscribes the engine. Pass ≤ 3 explicitly.

## VRAM margin + conversation-cache sizing (2026-10-27 ~13:20, **LIVE since the 13:29 restart**; superseded on context/floor by § the RAM wall)

Log review of the live load (12:50-13:05, 69 proxy requests, all 200, zero 429s, max 6 in flight vs
`admission_limit 7` — the 4+3 bound never engaged). Two findings became these two edits:

1. **`--vram-reserve-mib` 1024 -> 1280** (preset `extra`; `--vram-reserve-later-mib` left at 1024). The WARNING
   this boot: `only 505-509 MiB of VRAM free at the start of this request (below 512 MiB) … decode falls to a few
   tok/s and a window may never finish (#2065). Add --vram-reserve-mib 1088 …`. Sizing it from the log rather than
   from instinct — dip = (free with everything loaded) − (the number in the warning), per boot:

   | batch | free w/ everything loaded | warnings | worst dip | free needed for the 512 guard |
   |---|---|---|---|---|
   | 4 (now) | 667 / 998 | 3 (505-509) | **162 MiB** | 674 → we were **7 MiB short** |
   | 5 (old) | 665 / 708 | 7 (to 247) | 418 MiB | — |
   | 3 (old) | 246-869 | 28 | 23 MiB | — |

   So +256 MiB is the answer: free goes 667 → ~923, i.e. 411 MiB above the guard, enough to swallow even the
   418 MiB dip the 5-slot setup produced. **1536 (+512) was excessive and was walked back** — that margin has never
   been used, and the flag is setup's "VRAM kept free for other programs: the experts' share is set lower"
   (`setup.py:7500`), so margin is bought with expert residency: CUDA0's arena is 9.72 GiB / 5270 slots = 1.88 MiB
   per slot, so +256 MiB ≈ 136 slots (2.6%), where +512 was ~272 (5.2%) against a hit rate already at 70.6%. The
   engine's own suggested 1088 (+64) clears the one request it measured with only 57 MiB to spare — too thin.
   Deliberately **not** raised on `--vram-reserve-later-mib`: CUDA1's arena is the tuned win (8192 of its 8192
   profiled pairs resident), and shrinking it is a decode cost, not a margin.
   **Check at the next boot:** CUDA0 free should go up ~256 MiB (667 -> ~923) and CUDA1 must keep
   `8192 of its 8192 profiled pairs` + ~998 MiB free. If CUDA1's residency drops, the flag reached the wrong card —
   revert the preset value (one line).
2. **`--conversation-cache-mib` 10240 -> 6144 and `--conversation-cache-slots` 10 -> 6** (both the run config args
   and the preset `extra`, kept identical so nothing disagrees). The cache was **RAM-admission bound**, not
   budget-bound: 10 `skip parking (physical RAM admission; need 1328 MiB plus 2560 MiB floor, 3885 MiB available …
   evicted 7, 0 still parked)` in 15 min, 23 this boot, 208 cumulative evictions, and the parked count rode to the
   10-slot ceiling then collapsed — 28 sawtooth flushes in 347 requests. `MemAvailable` is ~4.5 GiB (engine RSS
   50.6 GiB of 62, Shmem 40.5 GiB = 27.66 GiB expert RAM tier + parked snapshots at ~0.92 GiB per 45-50k-token
   conversation; swap 2.6 GiB used, PSI 0.00), so a 10 GiB budget over 10 slots can never fill and admission
   flushes the whole cache instead of evicting LRU. Cost measured: **545k cold tokens = 297 s of prefill** in that
   window (191.5 s of it in one 15-request stretch), including three fully cold prefills of 95-114k tokens at
   ~1.9-2.1k tok/s = 152 s; reuse 80.7% vs 90.6% the previous window, recovering to 98.8% as the cache refilled.
   6144 MiB / ~1 GiB per snapshot = 6 conversations, and 6 also covers the real session count (4 slots + 3 queued,
   and Pi is 4 conversations). Engine default is 4 slots / up-to-8192 MiB (`--help`), so 6/6144 is mid-range, not exotic.
   Left alone: `--conversation-cache-min-free-mib` (the 2560 MiB floor is the safety, and lowering it trades evictions
   for swap).

Backups: `strata-iq3_s.json.bak-pre-cc-cache`, `strata/launch-presets/docker.json.bak-pre-cc-cache`.
Verified by dry-running the launcher in the container (`derive_config(install config, preset)`):
`--vram-reserve-mib 1280`, `--vram-reserve-later-mib 1024`, `--conversation-cache-mib 6144`,
`--conversation-cache-slots 6`, 29 engine flags intact, `max_queue 3 / queue_timeout 90` still carried.

**These need a real start, not a runtime restart:** `strata runtime restart --plan` says `changed: false` because it
diffs the profile revision and the sha256 of the *derived* state file, and the tree edits are only re-derived by
`strata launch` at start. A plain container restart applies all of it — including `--parallel 4` and the queue
bound — with nothing to re-apply. Re-measure afterwards with `python3 /tmp/logscan.py 75` (reuse %, cold-prefill
seconds, skip-parking count, parked series).

## Post-restart verification + a silent engine bump (2026-10-27 ~21:57, live)

The switch recreated the container and `--pull newer` brought **engine 0.1.52** (was 0.1.48 for the whole tuning
history in this file). All 30 tuned flags parsed, no unknown/deprecated warnings, no WARNING/ERROR lines in the boot
or the ~60 requests since. Boot checklist, new numbers:

| line | 0.1.48 @ reserve 1024 | 0.1.48 @ reserve 1280 | **0.1.52 @ 1280 + ctx 98304** |
|---|---|---|---|
| CUDA0 expert cache | 5270 / 9.72 GiB | 5134 / 9.47 GiB | **5226 / 9.64 GiB** |
| CUDA1 expert cache | 8192 / 16.52, 8192 of 8192 pairs | same | **unchanged** |
| slot sessions CUDA0 | 0.40 GiB each, 1.61 total | 0.40 / 1.61 | **0.36 / 1.45** (context cap) |
| KV resident | 20480 of 131072 cells, 1.03 GiB pinned | same | **20480 of 98304, 0.77 GiB pinned** |
| conv-cache RAM floor | 2560 (default) | 2560 | **1536** (memory guard line says `floor 1536 MiB`) |
| free at boot | 667 / 998 MiB | 925 / 998 | **922 / 1108** (live under load 839 / 1019) |

Measured over the 60 requests after the restart, against the 100 before it — this is the payoff for the context cap +
floor change, and it is bigger than expected:

    reuse            80.8% -> **95.9%**   (cold tokens 1,085,439 -> 147,644)
    KV VRAM hit med  56.5% -> **96.8%**
    decode tok/s med 72.2  -> **117.3**   (max 153.7)
    expert hit med   68.8% -> **80.5%**
    conversation cache: parked 2, **evictions 0**, skips 1 (53 tokens, below the 256 minimum - benign)
      the parked series no longer wipes to zero: [1,2] vs [1,2,3,4,5,1,2,3,4,5,1,2,3,4] before
    drafts accepted 82.1%; MemAvailable 3.8 -> **12 GiB**; WARN/ERROR 0; 58 requests, all 200,
      peak overlap 4, no 429, telemetry `admission_limit 7 / queue_timeouts 0`
    llama-swap `/v1/models` now advertises `context_window: 98304` for this model (nix `capabilities.context` live)

Watch items, not fixes: **major faults 4 -> 336** in the window (expert mmap page-cache pressure; OS MB read med
141 -> 127, so it is faults not volume), and CUDA0 now sits 327 MiB above the 512 guard instead of the 411 the
reserve change was sized for — the new engine fits 92 more slots than the old one at the same reserve. Observed
dips since boot are small (922 -> 839 under load, verify windows 922 -> 912). If a CUDA0 `only N MiB of VRAM free`
warning appears, the fix is `--vram-reserve-mib 1408`, not a batch change.

**Hazard worth deciding on:** `--pull newer` in the nix cmd means the engine can change under a rebuild, and it just
did — every number in this file was measured on 0.1.48. Nothing broke, but a re-run of the steady-state curve
(`bench-cc-curve.py`) and `parallel-overload-v1` on 0.1.52 is worth doing before trusting old margins; and if
reproducibility matters more than free upgrades, pin the image by digest.



## 4 x 100k conversations: the RAM wall, and the context cap (2026-10-27 ~15:10, **LIVE since the 21:57 restart** — measurements above)

A second parallel review (this one with 60-100k-token conversations, `prompt med 63,676`, `max 101,297`) broke the
conversation cache again, and the numbers say my 6144/6 sizing was wrong for this shape:

    skip parking (physical RAM admission; need 1355-2257 MiB plus 2560 MiB floor, 3598-4495 MiB available,
      source meminfo; evicted 0-4, 0 still parked)        x10 in 80 request blocks
    parked series: 4,5,1,2,3,4,5,6, 1,2,3,4, 1,2,3,4, 1,2,3,4     <- rebuilt, wiped, rebuilt, wiped
    prompt 100544 cold 100544 prefill 47.3 s      prompt 96545 cold 96545 prefill 48.8 s
    (the four 98-101k requests that stayed warm: cold 1, prefill 0.4 s)

**Snapshot cost scales with conversation size, not slot count.** `park tokens med 58,913` -> **1.4-2.3 GiB per
snapshot**, so 6 slots x ~2 GiB = 12 GiB of demand against `MemAvailable ~4.0 GiB - 2560 MiB floor = ~1.4 GiB` of
real headroom: at most ONE big snapshot fits, and the engine flushed the whole cache instead of evicting LRU. The
0.92 GiB I sized from earlier assumed ~45-50k conversations. Reuse fell to 85.4% (716k cold tokens) from 87.7%.

Underneath it, RAM is structurally oversubscribed at 4 x 128k: `Shmem 43.2 GiB` (expert RAM tier 27.9 GiB + pinned
KV + snapshots ~ 15 GiB, i.e. ~3.5 GiB per 128k slot), engine RSS 52.3 GiB (HWM 55.9) of 62.3 GiB, MemAvailable
3.8 GiB, swap 1.4 GiB used, memory PSI avg10 0.00 (admission control is refusing correctly, nothing is stalling).
VRAM follows the same pressure: free 662 / 616 MiB (CUDA1 only 104 MiB over the 512 guard), KV VRAM hit 59.1%
median (was 98%) with 23.5 GiB of KV streamed from RAM in one request, KV copy-in 207 ms med / 579 max.

**Applied (three layers, one truth): `--conversation-cache-min-free-mib 1536` (new; engine default 2560) and
`--max-context 131072 -> 98304`** — the context cap goes in the run-config args, the preset `extra` (the layer that
wins; `apply_to_argv` deletes the base flag so the derived argv carries it exactly once) **and** the preset
`"context"` (never reaches argv, but it is the reuse-test half — mismatch it and setup rewrites the run config).
The floor change buys ~1 GiB of usable parking headroom - enough for one big snapshot plus a mid-size one - with
swap 30 GiB free and PSI 0.00 as the safety net. The context cap is the engine's
own advice (`lower --max-context / --batch`) and attacks both walls at once: pinned KV and snapshots shrink ~25%
(~3-4 GiB back) and CUDA1's margin stops shrinking. Not applied: cache slots/budget (still 6/6144 - with the floor
lowered and the context capped, ~1-2 snapshots is the real capacity and LRU now governs it), and
`--vram-reserve-later-mib` (raising it would drop CUDA1 below its 8192 profiled pairs; no CUDA1 warning has fired).

**Two more places carry the same number, and neither is an engine arg:** llama-swap's
`capabilities.context = 98304` in `configuration.nix` (advertised as `context_window` / `context_length` / `n_ctx`
for **every** model, loaded or not; it was still 131072, so the router promised a context the engine would refuse —
needs a nix switch), and pi's
`modelOverrides["qwen3.8-flash-next-iq3_s-parallel"].contextWindow = 98304`.

**Correction (2026-10-29): that pi pin is redundant — pi does discover the context.** It discovers it from
llama-swap's advertised `context_window`, not from the engine. Proof: the solo `qwen3.8-flash-next-iq3_s` entry has
**no** `contextWindow` override at all and the session runs the full 262144. What I read as "101k prompts went
through" was 101k < the then-advertised 131072. The **128000 default in `docs/models-configuration.md`** belongs to
`models` entries declared in `models.json`, not to models discovered over `/v1/models`. And `modelOverrides`
*replaces* the discovered field, so a stale pin now **hides** the real cap: keep it only where pi must use less than
the router advertises, otherwise delete it rather than let it drift. With 98304 and the default
`reserveTokens 16384`, pi auto-compacts above **81,920** tokens (245,760 on the solo tree). Re-read at pi start, so
a running session keeps whatever number it already had.

Backups: `strata-iq3_s.json.bak-pre-ctx98k`, `strata/launch-presets/docker.json.bak-pre-ctx98k`,
`~/.pi/agent/models.json.bak-pre-ctx98k`. Verified by dry-running `derive_config` against **both** bases (installed
run config and the state file): 30 engine flags, `--max-context x1 = 98304`,
`--conversation-cache-min-free-mib 1536`, cache 6144/6, reserve 1280/1024, `max_queue 3 / queue_timeout 90`.

**Careless-mistake note (mine):** editing the args array, `args.index('--max-context')` is the *flag* index; I wrote
the new value over the flag name and left `131072` orphaned. The derive dry-run caught it (`--max-context (absent)`);
restored from `bak-pre-ctx98k` and re-applied at index+1. Always dry-run `derive_config` after touching args.

## batch 4 + queue back-pressure (2026-10-27, **LIVE** — `--batch 4`, `max_queue 3`, `queue_timeout 90`)

### Where each setting lives — declarative (2026-10-27; supersedes the CLI recipe I used first)

Two container restarts silently reverted my `strata profile set` edits: `launch/runner.py:ensure_profile`
replaces the saved profile's whole override set with exactly `host port parallel`, taken from the preset
("the overrides are replaced as a set"). So the settings now sit where the box regenerates them — full write-up
in the dotfiles NOTES § llama-swap/strata-parallel:

| knob | file | mechanism |
|---|---|---|
| slots | `~/.config/nixos/homepc/configuration.nix` (batch entry, key `…-parallel`): **`-e PARALLEL=4`** | entrypoint → `--parallel 4`, which overrides the preset at start *and* writes it back (`--save-preset`). § pi-subagents-era notes already called editing the preset alone "futile" |
| `parallel` in the tree | `strata/launch-presets/docker.json` → `"parallel": "4"` | kept in sync so `strata launch --list-presets` reads honestly (`4 requests`) |
| `max_queue`, `queue_timeout` | `strata-iq3_s.json` (this tree) → top-level `"max_queue": 3`, `"queue_timeout": 90` | `serve/server.py` falls back to `cfg.get("max_queue")` / `cfg.get("queue_timeout")`; `derive_config` opens with `json.loads(json.dumps(base))` (deep copy of the **installed** run config) and replaces only `host port api_key drafting exe open_browser log cards mtp args env`, so extra top-level keys survive every start. There is no launch flag or env for these: `STRATA_SET`/preset `extra` reach engine argv only |

Proved without touching the live engine — in-container `derive_config(install config, preset)` returned
`max_queue 3 / queue_timeout 90` with all 29 tuned engine args intact.

**`strata profile set` + `strata runtime restart --profile launch-docker` is a hotfix, not a setting.** It does
go live inside a running container (guarded by the `--if-profile-revision/--if-owner-id/--if-instance-id` ids from
`--plan --output json`; measured live: `admission_limit 7`, one 429 at c=8, `queue_timeouts 0`), but a profile
holding values the tree does not is a second source of truth that the next container start erases. The profile is
left at the launch-derived revision `47e97cdb5e924d68` (`host port parallel:4`); the queue lives in the tree file.

**Status: both live since 2026-10-27 12:09** (system switch done, and the tree/entry were renamed
`5slot` → `parallel` / `-parallel5` → `-parallel` in the same change — see the rename note at the top and the dotfiles
NOTES § llama-swap/strata-parallel for the podman-name trap that had to be cleared first). Verified after the
switch: container `-v /home/javi/.config/strata/parallel:/data/install`, `-e PARALLEL=4`, `admission_limit 7`,
`parallel-overload-v1` at c=8 → one 429 and `queue_timeouts 0` (`/data/bench/2026-10-27-rename-check`). Nothing
left to re-apply after a restart. Backups: `strata-iq3_s.json.bak-pre-cc4`, `launch-presets/docker.json.bak-pre-cc4`,
`profiles/launch-docker.json.bak-pre-cc4`, `~/.pi/agent/extensions/subagent/config.json.bak.pre-cc4`.

Live values (`strata runtime restart ... --output json` → instance `8e0c3703ed2749abb65178745c27460b`,
profile revision `4a0d15207ec1e839`): serve `--parallel 4 --max-queue 3 --queue-timeout 90.0`, engine `--batch 4`,
telemetry `slots_effective 4`, **`admission_limit 7`** (= slots + max_queue).

### Boot checklist at batch 4 (verified 2026-10-27 11:4x, cheaper than 5 slots as predicted)

`--batch: 4 slot sessions on CUDA0 (0.40 GiB each)` + CUDA1 twin; **expert cache 5270 slots** (5051 at 5 slots —
the freed slot feeds the cache, matching the 5,270 prediction); CUDA1 still `8192 slots (16.52 GiB), 8192 of its
8192 profiled pairs` (residency holds); `lend sizing: the prompt path borrows 3657 slots … 3657 of them keep
their experts in RAM too` (N == N, no WARNING); **667 / 998 MiB free with everything loaded** (665 / 708 at 5
slots). Also relevant: the old 5-slot boot logged repeated
`WARNING: only 179/249/379/509 MiB of VRAM free at the start of this request (below 512 MiB)` (#2065) during
traffic — 5 slots was running inside the paging guard, another reason 4 is the right setting here.

### Steady-state curve at batch 4 (300 tok/stream, temp 0, medians of 3 rounds — `bench-cc-curve.py 1 2 3 4 5 6 7`)

| streams | agg tok/s | med/stream | min/stream | med TTFT | max TTFT |
|---|---|---|---|---|---|
| 1 | 144.3 | 144.3 | 93.9 | 0.00 s | 0.01 s |
| 2 | 154.9 | 77.9 | 70.6 | 0.00 | 0.01 |
| 3 | 169.8 | 57.2 | 53.2 | 0.00 | 0.01 |
| **4** | **179.3** | **45.0** | **41.5** | 0.00 | 0.01 |
| 5 | 150.2 | 37.9 | 27.4 | 0.01 | 0.02 |
| 6 | 143.5 | 33.2 | 23.8 | 0.00 | 0.01 |
| 7 | 143.1 | 31.0 | 19.9 | 0.01 | 0.01 |

**What the queue bound does and does not buy.** It fixes the tail-TTFT pathology: at 7 concurrent, TTFT stays
≈0.01 s, where the unbounded batch-5 mixed suite measured p95 2.88 s at c=8 and 7.03 s at c=16. It does **not**
protect aggregate: 5 streams still costs 179 → 150 tok/s and 6–7 settle ≈143, because a queued conversation is
rotated into a slot as soon as one frees (the `slot takes N tokens (copied in ~116-120 ms)` / `gave back ~47 ms`
churn plus MTP acceptance loss), so oversubscription past slots is still pure loss. The bound's real value is
the hard ceiling: 8 clients got `peak_active 7 / occupied_slots 4` and **one HTTP 429**, `queue_timeouts: 0` —
vs batch 5 unbounded where 16 clients all got absorbed (`active 16, queued 0`) and dragged everyone down.
Keep the operating point at **≤ 4 streams**, i.e. **3 subagent children + 1 parent**.

### Suites now unlocked (both passed 2026-10-27)

- `parallel-overload-v1` c=8: **passed** — `peak_active 7`, `peak_admission_rejected 1` (429), `queue_timeouts 0`,
  recovery phase back to 1 stream at 52 tok/s.
- `parallel-cancel-v1` c=5: **passed** — `client_disconnect_cancels 2`, no queue timeouts, recovery 47.8 tok/s.
- `parallel-prefill-cancel-v1` (ran earlier at batch 5): recovery TTFT 0.50 s.
- `peak_queued` reads 0 even when the queue was used: samples are ~1 s apart and a queued request here waits far
  less than that. Trust `admission_limit`, `admission_rejected` and `peak_active` instead.

### pi-subagents budget at 4 slots

`~/.pi/agent/extensions/subagent/config.json`: `globalConcurrencyLimit: 3`, `parallel.concurrency: 3`
(backup `config.json.bak.pre-cc4`); `maxActiveAsyncRunsPerSession: 1` × 3 = 3 children + parent = 4 = slots.
A workflow script passing its own `globalConcurrencyLimit` must pass ≤ 3. At 8+ children the old config measured
152.0 agg / 19.4 each; the product ≤ 3 rule keeps every stream in the 45 tok/s band.

## Removed: 3slots (2026-10-26)

Deleted once the pi-subagents budget moved to 4 children: the bench says parallel ties 3slots' best aggregate
(166.7 vs 167.1) and a tree nobody routes to is just a third thing to keep in sync. What went:

| Removed | Where |
|---|---|
| engine tree | `~/.config/strata/3slots/` — install JSON, `strata/launch-presets/`, `bench-batch-mtp.py`, its `TUNING_NOTES.md` |
| llama-swap model | `configuration.nix`: the `"qwen3.8-flash-next-iq3_s-parallel"` entry **and** its `routing.router` gpu-group member |
| Pi overrides | `settings.json modelThinkingLevels` + `models.json modelOverrides` for `qwen3.8-flash-next-iq3_s-parallel` |
| container | `podman rm qwen3.8-flash-next-iq3_s-parallel` (it was exited, not running) |

Checked clean (no reference to the name): `~/.pi/agent/extensions/local-models.json` VRAM tiers, `common.nix`,
`dell/`, home-manager, `~/.pi/agent/scripts`, `~/.local/bin`, `~/.agents`. llama-swap's `activity.sqlite` still has
historical rows for the model — harmless, it only tracks what has been served.

**Restore recipe** — every piece below is still on disk today, so this is a re-wire, not a reconstruction:

1. `cp -r ~/.config/strata/parallel ~/.config/strata/3slots`
2. In `3slots/strata-iq3_s.json`, revert the two args the deleted install JSON differed by:
   `"--conversation-cache-mib", "10240"` → `"8192"` and `"--conversation-cache-slots", "10"` → `"6"`.
3. `cp 3slots/strata/launch-presets/docker.json.bak-pre-batch5 3slots/strata/launch-presets/docker.json` — that
   backup **is** the old 3-slot preset verbatim (`"parallel": "3"`, `"port": 5802`; only `last_used` differs).
4. Re-add the llama-swap entry (copy the batch block — key `qwen3.8-flash-next-iq3_s-parallel` — at
   `configuration.nix:375`, change the `-v .../parallel`
   mount to `.../3slots`) **and** the same name in `routing.router`'s gpu `members` — forgetting the member is the
   classic "model not found" after a restore. Set `hooks.on_startup.preload` to whichever tree should boot.
5. Build, then `sudo nixos-rebuild switch --store-path <built path>` (edit literal lists; the submodule appends).
6. Pi: re-add the `modelOverrides` + `modelThinkingLevels` entries under the exact model name, or Pi advertises it
   with no thinking support and runs it at the `medium` default.

---

# Strata 3slots — tuning notes (qwen3.8-flash-next-iq3_s)

> **The `3slots/` tree was deleted 2026-10-26** (§ Removed: 3slots above has the restore recipe). This section is
> the only surviving copy of those notes; paths and the port below refer to the restored layout, not to anything
> currently on disk.

Box: RTX 5070 Ti (CUDA0, 15.92 GiB) + RTX 3090 Ti (CUDA1, 23.99 GiB), 62 GiB RAM.
Engine 0.1.48 linux-x86_64-cuda-cuda13. Container `qwen3.8-flash-next-iq3_s-parallel`, port 5802, preset `docker`.
Model pack `IQ3_S`; 48 layers, **512 expert pairs per layer**, CUDA1 expert-cache cost ≈ **2.11 MiB/slot**, CUDA0 ≈ 1.94 MiB/slot.

Measure with: `python3 ~/.config/strata/<tree>/bench-batch-mtp.py` (solo / 2-stream / 3-stream medians,
plus the engine's own `strata batch:` window accounting). The parallel copy of that script targets 5802 and runs
solo + 2/3/4/5 streams every round (no stream-leg arguments; `--batch-mtp` / `--no-mtp` only set the warning line).

## Current best config (2026-10-25, "leg C")

Live and durable in both `strata-iq3_s.json` and `strata/launch-presets/docker.json`:

```
--max-context 131072   --kv int8   --kv-resident 20480
--layer-split 32       --pcie-frac 0.00
--resident-experts     --adapt-async 1 --adapt-every 1 --adapt-swaps 160 --adapt-decay 0.97
--batch 3 (preset "parallel": 3)   --batch-mtp   --spec 4 --spec-min-p 0.70 --mtp rt
--vram-reserve-mib 1024 --vram-reserve-later-mib 1024 --trim-stage-weights
--conversation-cache-mib 8192 --conversation-cache-slots 6
--conversation-cache-park-gain 2048 --conversation-cache-min-tokens 256
```

Result: solo **137.4 / 136.6** · 2 streams **143.7 / 150.2** · 3 streams **163.2 / 167.1** tok/s.
CUDA0 expert cache 5,558 slots (10.25 GiB), CUDA1 8,192/8,192 pairs (16.52 GiB, 100 % resident).
Free VRAM: CUDA0 545 MiB at reserve 896, CUDA1 1,376 MiB. `MemAvailable` ≈ 13 GiB under load.

**Reserve: 1024 is the keeper** (same value as the committed `2026-10-22-standard-rtx-5070-ti-plus-rtx-3090-ti`
config for this GPU pair). Measured CUDA0 readings: 896 → 545 MiB idle but **475 at request start**; 960 → 605 idle
but **505 at request start** — 7 MiB under the engine's 512 MiB floor (`#2065`). CUDA0 expert cache along that path:
5,558 (896) → 5,525 (960) → ~5,490 (1024) — still **+212 over the 5,278 baseline**, because `--kv-resident 20480` is
what frees the VRAM; the reserve only decides whether the warning fires.

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
- **`--spec-min-p` must match in both files.** The install config carried `0.5` while the preset carried `0.70`; the
  preset's args come later in the command line so it wins, but launch straight from the install config and you get
  the looser gate silently. Both are `0.70` now.
- **`STRATA_SPLIT_RING=384` (container env, set in `homepc/configuration.nix` for the 3-slot entry).** On a split the
  prompt path lends tail slots of each card's cache; the default rule gives 96 ring slots once ≥75 % of pairs are
  cache-resident, i.e. `borrows 2918 slots`. The override sets ring 384 → `borrows 3655 slots (ring 384 slots at chunk
  8192), 3655 of them keep their experts in RAM too` — K == N, so the `lend sizing` WARNING does not fire and long
  prompts read no experts from the model file. Cost: the RAM copy grows to ~27.3 GiB from ~26.2. Check this line after
  any split/cache change: if K < N, every prompt chunk re-reads N−K experts from disk.
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
  window may never finish (#2065)`. Settled at `--vram-reserve-mib 1024`: 896 read 475 and 960 read 505 at request
  start, both under the floor. If it ever warns at 1024, lower `--max-context` or `--batch` — not the reserve.
- `--kv-resident` minimum is **20480**; a context ≤ N cells is not streamed.
- CUDA1's cache is **profile-capped** at split 32: it already holds all 8,192 profiled pairs, so its ~1.4 GiB of
  free VRAM cannot be spent on experts. Raising `--kv-resident` back toward 32768 spends CUDA1 VRAM but *removes*
  CUDA0 expert slots — the opposite of what leg C measured.
- **Vision: `vision.max_tokens` 1024** (2026-10-26; was 512). It is the stock GPU default — `setup.VISION =
  {"gpu": {"max_tokens": 1024, "reserve_mib": 700}, "cpu": {...300}}` and `serve/server.py Vision.DEFAULT_MAX_TOKENS` —
  and nothing caps it above that: `Vision.token_limit()` passes the key straight to `strata-vision --max-tokens N`
  (`0` = unlimited); setup only notes "more than the encoder's default needs more VRAM and context per picture".
  The knob lives **only** in `strata-iq3_s.json` (the preset carries just `"vision": "on"`); the launcher copies the
  whole section into `state/strata/launch/docker.json`, which is where the reader's args come from.
  Measured here (3840×2160 screenshot, one request): image tokens **482 → 1,010** (`usage.prompt_tokens` 498 → 1,026,
  text-only baseline 16), CUDA1 **free VRAM 1,372 → 1,288 MiB** at start (−84 MiB), CUDA1 still `8192 of its 8192
  profiled pairs`, CUDA0 unchanged (669 MiB free, cache 5,488 slots), no VRAM warning, decode unaffected. The reader is
  a separate process on CUDA1 (`vision.cuda_device: 1`); the room the engine reports for CUDA1 experts read 17.31 →
  17.22 GiB, still above the 16.52 GiB its 8,192 resident pairs need, so residency is untouched.
  Above 1024 the same math applies (2,048 ≈ 2× linear resolution over 512), but check the `CUDA1: N MiB free with
  everything loaded` line again; the floor is 512 MiB at request start. Raising the cap does not upscale anything —
  it only lifts the ceiling on how big a picture may become, so it does nothing for a client that downsamples first.
- Watch `MemAvailable` (≈12–13 GiB under load): pinned footprint is ~27.3 GiB experts (including the 3,655 lend
  slots kept by `STRATA_SPLIT_RING`) + ~1.0 GiB K/V. Levers if it tightens: `--conversation-cache-mib`,
  `STRATA_RESIDENT_HEADROOM_GIB`, `STRATA_SPLIT_RING`, context, batch slots.

## Revert points

| file | restores |
|---|---|
| `strata-iq3_s.json.bak-pre-vision1024` | vision `max_tokens` 512 (everything else current) |
| `strata-iq3_s.json.bak-pre-reserve960` + `strata/launch-presets/docker.json.bak-pre-reserve960` | the reserve-896 and reserve-960 legs (kv-resident 20480, split 32) |
| `strata-iq3_s.json.bak-pre-legC` + `strata/launch-presets/docker.json.bak-pre-legC` | baseline leg (split 32 / kv-res 32768 / reserve 1024) |
| `*.bak-pre-split31` | pre-split-experiment (same as baseline leg) |
| `*.bak-pre-batch-mtp` | before `--batch-mtp` |
| `*.bak-pre-adapt-kv` | before `--adapt-async` / `--kv-resident` / `--kv int8` |
| `*.bak-int8-262k` | 262,144 ctx + int8 KV, no resident experts |

Config edits must go in **both** `strata-iq3_s.json` and `strata/launch-presets/docker.json`; the launcher
regenerates `state/strata/launch/docker.json` from the preset, so preset `extra` entries are authoritative
(boolean flags as `"--flag": "on"`). Restart is required for changes to go live.

## 0.2.9 (engine 0.1.55) A/B on iq3_s — measured 2026-10-31 (eras 177246 live-before · 177506 B · 177896 G · 178293 P*
· 178677 P2 · 179053 B2 accepted; P* invalid — 11 keys, two knobs)

**Accepted arm: no `env` key in `strata-iq3_s.json`** — i.e. 0.2.9's defaults, the nine parallel settings **on** and
`STRATA_GDN_TC=1`/`STRATA_GDN_CONVL2=2` **on**. Live boot after acceptance (`.tune/B2-all-on.era`):

```
layer split: CUDA1 runs layers 32-47, expert cache 8192 slots (16.52 GiB), 8192 of its 8192 profiled pairs; slot 0 verified
layer split: 54% of the experts resident, the prompt path's streamed ring 384 slots
1177 MiB of VRAM free with everything loaded
CUDA1: 1106 MiB of VRAM free with everything loaded
```

Identical across every arm of this A/B — `8192/8192` pairs, 1177/1106 MiB free, 54 % resident, no `LOW`/`WARNING`,
acceptance 83.7-86.1 %, `drafts/step 6.1-7.2`. So all three stacks are free of VRAM/residency cost on this arm.
(Note line "expect ~650 CUDA0 / ~700 CUDA1" is stale: with 0.1.55 + these args the boots report 1177/1106, and the
`strata verify` capture windows only fall to 1098.)

**Hygiene check (the coder tree needed this): this tree was NOT damaged by the 0.1.55 regeneration** — `max_queue 3`,
`queue_timeout 90`, `vision.cuda_device 1` all still in `strata-iq3_s.json`, and the preset has no `user_args` key at all
(schema here is `extra`, not `args`), so there is no stale-args copy to trip over. Compute apps confirm the split: the
engine's 21.8 GiB row on the 3090 Ti, its 14.8 GiB row on the 5070 Ti, and **vision's 1336 MiB row on the 3090 Ti only**.

### The nine parallel settings: **+8-11 % fan-out at 4 concurrent, nothing at 1** — keep on

`bench-util.py --levels 1 4 --rounds 3 --max-tokens 400` on the engine port (5803) + engine id, arms alternated:

| arm | level 4 `agg tok/s` (12 streams of 400) | level 1 `med/stream` |
|---|---|---|
| nine ON (B 182.9, G 183.4, B2 179.0) | **179.0-183.4, n=3 boots** | 130.2-146.6 (drift band) |
| nine OFF (P 165.2, P2 165.6) | **165.2-165.6, n=2 boots** | 142.8-148.6 |

**+8.1 to +11.0 %** for the stack at full batch, no overlap between arms, and it reproduces the coder tree's +7 %
(see `../coder/TUNING_NOTES.md`) on a different quant and a different batch width. Solo (level 1) again shows nothing
reliable — the boot-to-boot band (130-149) is wider than any arm effect. Judge fan-out only on `agg`.

### Gated DeltaNet (`STRATA_GDN_TC`/`GDN_CONVL2`): **keep ON here, +1.5-2.5 % on 14K prompts**

Judged on cold reads only (`reused = 0`, band 10-20K, unique nonce prompts so the conversation cache cannot reuse them):

| arm | 14.1-14.3K cold read tok/s | med |
|---|---|---|
| GDN ON (B, B2, P2) | 3249, 3285, 3287 | **3285** |
| GDN OFF (G, P) | 3200, 3236 | 3218 |

Same sign as the coder tree (+1.5 %), so the upstream note that "GDN TC does not pay on iq3_s" (their 1slot tree)
**does not hold on this box**: on 3090 Ti + 5070 Ti the tensor-core path is worth ~2 % on long prompts and costs
nothing at decode. If a future release flips the default off, put `STRATA_GDN_TC=1`/`STRATA_GDN_CONVL2=2` in the run
config `env` to keep it. Both effects are small enough that this is a keep-the-default call, not a sweep-worthy knob —
do not re-measure unless the engine package changes.

### Not tested (open, with the arithmetic so it stays cheap to decide)

`--batch 5` was **not** re-tested under 0.2.9, and it is not a one-knob change: this preset has no `extra.--batch`;
the engine's `--batch 4` is derived from the preset's `parallel: 4`, which also drives serve `--parallel 4
--max-queue 3`. Raising it moves queue/back-pressure at the same time (the § "batch 4 + queue back-pressure" product
rule is ≤ 3 concurrent sessions), and while CUDA1's cache is profile-capped at 8192 pairs (its free space cannot become
experts), a 5th slot session costs CUDA0 ~0.36 GiB out of 1177 MiB of margin. Nothing in the 0.2.9 numbers argues for
it: the stack's gain is already banked at batch 4.

### Method for this tree

- **`./tune-arm.sh <label> [gdn=on|off] [par=on|off] [env=…] [env-clear] [probe=TOKENS] [levels=…]`** is new here
  (copy of the coder runner). Same reload dance, gate before benching, and it prints the engine child's `/proc` env.
  Reload cost on this arm: **37.8-38.7 s** (vs 24.6-28.9 s for coder/iq1_m).
- **Arms are stateful**: `par=off` does not clear `gdn=off`. The run printed `run-config env (11)` for arm P and made it
  a two-knob arm; `P2 gdn=on par=off` is the valid one. Always read the `run-config env (n):` line before benching.
- **The era grep must pin `--batch 4`**: the 1slot tree uses the *same* pack (`packs/iq3_s`) and the same native GGUF,
  so a grep on pack name alone can measure the other tree's boot. Update the grep if `--batch` moves.
- The cold-read report now parses the **live log from the era line** (bounded by nothing, since no reload has happened
  yet in this run) — a boot archive written at reload time cannot contain the probe that runs after it.

## ctx 131072 + PARALLEL=3 (2026-10-31, **LIVE**, eras 179547 ctx@batch4 interim · 179781 preload@batch3 · 179912 accepted)

The profile layer was written back too: `strata/profiles/launch-docker.json` `overrides.parallel 4 -> 3` — this is the
"env beats the preset and is written back into it" behaviour, so the profile now agrees with nix instead of fighting it.

Requested: 128K context on this arm, three slots instead of four. **The slot count is not a preset knob**: nix's
`-e PARALLEL=4` for this model is what sets it ("env beats the preset and is written back into it"), and the
advertised context is a second, separate truth. So this changed **five places**, and the engine obeys only two of them:

| layer | was | now | note |
|---|---|---|---|
| nix `-e PARALLEL` (`configuration.nix` ~516) | 4 | **3** | authoritative for `--batch`; needed `nixos-rebuild switch` |
| nix `capabilities.context` (~533) | 98304 | **131072** | what llama-swap advertises as `context_window` / `n_ctx` |
| preset `extra["--max-context"]` | 98304 | **131072** | the layer that wins in argv |
| preset `"context"` | 98304 | **131072** | never reaches argv; it is the reuse-test half — mismatch it and setup rewrites the run config |
| run-config `args` `--max-context` | 98304 | **131072** | kept in step (write the value at `index+1`, never over the flag) |
| nix `hooks.on_startup.preload` | coder-iq1_m (stale from the tree switch) | **`qwen3.8-flash-next-iq3_s-parallel`** | boot default = the model that serves |

Backups: `20261031-pre-ctx128k-batch3-run.json.bak`, `…-preset.json.bak`.

**Why dropping a slot pays for the context** — the measured deltas, all one boot apart:

| line | ctx 98304 / 4 slots (B2) | ctx 131072 / **4** slots (interim) | **ctx 131072 / 3 slots (accepted)** |
|---|---|---|---|
| CUDA1 profiled pairs | 8192 of 8192 | 8192 of 8192 | **8192 of 8192** |
| experts resident | 54 % | 54 % | **55 %** |
| slot sessions CUDA0 | 4 × 0.36 GiB | 4 × 0.40 GiB | **3 × 0.40 GiB**, 11.10 GiB free |
| slot sessions CUDA1 | 4 × 0.20 GiB | 4 × 0.22 GiB | **3 × 0.22 GiB**, 19.27 GiB free |
| KV pinned RAM | 20480 of 98304, 0.77 GiB | 20480 of 131072, 1.03 GiB | **20480 of 131072, 1.03 GiB** |
| free at boot | 1177 / 1106 | 1179 / **972** | **1179 / 1262** |

The interim column is the warning label: **at 128K a 4th slot costs CUDA1 ~290 MiB** (1106 → 972), which is the RAM/VRAM
wall from § the RAM wall in miniature. With 3 slots CUDA1 ends up **156 MiB better** than the old 4-slot/98304 arm, and
CUDA0 gains 78 more expert slots (residency 54 → 55 %). KV resident cells did not move, so decode speed is unaffected;
what moved is pinned RAM (+0.26 GiB) and per-slot session size.

**Verified with a real cold 118,591-token prompt** (direct to the engine port, 500 KB of unique text):
`prompt 118591 tokens = 0 reused + 118591 read in 25592 ms (4634.0 tok/s)`, `KV streaming: 83.06% … hit VRAM`,
no `below 512 MiB`, no `WARNING`/`ERROR`, MemAvailable 12760 → 11355 MiB, evictions 0. So the prompt path is
*cheaper* per token at 118K than at 14K (4634 vs ~3290 tok/s) — the big-context path is not the weak spot.
Watch item instead: parked snapshots at this size are ~1.3-1.7 GiB each (`parked 52809 tokens bytes=1697473808`),
so the 6144 MiB / 6-slot cache holds **two** 100K+ conversations at most; the 1536 MiB admission floor is what keeps
that from touching swap.

**Client side:** llama-swap now advertises `context_window: 131072` for `qwen3.8-flash-next-iq3_s-parallel`
(verified over `/v1/models`). pi has **no** `contextWindow` override for this model, so it discovers that number and
auto-compacts above **131072 − 16384 = 114,688** tokens. A *running* pi session keeps whatever it read at start —
this session still believes 98304 until it is restarted.

## The slot count is steered from the config files now — `-e PARALLEL` removed from nix (2026-10-31, **LIVE**, era 180366)

`-e PARALLEL` is gone from both strata entries in `configuration.nix` (iq3_s parallel and coder). **The preset is the
steering place: `"parallel": 3` in `strata/launch-presets/docker.json`.**

Why this is safe, read off the code rather than guessed (engine package 0.1.55):

    entrypoint.sh:194   -e PARALLEL=N  ->  CLI `--parallel N`          (absent: no CLI flag at all)
    serve/server.py:9107 CLI flag      ->  cfg["parallel"] = N         (only when the flag was given)
    launch/cmd.py:238    CLI flag      ->  settings.parallel           (else the preset's value stands)
    launch/runner.py:1479 profile overrides.parallel = settings.parallel  (else four_card / catalog fit)
    serve/server.py:3309 parallel_args(cfg): cfg["parallel"] -> "--batch N"   (skipped if --batch/--slots already set)

So the env was never a separate source of truth — it was an **override of the preset that got written back into the
profile**, which is why `profiles/launch-docker.json` `overrides.parallel` silently moved 4 → 3 when the env changed.
Verified with the env stripped inside the container: `store.load("docker")` → `parallel = 3`, and the boot after the
rebuild still says `--batch: 3 slot sessions`, `8192 of its 8192 profiled pairs`, `55% resident`, free `1179 / 1262 MiB`,
`overrides: {host, port, parallel: 3}` written back from the preset path, and the 0.2.9 parallel stack env still
auto-on (`CKPT_POOL=1 GDN_TC=1 QSA_SLOTS=1`). No `usually holds` card-fit notice fired.

**What the env was protecting against (now a check, not a guard):** if `settings.parallel` is falsy the fallback is
`fit_parallel(main_vram_gb)` with `PARALLEL_BY_VRAM = ((32.0, 4), (24.0, 3), (20.0, 2), (0.0, 1))` — on this box that
is **3 for a 24.5 GB card but 1 for a 16.3 GB card**, i.e. card-dependent, not deterministic. This tree's preset *was*
regenerated once (0.1.55), and that is exactly when a `"parallel": null` could appear. So after any preset
regeneration: read the boot line for `--batch N` (and `overrides.parallel`) before trusting the arm.

The **coder entry lost `-e PARALLEL=3` in the same change** and was not booted to check it (it is not the serving
tree); its preset already has `parallel: 3`, so `--batch 3` is expected — confirm on its next start.

## Bench of the live keeper as-is — `--batch 3` + ctx 131072 + 0.2.9 stack on (2026-10-31, boot 12:37 local, bench 12:39-12:40)

No preset/run-config change in this run: the point was to measure what is live today.
Artifact: `.tune/keeper-b3-ctx128k.csv` (`bench-util.py --levels 1 2 3 --rounds 4 --max-tokens 400`,
engine port **5803** + engine id `qwen3.8-flash-next-iq3_s`, container `qwen3.8-flash-next-iq3_s-parallel`).

**Era / clock trap found here:** the engine log stamps are **UTC**, `podman inspect` `.Created`/`.State.StartedAt`
are local. The 12:37:14 CET container boot is era `180693` at `2026-10-31 11:37:18` — exactly one hour apart, which
looks like a stale era if you compare them naively. The newest `iq3_s` era *was* the live boot.

Boot gate (all pass; the boot line is the merged truth and carries `--batch 3`, preset-steered):

```
engine started: … --layer-split 32 --max-context 131072 --pcie-frac 0.00 --kv-resident 20480 … --batch 3
--batch: 3 slot sessions on CUDA0 (0.40 GiB each); 11.10 GiB free   /   CUDA1 (0.22 GiB each); 19.27 GiB free
layer split: CUDA1 runs layers 32-47, expert cache 8192 slots (16.52 GiB), 8192 of its 8192 profiled pairs; slot 0 verified
layer split: 55% of the experts resident, the prompt path's streamed ring 384 slots
1179 MiB of VRAM free with everything loaded   /   CUDA1: 1262 MiB of VRAM free with everything loaded
```

No `LOW` / `WARNING` / `not enough room`. `--pipeline-windows 2 is off: not with --batch slots` (expected under
`--batch`). Compute apps as expected: engine 14,780 MiB on the 5070 Ti + 21,614 MiB on the 3090 Ti, and
`strata-vision` 1,336 MiB on the 3090 Ti only.

| streams | agg tok/s | med/stream | per-stream runs | med/max TTFT | GPU0 (5070 Ti) | GPU1 (3090 Ti) | engine CPU (all threads) |
|---:|---:|---:|---|---|---|---|---|
| 1 | **149.8** | 149.8 | 96, 146, 153, 155 | 0.00 / 0.01 s | util 58% max 73%, 113 W | util 34% max 45%, 180 W | mean 14.77 max 16.33 |
| 2 | 156.9 | 78.7 | 73-82 ×8 | 0.00 / 0.00 s | util 57% max 100%, 115 W | util 37% max 42%, 172 W | mean 15.45 max 16.42 |
| 3 | **180.8** | 60.6 | 58-63 ×12 | 0.00 / 0.01 s | util 55% max 66%, 113 W | util 41% max 83%, 190 W | mean 15.46 max 16.36 |

Engine-side truth, same era (`erastats.py --pack iq3_s`, n=42 incl. this session): **accept 82.0 %,
`drafts/step 5.56`, `yield gen/fed 1.434`**, long-request `gen>=400` med **125.6 tok/s** (n=9), decode expert-cache
hit rate under load 69.8-86.3 %, `KV streaming` 95.5-97.2 % of block reads hit VRAM. MemAvailable 12,770 → 12,224 MiB
across the bench, no evictions. Drafting and KV residency are healthy.

### Readings

- **The fan-out ceiling is ~181 tok/s at 3 streams — dropping the 4th slot cost nothing aggregate.** Same-era-family
  comparison: this morning's batch-4 + nine-settings-ON arms measured 179.0 / 182.9 / 183.4 at **4** concurrent
  (§ 0.2.9 A/B), pre-0.2.9 batch-3/4/5 all topped out at 166-167 (§ Measured: batch 5). So `--batch 3` + 0.2.9 sits at
  the same ceiling with **60.6 tok/s per client at 3 concurrent** instead of 41.7 at 4 — and it bought the 128K context.
  The box is still saturated at ~166-183 regardless of slot count; the 0.2.9 gain (+8-11 %) is banked at 3 slots too.
- **Solo 149.8 is inside the drift band** (130.2-146.6 across that A/B; ±11 % for identical fixed configs). n=1 boot,
  so no claim either way — do not read it as an improvement over the 4-slot arm.
- **Neither GPU is the limiter at this width**: util 55-58 % (5070 Ti) and 34-41 % (3090 Ti), 113 W / 180-190 W, while
  the engine's all-thread CPU sits at **14.8-15.5 cores against a 15-worker pool** at every level. The feed path is at
  its ceiling while the cards idle — that, not VRAM or split, is what caps aggregate here. Worth knowing before any
  further slot/`--expert-cache` experiment: more slots will not move ~181.
- Not measured (so this is not a control): the ~14K-token unique-nonce **cold read**. `bench-util.py` prompts are ~30
  tokens, so the ±1 %-stable instrument is absent — this table prices decode and fan-out only.

### Would a 4th slot raise aggregate? — probed on the warm 3-slot boot (2026-10-31 12:44, same era 180693)

No config change: on a `--batch 3` engine a 4th concurrent client is still admitted (`max_queue 3`), so
`--levels 4` measures **demand**, not a 4th batch row. Interleaved in one era to beat the drift band
(`--levels 3 4 3 4 --rounds 2 --max-tokens 400`, artifact `.tune/keeper-b3-l34-interleave.csv`):

| level | agg (runs) | med/stream | GPU0 / GPU1 util | engine CPU |
|---|---|---|---|---|
| 3 | **170.7 / 184.1** | 57.1 / 61.9 | 52-53 % / 38-41 % | 15.15-15.55 cores |
| 4 | **164.9 / 172.9** | 57.2 / 59.7 | 53-54 % / 39 % | 15.36-15.54 cores |

(All 16 streams per level completed — the queue worked; the `med/stream` at level 4 is dragged by the queued
client whose wait is inside its own wall time: runs 41-43 vs 56-62 for the three that held slots. `agg` is
chunks/s as always in this script, which is why only same-run comparisons are meaningful.)

**Reading: a 4th *client* buys nothing** — 3 slots already cap the window at 3 rows, so extra concurrency only
queues. Whether a 4th **slot** (a 4th batch row) would help is *not* settled by this probe; the instruments that
decide it are the window lines, and they say the throughput variable is rows/window, not window cost:

```
strata batch: 226 windows, avg 5.29 rows, 27.25 ms/window = run 24.24 (CUDA0 GPU-reach wait 9.40 + CPU experts 5.40)
              + commit 1.12 + emit 1.70 + adapt wait 0.18
strata verify: captured the batch window over slots 0,0,1,1,2,2      ← 3 slots × 2 draft positions = 6-row ceiling
```

`avg 5.14-5.39 rows` of a **6-row** ceiling and `ms/window` flat at 27.2-27.9 across levels ⇒ a 4th slot raises the
ceiling 6 → 8; the gain is exactly `Δrows / ms/window` if `ms/window` holds. The `run` cost is dominated by
per-window fixed components (GPU-reach wait on the 5070 Ti ~9.4 ms, CPU experts 5.0-7.5 ms, commit+emit ~2.8 ms),
which is why it might.

Prior data (different ctx/boots, so indicative only): pre-0.2.9 batch-5 legs gained **+3.3 %** going 3→4 rows
(161.3 → 166.7) and **0** for the 5th (166.3); this morning's batch-4 + 0.2.9 arms hit 179.0-183.4 at level 4, which
**overlaps** today's 3-slot 170.7-184.1. So the honest prior is **+0 to +5 %, n≥2 boots/arm required** (±11 % drift).

Known cost at this context (measured § ctx 131072 + PARALLEL=3): a 4th slot costs CUDA1 **~290 MiB**
(1262 → 972 free — still above the 512 floor), residency 55 → 54 %, +0.26 GiB pinned RAM, and per-client speed at
4 concurrent drops 60.6 → ~42 tok/s. The § batch-4 product rule (≤3 concurrent sessions) also returns.

**To test it properly:** preset `"parallel": 3 → 4` + the reload dance. Two gotchas found while preparing:
`tune-arm.sh` has no `parallel=` knob (its arms are run-config `env` only) **and its era grep pins
`engine started: … --batch 4$`, which no longer matches the live `--batch 3` arm** — patch the grep (with a `.bak`)
or the runner will not find the era. Expect `4 slot sessions on CUDA0 (0.40 GiB each)` and ~1179 / 972 MiB free.

## A/B: `parallel: 3` vs `parallel: 4` at ctx 131072 (2026-10-31 12:50-13:05, boots A4 · B3 · C4 · D3)

The probe above left the question open, so this is the real arm test. **One knob**: `"parallel"` in
`strata/launch-presets/docker.json`, everything else byte-identical; switched identically each time
(python-set the key → `podman stop -t 120` → `sleep 2` → reload curl on the **proxy id** → gate → bench), each
switch inside one tool call (pi is served by this arm). Reload `38.2-40.7 s` every time.
Bench per boot: `bench-util.py --levels 3 4 --rounds 3 --max-tokens 400`, engine port 5803 + engine id.
Artifacts: `.tune/{A4,B3,C4,D3}.{era,csv,boot.txt}`; preset backup `…docker.json.bak-20261031-pre-batch4-ab`.
Order was **4, 3, 4, 3** (interleaved). Boot lines:

| | batch 3 (B3, D3) | batch 4 (A4, C4) |
|---|---|---|
| slot sessions | 3 × 0.40 GiB CUDA0 / 3 × 0.22 CUDA1 | 4 × 0.40 / 4 × 0.22 |
| CUDA0 expert cache | **5204 slots (9.60 GiB)** | **4985 slots (9.19 GiB)**, −4.2 % |
| experts resident | 55 % | 54 % |
| CUDA1 pairs | 8192 of 8192 | 8192 of 8192 |
| free at boot | 1179 / **1262** MiB | 1179 / **972** MiB |
| **min free at a window capture** | **1063 / 989 / 1039** MiB | **856 / 732** MiB |

Both arms healthy: no `LOW` / `WARNING` / `not enough room`; 972 and 732 are both above the 512 floor.

### Aggregate — the 4th slot wins **only at 4 real clients**

| level (concurrent streams) | parallel 3 | parallel 4 | verdict |
|---|---|---|---|
| 3 | 178.1 · 174.0 (+170.7 · 184.1 from era 180692) → **~176** | 175.1 · 175.5 → **175.3** | **tie** |
| 4 | 167.0 · 160.3 (+164.9 · 172.9) → **~166** | 182.7 · 184.0 → **183.4** | **+10.5 %, no overlap** (p4 min 182.7 > p3 max 172.9) |

Per-client at level 4: `parallel 4` gives all four clients **46.1 / 46.4** tok/s-equivalent; `parallel 3` is bimodal —
three slot-holders at 54-61 and the **queued fourth at 39.6-42**, wall/round 9.58-9.98 s vs 8.70-8.76 s.
Per-client at level 3: 58.5-59.5 vs 58.7-58.9 — tie.

### Mechanism (window accounting, medians per arm)

| arm | avg rows/window | ms/window | **rows/s** | CPU-experts/row | GPU-reach-wait/row |
|---|---|---|---|---|---|
| batch 3 (3 boots) | 5.23 of a 6-row ceiling | 27.96 | **190** | 0.214 ms | 1.069 ms |
| batch 4 (2 boots) | 6.09 of an 8-row ceiling | 32.87 | **185** | 0.215 ms | 1.212 ms |

**The engine does not generate faster with a 4th slot — rows/s is the same (190 vs 185, −2.6 %).** `ms/window` grows
almost exactly with rows, so the batch width itself is throughput-neutral. The whole +10.5 % is **queue avoidance**:
with 3 slots the 4th client waits, then burns engine time on its prefill and a mid-round slot handoff. A 4th slot does
not add speed, it stops the engine from paying admission costs — and it costs 4.2 % of the CUDA0 expert cache,
330 MiB of CUDA1 headroom, and ~250-300 MiB of window-capture margin.

### Verdict: **keep `parallel: 3`** (preset left on it; D3 is the live boot)

- The gain needs **≥4 genuinely concurrent clients**. This box's own product rule (§ batch 4 + queue back-pressure)
  caps pi-subagents at ≤3 concurrent sessions, so the +10.5 % is unreachable in normal use; at the ≤3 width that is
  actually used, `parallel 4` is a tie on agg and on per-client speed while being measurably thinner on VRAM.
- The thin margin is not cosmetic: the 4-slot arm's worst window capture sat at **732 MiB free** with ~400-token
  generations on ~30-token prompts. Context growth (this arm's whole point is 128K) eats exactly that pool, and
  § the RAM wall is about 4 concurrent long conversations — the same regime `parallel: 4` invites.
- If 4+ concurrency ever becomes real (e.g. a second client class, or the subagent rule is raised), re-run this A/B
  with `--levels 4 5` and watch the window-capture minimum; the decision line is 512 MiB there, not the aggregate.
- Runner state: `tune-arm.sh` is still pinned to `--batch 4$` in its era grep and has no `parallel=` arm — the A/B was
  run by hand with identical steps. Either patch both before the next arm, or keep hand-running this knob.

---

## 2026-11-03 — vision on the CPU, then the `gpus: [1,0]` split ladder to 21 (arms A/V, 5 boots each)

Requested: get the vision tower off the GPUs and give the 3090 Ti more experts. Both happened; **neither is a win**,
and the reason the second one fails to win also **partly overturns § the `[1,0]` role swap is poison on this pack**.

Arms (each boot = edit → `podman stop -t 120` → one proxy-id request on 8080 → gate → bench, all in one tool call;
the box serves this session, so no self-traffic was in flight during any measurement):

| arm | files | gpus | `--layer-split` | `--pcie-frac` | reserve MiB (0/later) | `vision.gpu` |
|---|---|---|---|---|---|---|
| **V** (keeper) | `*.bak-20261103-pre-gpuorder-swap` | `[0,1]` | 32 | 0.00 | 1280 / 1024 | true |
| **A** | `.tune/arm-A-{strata,preset}.json` | `[1,0]` | 21 | 0.20 | 1024 / 1280 | **false** |

### Vision on the CPU: works, costs nothing on the boot, unmeasured on real images

`"vision": {"gpu": false}` in the run config is the only knob — the preset keeps `--vision`, `strata-vision` still
starts, and it simply gets no CUDA context. Verified on the `[1,0]/17` boot: `nvidia-smi --query-compute-apps` shows
**one row (the engine) per card, no tower row**, and a real `image_url` request answers (`prompt 74 tokens in 710 ms`,
0.9 s round trip). The freed VRAM is what funded the ladder below (+1.23 GiB of auto-sized expert cache on the 3090 Ti).
**Not** measured: a real screenshot at `vision.max_tokens 1024` on CPU — 1slot's CPU-vision keeper runs 512 for that reason.

### The ladder: every step is +1 layer = +512 slots on the 3090 Ti, and it stops at 21

`--layer-split` 16 → 21, `[1,0]` throughout (boot files `.tune/visioncpu-s{17,18,19,20,21}.boot.txt`):

| split | 3090 Ti (stage 0) cache | …of its span | 5070 Ti (stage 1 = layers + head + 3 slot drafters) | overall resident | free MiB 0 / 1 |
|---|---|---|---|---|---|
| 16 | 8,192 / 14.33 GiB | 8192/8192 | 4,181 / 16,384 pairs (26 %) | 50 % | 1628 / 781 |
| 17 | 8,704 / 15.37 | ✓ | 4,228 / 15,872 (27 %) | 53 % | 1827 / 783 |
| 18 | 9,216 / 16.48 | ✓ | 4,287 / 15,360 (28 %) | 55 % | 4157 / 779 |
| 19 | 9,728 / 17.52 | ✓ | 4,338 / 14,848 (29 %) | 57 % | 3015 / 779 |
| 20 | 10,240 / 18.46 | ✓ | 4,435 / 14,336 (31 %) | 60 % | 1835 / 781 |
| **21** | **10,720 / 19.22** | ✓ 100 % | **4,451 / 13,824 (32 %)** | **62 %** | **969 / 785** |

Every boot passed the gate (min window capture 755-771 MiB, no `LOW` / `WARNING` / `not enough room`, `lend sizing`
ring K == N with `STRATA_SPLIT_RING=384`). **22 is off the cliff**: a step costs ~1.2 GiB there (922 MiB experts +
~180 MiB dense weights + ~120 MiB of per-slot KV — the slot sessions on CUDA0 grew 0.23 → 0.27 GiB each as the span
grew) against 969 MiB reported free, and the card is down to 1.3 GiB physical. Beyond 21 the money has to come from
`--max-context`, `--batch`, or the vision tower — not from more split.

**Stage 1 does not move.** It is capacity-capped, not demand-capped: it settles at ~4,300-4,450 slots whatever its
span, so shrinking the span from 32 to 27 layers only lifts its ratio 26 → 32 %. Fully resident needs span ≈ 8 layers
(split ~39-40) — that is the `[1,0]/38` arm § the role swap already rejected at −33…−42 % decode.

### A/B — 5 boots per arm, time-adjacent pairs

Level-1 (single stream) median tok/s per boot, `bench-util.py --max-tokens 400`:

| pair in time | A | V | winner |
|---|---|---|---|
| A1 / V1 (rounds 2) | **109.0** | **121.2** | V +11 % |
| A2 / V2 (rounds 2) | 118.8 | 129.9 | V +9 % |
| A3 / V3 (rounds 3) | 137.5 | 134.8 | A +2.0 % |
| A4 / V4 (rounds 3) | 136.1 | 134.9 | A +0.9 % |

Fan-out (agg tok/s): level 2 — A 154.4 / 151.9 vs V 151.3 / 149.0 (**A +2 %**); level 3 — A 177.3 / 172.2 vs
V 170.2 / 174.4 (**A +1.5 %**, overlapping; per-stream 57.8-60.0 vs 57.7-58.8 = tie, ceiling ~172-177 as always).
Cold read (the ±1 % control; unique ~3.5k-token probes, `max_tokens 1`): A5 **1678 / 1873**, V5 **1686 / 2021 tok/s** — identical.
`erastats.py --pack iq3_s` on the live V5 boot: `accept 74.6 %`, `drafts/step 3.94`, `yield gen/fed 1.543`.

**Verdict: `parallel: 3` / `[0,1]` / split 32 stays the keeper (it is the live boot).** A is a lateral move:
+7 points of overall residency and 2.5 GiB more experts on the 3090 Ti bought **nothing measurable** at 1-3 streams,
while giving up 210-480 MiB of window-capture margin and leaving the head+drafter stage at 32 % of its pairs.

### What this overturns, and the confound that has to be settled before anyone re-litigates it

§ the role swap rejected `[1,0]` on the last stage **not** holding its span. At split 21 that stage holds **32 %** of
its profiled pairs — far hungrier than at split 38 — and there is **no decode or cold-read penalty at all**. So the
"last stage must be fully resident" mechanism is **not** what killed `[1,0]/38`.

Arm A is a **bundle**, not a knob: it also changed `--pcie-frac 0.00 → 0.20` and swapped the reserves (1280/1024 →
1024/1280), and the earlier `[1,0]/38` rejection ran at `pcie-frac 0.00`. `--pcie-frac` sizes the VRAM staging pool
for exactly the starved stage, so it is the prime suspect for why starvation stopped hurting. **If this matters
enough to chase, the single-knob arm is `[1,0]/38 + pcie-frac 0.20` (everything else = keeper)** — that isolates it;
`[1,0]/21` is not the test.

### Method, since the drift ate two of the four pairs

Level-1 medians drift **+26 % within one config** over a long window (A1 109.0 → A3 137.5, identical config), which
is larger than every effect here and flipped sign between the early and late pairs. Only **time-adjacent** pairs are
comparable, and four of them still do not separate ±10 %: `--levels 1 --rounds 3` pairs are cheap (~36 s reload +
~25 s bench), so run **≥6 adjacent pairs** for anything under ~10 %, or interleave within one call.

## 2026-11-03 — vision on the CPU at 512 image tokens: **new keeper** (1.25 GiB back, latency unchanged)

Knob is in the run config only — `strata-iq3_s.json`: `"vision": {"gpu": false, "max_tokens": 512}`. The preset keeps
`--vision` and the mmproj; `strata-vision` still starts, it just gets no CUDA context.

**Boot cost: zero, and it pays.** Same expert caches as the old keeper (5,204 slots on CUDA0; 8,192 of its 8,192
profiled pairs on CUDA1), same min window capture (1163 vs 1159-1163 MiB), no `LOW` / `WARNING`. The 3090 Ti goes
from **1,346 → 2,603 MiB free** — the tower is a separate process holding **1,252 MiB** on the card named by
`vision.cuda_device` (still the physical nvidia-smi index, not the engine's stage) when `gpu: true`, and no row at all
when `gpu: false`.

**Image latency, isolated by holding the token budget at 512 across both boots** (same 1280x720 dashboard PNG, unique
nonce in the text so the KV prefix does not hit, `max_tokens 8`):

| boot | prompt_ms | wall s |
|---|---|---|
| `vision.gpu true`, 512 | 1504 · 866 · 872 | 1.74 · 0.98 · 0.98 |
| **`vision.gpu false`, 512** | 1109 · 846 · 838 | **4.33** · 0.94 · 0.92 |

Steady state is the **same either way** (0.92-0.98 s for a full-HD screenshot) — the tower encode is billed inside
`prompt_ms`, it is not a separate stall, and moving it to the CPU does not make it slower here. The one real cost is the
**first image after each boot on the CPU: ~3.2 s extra** (4.33 s wall against 1.11 s of engine time). If that ever
matters, it is a warm-up problem, not a throughput problem.

**512 image tokens is enough at this density**: every string on the 1280x720 mock — including 20 px text — came back
verbatim (`137 tok/s`, `22362 MiB`, `STAGE 1 THIN`, `cold read 1686 tok/s`), at `prompt_tokens 570` vs `1005` at 1024.
Not tested: dense terminal/text screenshots. If small-text OCR starts dropping, raise `vision.max_tokens` back toward
1024 **before** putting the tower back on the GPU — the token budget, not the placement, is what buys detail.

**Keeper now: `gpus [0,1]` · `--layer-split 32` · `--pcie-frac 0.00` · reserves 1280/1024 · `vision.gpu false` ·
`vision.max_tokens 512`** — live boot `.tune/K3-keeper-visioncpu512.boot.txt`, arm files `.tune/arm-A-*` / `.tune/arm-V-*`
(the V files are the *old* keeper, pre-vision-CPU; the current one adds the two `vision` keys).
Backup: `strata-iq3_s.json.bak-20261104-pre-visioncpu512`.

**Method trap found on the way:** sending the same image + same text twice makes the second read `prompt_ms 47 ms`
(prefix cache), which looks like a 20x vision speedup. Nonce the text on every vision latency probe.

## 2026-11-04 — `--layer-split 31` (re-test), `--kv-resident 16384`, `--pcie-frac 0.20`: **all three keep the keeper**

Requested: squeeze more out of this arm with `--pcie-frac 0.20` and other split / `--kv-resident` values. Six
boots, one knob each, `./tune-arm.sh` with `ROUNDS=3 'levels=1 3'`, arms interleaved with a keeper control after
every arm boot. Backups: `strata/launch-presets/docker.json.bak-20261104-pre-split-kv-sweep`,
`strata-iq3_s.json.bak-20261104-pre-split-kv-sweep`. Artifacts `.tune/q1104-{sp31-a,ctl-a,sp31-b,ctl-b,kv16-a,frac020-a,restore-k}.*`.
Eras: 200421 sp31-a · 200703 ctl-a · 201028 sp31-b · 201345 ctl-b · 201661 kv16-a · 201991 frac020-a · 202324 restore (live).
Reload 38.7 s every boot. pi is served by this arm, so every boot was a synchronous stop → proxy curl inside one
tool call, and the benches were issued from tool calls (no self-traffic in flight); this session's own requests do
live in every era and are excluded from the decode columns below (bench-util's own streams only).

### split 31: the 2026-10-25 rejection is **void** — it fits now — and it is still only a lateral move

The old rejection (§ The layer-split experiment) priced 17 layers against CUDA1's room *while the vision tower sat on
the 3090 Ti*. Since the vision-on-CPU keeper that room is 1.25 GiB bigger, and the boot says so:

```
layer split: CUDA1 runs layers 31-47, expert cache 8704 slots (17.55 GiB), 8704 of its 8704 profiled pairs; slot 0 verified
layer split: 57% of the experts resident          (keeper: 55%)
expert cache 5333 slots, 9.81 GiB                 (keeper: 5204 slots, 9.60 GiB)
1179 MiB of VRAM free with everything loaded      (keeper: 1179 — unchanged)
CUDA1: 1323 MiB of VRAM free                      (keeper: 2603)
```

So: **`8704 of its 8704`, gate clean**, residency 55 → 57 %, CUDA0's expert cache +129 slots (+2.5 %), and CUDA0's
auto sizing reports 11.31 GiB free instead of 11.10 — i.e. the vision move *did* convert into expert slots, which
also means § Guardrails' "CUDA1's cache is profile-capped … its free VRAM cannot be spent on experts" is true only
**at split 32**. At split 32 it holds exactly its 8192 profiled pairs; drop a layer onto it and it takes them.

Decode is a **tie**, in spite of the mechanism working:

| boot | L1 per-stream (first-of-level discarded) | L1 usable med | L3 agg / med-stream | rows | ms/window | CUDA0 GPU-reach | CPU-experts |
|---|---|---|---|---|---|---|---|
| sp31-a | 96 · **158** | 158 | 173.5 / 58.9 | 5.20-5.27 | 27.46-27.63 | 9.18-9.26 | **4.54-4.60** |
| ctl-a | 106 · 142 · 156 | 149 | 175.1 / 58.4 | 5.22 | 27.76 | 9.43 | 5.05 |
| sp31-b | 111 · 147 · 162 | 154.5 | **180.6** / 60.2 | 5.27 | **27.44** | **9.20** | **4.78** |
| ctl-b | 111 · 149 · 162 | 155.5 | 176.1 / 59.0 | 5.25 | 27.47 | 9.47 | 5.28 |
| kv16-a (clamped = control, see below) | 110 · 150 · 151 | 150.5 | 176.7 / 59.2 | 5.25 | 28.27 | 9.56 | 5.89 |
| frac020-a | 107 · 133 · 157 | 145 | 178.0 / 59.6 | 5.25 | 27.65 | 9.45 | 5.63 |

Adjacent pairs flip sign: pair A sp31 158 vs ctl 149 (+6 %), pair B 154.5 vs 155.5 (−0.6 %); L3 aggregate +0.8 %
across both pairs. The two mechanism terms do move — **CPU-experts 5.05-5.28 → 4.54-4.78 ms (−7…−10 %)**, GPU-reach
−2.7 % — but `ms/window` (27.44-27.63 vs 27.47-27.76) and `rows/s` (188-192) are flat, so the saving is absorbed by
the other window components and never reaches the token rate. Note `CPU-experts` itself drifts (5.05-5.89 across four
*identical* control-equivalent boots), so those percentages are the weakest instrument in the table; `ms/window` is
the one that matters and it did not move.

**Reject, and it is not a close call:** the price is CUDA1 free **2603 → 1323 MiB**, i.e. 1.28 GiB of the 3090 Ti's
working memory (long-context KV growth, later window graphs) for a residency gain that measured as nothing. Hard
rule 4 is on the table here. Re-test it only if something else gives that GiB back — the pair counts make split 30
the cliff: 9216 pairs = **18.58 GiB > 18.51 GiB room**, so 30 is `8192 of its 9216` on the 6.6 GB/s link.

### `--kv-resident` cannot go below 20480 — the engine floors it, silently

`kv=16384` lands in the preset and in the argv (`--kv-resident 16384` is on the boot line) but the boot prints:

```
KV streaming: 20480 of 131072 cells per QSA layer in VRAM, the K/V in 1.03 GiB of pinned RAM
expert cache 5204 slots, 9.60 GiB · 1179 / 2603 MiB free · 55% resident · 8192 of its 8192 pairs
```

**byte-identical to the keeper** — the floor the § Guardrails line names as a recommendation is enforced. So the
"free 0.7 GiB of slot sessions → +390 CUDA0 expert slots" idea is unreachable on this pack from this flag, and the
up direction was already measured negative (§ The layer-split experiment: kvres 32768 → CUDA0 cache 5,278).
**`--kv-resident 20480` is not a choice on this tree, it is the value the engine clamps to.** Any CUDA0 expert-cache
growth has to come from physical GiB on that card (vision off the GPU is the lever that worked) or from `--batch`.

### `--pcie-frac 0.20`: nothing to stage. Keep 0.00.

Identical boot (`5204 slots`, 1179/2603, 55 %, 8192/8192) and identical decode/fan-out (L3 178.0). The reason is in
the per-request tier counters, present in **every** era of this sweep:

```
strata serve: expert tiers: GPU 124837 hits this request; since the start RAM 32786 blobs, files 0 blobs 29387.5 MB read (the GGUF in place)
strata generate: resident RAM mode: 27.78 GiB of experts in RAM (page-locked) … adaptive swaps … (no file reads)
```

`files 0 blobs` everywhere: with `--resident-experts on` the miss tier is page-locked RAM, there is no file tier for
a PCIe staging pool to prefetch into, exactly as § Other measured decisions predicted. This is the same tie the
`1slot` tree measured across 0.00/0.20/0.40/0.60, now confirmed on this pack. **Do not re-sweep it** unless
`--resident-experts` comes off. (It also means the § 2026-11-03 open question "`[1,0]/38 + pcie-frac 0.20` would
isolate the role-swap failure" is dead on other grounds — 17 layers = 17.55 GiB can never fit the 16.3 GiB 5070 Ti.)

### Where the headroom actually is, after this sweep
`ms/window` sits at 27.4-28.3 with `run ≈ 24.2` made of `CUDA0 GPU-reach 9.2-9.6 + CPU experts 4.5-5.9 + commit 1.1 +
emit 1.7 + adapt 0.1`, at 5.2-5.3 rows of a 6-row ceiling, while both cards idle (util 55/38 %) and the engine's
thread pool is saturated (14.8-15.5 of 15 workers, § Bench of the live keeper as-is). Split, kv-resident and
pcie-frac are now all closed — the remaining multiplier is the **draft yield** (`yield gen/fed 1.40-1.50`,
`accept 77-84 %`): `--spec 4 --spec-min-p 0.70` has never been swept on this tree (the coder tree measured
`--spec-min-p 0.5` = −33 %, which only proves the *down* direction is bad). A `spec=6` / `spec-min-p=0.80` arm would
need a runner arg for those two keys (`PAIRS` currently knows only split/kv/frac/slots).
