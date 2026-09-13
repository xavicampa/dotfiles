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
| Power limits (PL1/PL2) | currently **Intel baseline** (PL1 200 / PL2 177 W) | Self-limits to ~160 W in practice — see RESULTS.md. |

**Full experiment log: `RESULTS.md` in this skill's directory.** Current state
(2026-09-13): BIOS on **Intel baseline**, no OS PL1 clamp (service removed).
Tuned profile (-50 mV input / -50 mV core / vdroop 224 mΩ / PL2 170 W) is saved
in a BIOS profile. Quick comparison of the two at ~160 W sustained:

| | Intel baseline | Tuned (-50/-50, vdroop 224, PL2 170 W) |
|---|---|---|
| P / E freq | 4.9–5.0 / ~4.3–4.4 GHz | 5.0–5.2 / ~4.5–4.7 GHz |
| Pkg T | 89–98 °C | 85–90 °C |
| Power | ~157–165 W (self-limited, never hits 177 W cap) | 170 W burst → 160 W sustained |

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

### PL1 clamping (ad-hoc)

BIOS PL1 ("Long Duration Power Limit") is not reliably written to the CPU by
firmware. Clamp ad-hoc (root, reverts on reboot):
`pkexec sh -c "echo <uW> > /sys/class/powercap/intel-rapl:0/constraint_0_power_limit_uw"`.
Caveats: **sysfs read-back of RAPL limit values is flaky on this platform — judge
the effective limit by measured power under load, not the file value.** PL1 only
bites after the long-duration window on sustained load; 2–5 min runs run at PL2.
History: a boot-time `rapl-pl1` systemd oneshot did this for 150–160 W, removed
2026-09-13 (see RESULTS.md).

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

Full per-config data points: **RESULTS.md** (in this skill's directory).

Voltage verification is a dead end on Intel client CPUs: no Vcore MSR exists (unlike AMD
0xCD01); confirmed against kernel turbostat source. RAPL power + A/B testing is the way.
Note: `find` returns nothing on /sys/class/hwmon on this system — use glob loops.

## Process

1. One BIOS change at a time; F10, reboot, then run the 5-min test.
2. Record offset/LLC/power cap + resulting temp/power/freq each iteration in
   `RESULTS.md` (newest section on top).
3. If stable, push offset -25 mV deeper and re-test; if unstable, step back.
4. Final validation: a longer run (30 min) or a real workload day before trusting it.
