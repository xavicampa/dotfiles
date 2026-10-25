# 1slot A/B — baseline arm (arena mode, no --resident-experts / --kv-resident)

Run: 2026-10-26 00:10, `python3 bench-1slot.py 2` against port 5801.
Engine 0.1.48, started 22:56:08 with the pre-change preset:
`--max-context 262144 --kv int8 --layer-split 32 --pcie-frac 0.00 --pipeline-windows 2
 --spec 4 --spec-min-p 0.70 --trim-stage-weights --vram-reserve-mib 1024 --vram-reserve-later-mib 1024
 --adapt-decay 0.97 --adapt-swaps 160 --conversation-cache-mib 1024 --expert-profile profile-learned.bin`

Startup state of this arm:
- expert arena: 46.84 GiB loaded (all experts pinned in RAM), THP refused ("only 13 GiB of free 2 MiB blocks")
- CUDA0 expert cache 4,840 slots (8.93 GiB); CUDA1 8,192 slots (16.52 GiB, 8192/8192 profiled pairs)
- VRAM free after load: CUDA0 817 MiB, CUDA1 808 MiB
- `--adapt-async 1 is off (not with a layer split in the arena mode)` (in preset from 23:56, refused)
- before the bench: MemAvailable 2.7 GiB, swap used 2.2 GiB, strata-host RSS 55.7 GiB

## engine accounting (baseline)

```
      ctx  reused   read  read tok/s   gen  gen ms decode tok/s
     6494       0   6494      2198.7     1      11         89.5   warm
     2039       0   2039      1017.0   693    4473        154.9   A r1
     2745    2034    711       703.0   494    2490        198.4   A r1 (auto-continue)
    83201    2034  81167      4603.5   689    5167        133.4   B r1
    83907   83889     18       318.8   494    3529        140.0   B r1 (auto-continue)
   171103   83196  87907      4310.5   690    5592        123.4   C r1
   171809  171098    711       872.2   494    3685        134.0   C r1 (auto-continue)
    84678       0  84678      4633.9     1      14         73.8   D r1 cold read
     1673       0   1673       925.0   691    4545        152.0   A r2
     2379    1668    711       709.1   494    2323        212.7   A r2 (auto-continue)
    81301    1668  79633      4576.8  1200    8398        142.9   B r2
   174856   81296  93560      4271.5  1200    8911        134.7   C r2
    84678       0  84678      4633.1     1      15         68.1   D r2 cold read
```

## medians (baseline)

| stage | what | baseline |
|---|---|---|
| A | decode at <40K ctx | **176.7 tok/s** (154.9 / 152.0 first passes) |
| B | decode at ~80K ctx | **140.0 / 142.9 tok/s** |
| C | decode at ~170K ctx | **123.4 / 134.7 tok/s** |
| D | cold 84,678-token prompt read | **4,633 tok/s** (18.3 s) |
| B/C prompt reads | 80–94K tokens read | 4,271–4,604 tok/s |

Note: the engine answers some greedy 1,200-token requests as two requests (693 + 494);
same behaviour expected in both arms, so the comparison stays fair. Round 2 did B/C in one pass.

---

# Arm 2 — + --resident-experts + --adapt-async 1 + --adapt-every 1 + --kv-resident 32768

Run: 2026-10-26 00:30, same script, same prompts.

Startup diff vs baseline:
- `KV streaming: 32768 of 262144 cells per QSA layer in VRAM, the K/V in 2.06 GiB of pinned RAM`
- CUDA0 expert cache **5,860 slots (10.78 GiB)** (baseline 4,840 / 8.93 GiB) = +1,020 slots
- CUDA1 8,192 slots unchanged, **2,026 MiB free** (baseline 808 MiB); CUDA0 763 MiB free
- `resident RAM mode: 25.43 GiB of experts in RAM (page-locked) ... (no file reads)`
  (baseline arena: 46.84 GiB) + 1.51 GiB exchange buffers (STRATA_EXCHANGE_ROTATE=1 in the image env)
- `adaptive tier asynchronous (--adapt-async 1): up to 96 swaps per round, a round every 1 windows` (ON)
- `lend sizing: the prompt path borrows 3062 slots (ring 96 at chunk 8192), 3062 keep their experts in RAM too`
  (baseline borrowed 2,022 CUDA0 + 1,836 CUDA1)
- `prefill plan: chunk 8192, ring 96 kept ... ~0.0 GB read from the drive per 32768-token prompt`
- after load: MemAvailable **18.7 GiB** (baseline 2.9 GiB), swap not growing, RSS 52.9 GiB

## engine accounting (arm 2)

```
      ctx   read  read tok/s   gen   decode tok/s
     2039   2039      1192.2   692        155.9   A r1
     2745    711       679.5   494        187.9   A r1 cont
    83201  81167      3849.0   689        126.8   B r1
    83907     18       238.7   494        144.9   B r1 cont
   171103  87907      3571.4   690        126.9   C r1
   171809    711       701.5   494        129.9   C r1 cont
    84678  84678      3882.2     1                D r1 cold read
     1673   1673      1096.5   695        151.1   A r2
     2379    711       661.9   494        231.5   A r2 cont
    81301  79633      3819.1   692        130.0   B r2
    82007    711       702.4   494        137.4   B r2 cont
   174808  93512      3579.3   691        139.1   C r2
   175514    711       649.4   494        125.4   C r2 cont
    84678  84678      3883.3     1                D r2 cold read
```

## A/B

| metric | baseline (arena) | arm 2 (resident + adapt-async + kv-res 32768) | delta |
|---|---|---|---|
| A decode @2-3K ctx | 154.9 / 152.0 (+cont 198/213) | 155.9 / 151.1 (+cont 188/232) | ~flat |
| B decode @80K ctx | 133.4 → 140.0, 142.9 | 126.8 → 144.9, 130.0 → 137.4 | ~flat (within spread) |
| C decode @170K ctx | 123.4 → 134.0, 134.7 | 126.9 → 129.9, 139.1 → 125.4 | ~flat |
| **D cold 84.7K read** | **4,633.9 / 4,633.1 tok/s (18.3 s)** | **3,882.2 / 3,883.3 tok/s (21.9 s)** | **-16.2 % (2 runs, +-0.03 %)** |
| B/C prompt reads | 4,271-4,604 tok/s | 3,571-3,849 tok/s | -15 % |
| decode cache hit rate | 84.5-87.7 % | **89.2-91.8 %** | +4 pt |
| resident blob reads from file | n/a | 9 total over 15 requests | ~0 |
| MemAvailable min | 2.9 GiB (swapping) | **18.1 GiB** | +15 GiB |
| CUDA0 free VRAM at start | 817 MiB | 763 MiB | -54 MiB |

Reading: the +1,020 CUDA0 expert slots and the async adaptive tier raise the hit rate ~4 points,
but decode lands flat; the reproducible cost is the **prompt path: 16 % slower on cold 85K reads**,
which is what KV streaming costs when the attended K/V past 32,768 cells come from host RAM
(PCIe ~12 GB/s) instead of VRAM. Setup's 32768 is the wrong number for sessions of 60-90K:
`strata_control/tune_knobs.py` only accepts 49152/65536 as flat-or-better at 128K and offers
`kv_resident_64k` (+5.4 % decode, 5/5) as the arm for ctx >= 128K.

Next arm: same, `--kv-resident` removed (isolate KV streaming).

## Launcher merge order (why arm 3 first ran with --kv-resident anyway)

`strata_cli/launch/runner.py:derive_config` (line ~285) builds the private run config as:
**base = the installed config** (`/data/install/strata-iq3_s.json` = `~/.config/strata/1slot/strata-iq3_s.json`),
then the preset's `extra` on top through `strata_control/tune_knobs.apply_to_argv`.

- a preset `extra` entry **adds or overrides** a flag;
- it does **not remove** a flag that the installed config carries. To remove: put `"--flag": "off"` in the
  preset's `extra` (`strata_cli/launch/settings.py:as_argv_changes`: "off/false/no/none removes it") or delete
  it from the installed config;
- so "the preset is authoritative" holds only for adds/overrides. Both files must be checked when taking a flag out.

Arm 2's `--kv-resident 32768` therefore came from the installed config (I had mirrored it there), which is why
the first arm-3 restart still showed `KV streaming: 32768 ... 2.06 GiB of pinned RAM`. Removed from both files;
arm 3 = `--resident-experts --adapt-async 1 --adapt-every 1`, no KV streaming.

# Arm 3 — resident + adapt-async, NO --kv-resident

CUDA0 cache 4,891 slots (8.98 GiB) · pinned complement 26.71 GiB · CUDA1 8,192 · free VRAM 759 / 844 MiB
`lend sizing: borrows 2774 slots (ring 96 at chunk 8192)` · `prefill plan: chunk 8192, ring 96 kept` · MemAvailable min 20.2 GiB

```
prompt 2039   = read 2039  (1180.5) 689 gen (149.9) | 494 gen (181.1)
prompt 83201  = read 81167 (3847.8) 1200 gen (138.4)
prompt 170764 = read 87568 (3628.5) 690 gen (124.7) | 494 gen (135.7)
prompt 84678  = cold read (3905.8 / 3905.5)
prompt 80814  = read 79139 (3816.3) 1200 gen (145.0)
prompt 173831 = read 93022 (3646.2) 692 gen (136.5)
```
=> `--kv-resident` was NOT the prompt-cost culprit (3,881 arm 2 vs 3,906 arm 3). Decode flat/slightly better at 170K.
=> the prompt cost tracks the borrow/ring: arena borrowed 3,858 slots, resident ring-96 borrows 2,774.

# Arm 4 — + STRATA_SPLIT_RING=0

Env reached the engine, but nothing changed: `ring 96`, `borrows 2,777`, pinned 26.71 GiB.
`split_ring_slots()`: 0 = "no override", and resident mode never gets arena's pinned-share borrow, so 0 is a no-op here.
(Also: `--kv-resident` had to be deleted from BOTH the preset `extra` and the installed config — extras never remove.)

# Arm 5 — + STRATA_SPLIT_RING=384  <-- winner

`layer split: 53% of the experts resident, the prompt path's streamed ring 384 slots`
`lend sizing: borrows 3512 slots (ring 384 at chunk 8192), 3512 keep their experts in RAM too` (K == N, no WARNING)
pinned complement 28.14 GiB · CUDA0 4,888 slots · free VRAM 757 / 840 MiB · MemAvailable min 18.8 GiB · 43 file blob reads per run

```
prompt 2039   (1087.6 read) 692 gen (140.9) | 494 (192.5)
prompt 83201  read 81167 (4637.7) 690 gen (147.7) | 494 (163.0)
prompt 171103 read 87907 (4386.3) 691 gen (128.4) | 494 (137.9)
prompt 84678  cold read (4727.4)
prompt 148524 cold read (4509.2), 948 gen (124.4)
```

## Cold prompt read, all arms (the one metric that is repeatable to +-0.1 %)

| arm | 84,678-token cold read |
|---|---|
| baseline (arena, KV in VRAM) | 4,633.9 / 4,633.1 tok/s |
| resident, ring 96 (arms 2/3/4) | 3,881.0 - 3,905.8 tok/s (**-16 %**) |
| **resident + ring 384 (arm 5)** | **4,727.4 tok/s (+2 % over baseline)** |
| 81K read inside a session | 4,638 (arm 5) vs 3,848 (ring 96) vs 4,604 (baseline) |
| 88K read inside a session | 4,386 (arm 5) vs 3,628 (ring 96) vs 4,310 (baseline) |

Decode did not move across arms beyond run-to-run spread (B 138-155, C 124-138; single 1200-token passes read
~10 tok/s higher than 692+494 two-pass answers, which happen in every arm).

## Final keeper config (live now, no restart needed)

preset `extra`: `--resident-experts on`, `--adapt-async 1`, `--adapt-every 1`, `--adapt-swaps 160`,
`--adapt-decay 0.97`, `STRATA_SPLIT_RING 384`, no `--kv-resident`; everything else untouched
(262144 ctx, `--kv int8`, `--layer-split 32`, `--pcie-frac 0.00`, `--pipeline-windows 2`, `--spec 4 --spec-min-p 0.70`,
`--conversation-cache-mib 1024`, `--vram-reserve-mib 1024 --vram-reserve-later-mib 1024`, `--trim-stage-weights`, `--vision`).
Installed config `strata-iq3_s.json` mirrors the args and carries `env: {"STRATA_SPLIT_RING": "384"}`.

# Arm 6 — split 31 + --kv-resident 32768  (and arm 7 = same with 20480)

Split 31 is viable here, and only because KV streaming funds CUDA1's 17th layer:
`CUDA1: 18.95 GiB free, room for experts 17.70 GiB -> expert cache 8704 slots (17.55 GiB), 8704 of its 8704 profiled pairs`
(512 pairs x 2.11 MiB = 1.08 GiB; at split 32 with KV in VRAM CUDA1 had only 808 MiB free -> would have missed).
CUDA0 cache 4,888 -> **5,947 slots**; overall residency 53 % -> **60 %**; free VRAM 759 / 822 MiB; no warnings.

```
arm 6 (kv 32768)                                  arm 7 (kv 20480)
ctx 1673/2039  read @971-1078   gen 692 @176.9    ctx 1673/2039  gen 691 @145.6/146.7
ctx 81301  read 79633 @4385.1   gen 690 @133.5    ctx 81301  gen 691 @130.2
ctx 83201  read 81167 @4478.6   gen 691 @156.4    ctx 83201  gen 691 @124.6
ctx 171103 read 87907 @4099.7   gen 691 @139.6    ctx 171103 gen 696 @139.1
ctx 174808 read 93512 @4085.7   gen 693 @159.2    ctx 174808 gen 1200 @128.6
cold 84678 @4475.6 / 4477.2                       cold 84678 @4477.1 / 4527.2
hit rate 88.3-93.5 %                              hit rate 92.1-93.9 %
```
Also in arm 6, a real long session ran through the engine: 182,501-token cold read @4,337.9 then decode
146.1 / 146.1 / 145.3 / 147.8 / 155.5 tok/s at 182-190K context. Arm 5 (split 32, KV in VRAM) had
124.4 / 134.7 / 128.4 / 139.6 tok/s at 148-175K. **Split 31 is ~+15 % decode at deep context**, paid for with
4,727 -> 4,476 tok/s on cold prompt reads (-5.3 %).

kv-resident 20480 vs 32768 at split 31: reads identical, CUDA0 +45 slots, CUDA1 +62 MiB margin,
decode a little lower -> keep **32768** (setup's own value for ctx >= 64K).
