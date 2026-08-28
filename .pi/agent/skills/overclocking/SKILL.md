---
name: overclocking
description: CPU undervolting, overclocking, and stability stress testing on this machine (Intel Core Ultra 7 270K Plus, ASRock Z890I Nova WiFi, Linux/NixOS). Use when the user asks to undervolt/overclock the CPU, change CPU voltage/LLC/offset in BIOS, tune power limits, or validate stability after tuning changes (stress test + monitor). Also covers interpreting temps/power/freq under load and diagnosing thermal throttling vs instability.
---

# CPU Overclocking / Undervolting

## System

- **CPU:** Intel Core Ultra 7 270K Plus (Arrow Lake, LGA1851), no SMT enabled → 24 logical CPUs
  - **P-cores = cpu0–7** (max 5.5 GHz), **E-cores = cpu8–23** (max 4.9 GHz)
- **Board:** ASRock Z890I Nova WiFi (ITX — cooling is the usual bottleneck; 250W CPU in 17×17 cm)
- **RAM:** 62 GB
- Manuals (if needed, in this skill's directory): `Z890I Nova WiFi.pdf` (hardware
  quick guide) and `Software_BIOS Setup Guide_English.pdf` (BIOS settings reference).
  Extract text with `nix-shell -p poppler-utils --run "pdftotext -layout <pdf> /tmp/out.txt"`.

## BIOS (reboot → Del) — OC Tweaker

| Setting | Recommended | Notes |
|---|---|---|
| Intel CPU Vcore Offset | start **-0.050 V**, max ~-0.100 V | This is the undervolt. The only thing that lowers voltage. |
| Intel CPU Vcore Loadline Calibration (LLC) | **Level 4–6** | Higher level = **less** Vdroop = more voltage under load (flatter). Lower level = more droop = lower voltage under load but less stability headroom. |
| Core Voltage Mode | **Adaptive** | Override = flat voltage at all freqs, wastes power at low clocks. |
| VF Offset Mode | **Legacy** | Global offset. "Selection" = per-VF-point tuning (power users only). |
| Power limits (PL1/PL2) | **PL2 150 W** (done, works) | The real win on this board — see power-limit check below. |

### LLC direction (verified against the ASRock BIOS manual)

- "CPU Load-Line Calibration helps prevent CPU voltage droop under heavy load."
  → **Bigger Level = less Vdroop = higher voltage under load** (same convention as ASUS 1–15).
- **Do NOT confuse** with `IA AC Loadline` (VR Configuration section): that is the droop
  *slope* in **mΩ (0–20)** — there, bigger number = **more** droop. Opposite scale!
- Memory aid: Level scale → **L**arger level = **L**ess droop.
- The manual exposes LLC up to Level 5 for CPU; if the actual BIOS shows more (some users
  report up to 12), the direction is the same.

Undervolt pairing rules of thumb:
- Conservative: -50 mV + LLC 4–5
- Aggressive: -100 mV + LLC 8–12 (higher LLC lets you push the offset deeper before crashes)
- Instability at a given offset → raise LLC first before reducing the offset.
- Goal is cooler temps? Lower LLC (more droop) + deeper offset; LLC is not a voltage-reduction tool.

## Stress test + monitoring (no root needed)

Tools: `stress-ng` via nix-shell. **turbostat is NOT available** as a nixpkgs standalone
package (only in kernel trees) and dmesg is restricted (`kernel.dmesg_restricted`), so rely
on stress-ng's `--verify` for error detection.

Monitoring sources (all user-readable, no root):
- Freq: `/sys/devices/system/cpu/cpuN/cpufreq/scaling_cur_freq` (kHz)
- Temps: `/sys/class/hwmon/hwmon2/` (coretemp) — `temp*_input` m°C + `temp*_label`
- Power: `/sys/class/powercap/intel-rapl:0/energy_uj` (µJ, delta between samples / seconds)

### PL1 workaround (BIOS does not persist PL1)

The BIOS shows PL1 (Long Duration Power Limit) as set (e.g. 150 W), but the
firmware still writes the default 200 W to the CPU — verified: fresh reboot
shows `constraint_0_power_limit_uw` = 200000000 while PL2 applies correctly.
The sysfs file IS root-writable and the value sticks, so a systemd oneshot
`rapl-pl1` (in `~/.config/nixos/homepc/configuration.nix`) writes
`echo 150000000 > /sys/class/powercap/intel-rapl:0/constraint_0_power_limit_uw`
at boot after waiting for the RAPL node. To change PL1: edit that service's
`script` (uW), `pkexec nixos-rebuild switch`. To change it ad-hoc:
`pkexec sh -c "echo <uW> > /sys/class/powercap/intel-rapl:0/constraint_0_power_limit_uw"`.
Note PL1 only bites after the long-duration time window on sustained load —
short stress runs (2–5 min) still run at PL2.

### Run a stability test (5 minutes is the house standard)

Monitor script lives at `uvolt-monitor.sh` in this skill's directory (copy to a writable
path or run in place):

```bash
SKILL_DIR=<dir containing this SKILL.md>
# 1. Baseline (15 s idle)
bash "$SKILL_DIR/uvolt-monitor.sh" 15 5

# 2. Start stress test in background (CPU + memory, self-verifying)
nohup nix-shell -p stress-ng --run \
  "stress-ng --cpu 24 --verify --vm 2 --vm-bytes 4G --timeout 300 --metrics-brief" \
  > /tmp/stress.log 2>&1 &

# 3. Sample while it runs (duration, interval — keep within the run)
sleep 30; bash "$SKILL_DIR/uvolt-monitor.sh" 280 15

# 4. Check results
cat /tmp/stress.log     # want: "passed: 26 ... failed: 0 ... successful run"
```

Pass criteria:
- `failed: 0`, `metrics untrustworthy: 0`, no "skipped"
- No hangs/reboots during the run (system stays responsive)
- `--verify` exercises CPU math correctness (catches most undervolt instability)

### Interpreting the numbers

| Symptom under load | Diagnosis |
|---|---|
| Load power pinned **exactly** at a RAPL constraint value | **Power-capped** — lower PL1/PL2 in BIOS (was 178 W → set 150 W, dropped 13 °C for ~200 MHz). Undervolt is invisible under a hard cap. |
| P-core freq pinned well below max (e.g. 5.1 GHz vs 5.5 GHz) **and** temp ≥ ~100 °C | **Thermally throttled** — cooler is the bottleneck. Check case airflow/cooler mounting, then power limits, then push offset deeper. |
| Crash/reboot/wrong results at full load, fine at lighter load | Voltage too low under load → raise LLC or reduce offset by 25 mV. |
| Temp high but freq at max | Fine — undervolt is working if W-per-GHz dropped vs. baseline. |

**FIRST CHECK POWER LIMITS** — `cat /sys/class/powercap/intel-rapl:0/constraint_*power_limit_uw`
(µW). If load power reads exactly at constraint_1 (short-term/PL2), the CPU is
**power-capped**, not just thermally limited — an undervolt will change nothing visible
under the cap, and lowering PL1/PL2 in BIOS is the real fix for temps.

Data points (24 CPU + 2 VM @ 4 GB mixed load):
- Stock-ish, PL2 178 W: P ~5.1 GHz, E ~4.6 GHz, pkg 99–104 °C, flat 178 W (power-capped).
- -75 mV + LLC 5 + PL2 150 W (PL1 200 W): P ~4.9–5.0 GHz, E ~4.4–4.5 GHz,
  pkg 86–94 °C, 150 W, stress-ng 3-min --verify PASS (26/26). 5-min pass also verified
  earlier on -75 mV + LLC 5 + 178 W.
- -100 mV + PL2 160 W (PL1 200 W): P ~5.0–5.1 GHz, E ~4.6 GHz,
  pkg 90–98 °C, flat 160 W (power-capped, not thermally), 5-min stress-ng --verify
  PASS (26/26).** +100 MHz on P and E vs. the 150 W config for +4–5 °C; power cap
  buys more clocks than the deeper offset saves.
- -25 mV core input + -50 mV core offset (two-offset split) + PL2 160 W:
  P ~4.9–5.0 GHz, E ~4.5 GHz, pkg 90–93 °C, flat 160 W, stress-ng --verify
  passed 26/26 failed 0 (~2 min 15 s, stopped early by user). ~3–5 °C cooler than
  the flat -100 mV offset at the cost of ~100–150 MHz on P-cores.
- **Best so far: Auto core input + -75 mV core offset + vdroop 224 mΩ (instead of
  LLC level) + PL2 160 W (PL1 200 W): P pinned exactly 5.00 GHz, E ~4.5 GHz,
  pkg 87–91 °C, flat 160 W, full 3-min stress-ng --verify PASS (26/26, 0 untrustworthy).**
  Coolest of the 160 W configs; vdroop 224 mΩ keeps the offset stable under the cap.
  Note: vdroop (mΩ, bigger = more droop, like IA AC Loadline) is a separate dial from
  the LLC level scale on this BIOS.
- -25 mV core input + -50 mV core offset + vdroop 224 mΩ + PL2 170 W:
  P pinned 5.00 GHz, E ~4.5 GHz, pkg 85–96 °C, flat 170 W, full 2-min stress-ng
  --verify PASS (26/26, 0 untrustworthy). Same clocks as the 160 W auto-input config
  but ~5 °C hotter → no gain from the extra 10 W or the -25 mV input offset; the
  160 W / auto-input setup is strictly better.
- -50 mV core input + -50 mV core offset + vdroop 224 mΩ + PL2 170 W:
  P pinned 5.00 GHz (one 5.2 GHz blip), E ~4.5–4.7 GHz, pkg 88–93 °C, flat 170 W,
  full 3-min stress-ng --verify PASS (26/26, 0 untrustworthy). ~3–4 °C cooler than
  the -25 mV input variant at the same cap; the deeper input offset helps a little.
- **Final: -50 mV core input + -50 mV core offset + vdroop 224 mΩ + PL2 170 W
  (BIOS) + PL1 150 W (OS-enforced, see PL1 workaround above).** 3-min stress-ng
  --verify PASS (26/26, 0 untrustworthy). Confirmed PL1 bites under sustained load:
  flat 170 W for the first ~90 s (P 5.0–5.2 GHz, E ~4.5–4.7 GHz, pkg 85–90 °C),
  then RAPL drops to flat 150 W (P ~4.9 GHz, E ~4.3 GHz, pkg 85–88 °C).

Voltage verification is a dead end on Intel client CPUs: no Vcore MSR exists (unlike AMD
0xCD01); confirmed against kernel turbostat source. RAPL power + A/B testing is the way.
Note: `find` returns nothing on /sys/class/hwmon on this system — use glob loops.

## Process

1. One BIOS change at a time; F10, reboot, then run the 5-min test.
2. Record offset/LLC/power cap + resulting temp/power/freq each iteration.
3. If stable, push offset -25 mV deeper and re-test; if unstable, step back.
4. Final validation: a longer run (30 min) or a real workload day before trusting it.
