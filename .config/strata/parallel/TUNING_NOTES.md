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
