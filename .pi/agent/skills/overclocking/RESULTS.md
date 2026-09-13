# Overclock / Undervolt Test Log

Full history of BIOS voltage/power experiments. SKILL.md keeps only the current
state + methodology; this file is the A/B reference.

## Method

- Load: `stress-ng --cpu 24 --verify --vm 2 --vm-bytes 4G` (24 P+E cores + memory),
  3–5 min runs unless noted. Pass = `failed: 0`, `metrics untrustworthy: 0`, no
  hangs.
- Monitored: P/E max freq, pkg temp (coretemp), package power (RAPL) every 10–15 s.
- Voltage is NOT directly measurable (no Vcore MSR on Intel client) — judged via
  power/freq/temps A/B.
- **Effective power limit is judged by measured power under load, not by the RAPL
  sysfs files** (their read-back is flaky on this platform).

## Current state (2026-09-13)

BIOS set to **Intel baseline** (no undervolt, PL1 200 W / PL2 177 W), and the
`rapl-pl1` systemd service (OS PL1 clamp) was **removed**. The tuned profile
(-50/-50 mV + vdroop 224) still exists in a BIOS profile, untested since.

## Run log (newest last is fine; grouped chronologically)

### Intel baseline (BIOS default, PL1 200 W / PL2 177 W) — 2026-09-13

- P 4.9–5.0 GHz, E ~4.3–4.4 GHz, pkg 89–98 °C, 3-min PASS (26/26).
- Power peaks 164–165 W then settles ~157–160 W — **never reaches the 177 W cap**
  (VRM current limit and/or soft-thermal backing off as temps near Tjmax).
- Reference point: at the same ~160 W sustained, the tuned undervolt config runs
  100–200 MHz higher on P and E and 4–8 °C cooler.

### -50 mV core input + -50 mV core offset + vdroop 224 mΩ, PL2 170 W (BIOS), PL1 160 W (OS clamp)

- 3-min PASS (26/26, 0 untrustworthy). Flat 170 W for first ~90 s
  (P 5.0–5.2 GHz, E ~4.5–4.7 GHz, pkg 85–90 °C), then PL1 clamps: flat 159–160 W
  (P ~4.9 GHz, E ~4.5 GHz, pkg 88–90 °C).
- Confirmed the OS PL1 clamp actually bit despite sysfs read-back showing 200 W —
  proof that file values are unreliable and measured power is the truth.

### -50 mV core input + -50 mV core offset + vdroop 224 mΩ, PL2 170 W

- Full 3-min PASS (26/26, 0 untrustworthy). P pinned 5.00 GHz (one 5.2 GHz blip),
  E ~4.5–4.7 GHz, pkg 88–93 °C, flat 170 W.
- ~3–4 °C cooler than the -25 mV input variant at the same cap; the deeper
  input offset helps a little.

### -25 mV core input + -50 mV core offset + vdroop 224 mΩ, PL2 170 W

- Full 2-min PASS (26/26, 0 untrustworthy). P pinned 5.00 GHz, E ~4.5 GHz,
  pkg 85–96 °C, flat 170 W.
- Same clocks as the 160 W auto-input config but ~5 °C hotter → no gain from the
  extra 10 W or the -25 mV input offset.

### Auto core input + -75 mV core offset + vdroop 224 mΩ (instead of LLC level), PL2 160 W

- Full 3-min PASS (26/26, 0 untrustworthy). P pinned exactly 5.00 GHz, E ~4.5 GHz,
  pkg 87–91 °C, flat 160 W. Coolest of the 160 W configs; vdroop 224 mΩ keeps the
  offset stable under the cap.
- Note: **vdroop (mΩ, bigger = more droop, like IA AC Loadline) is a separate dial
  from the LLC level scale** on this BIOS.

### -25 mV core input + -50 mV core offset (two-offset split), PL2 160 W

- ~2 min 15 s PASS (26/26, stopped early by user). P ~4.9–5.0 GHz, E ~4.5 GHz,
  pkg 90–93 °C, flat 160 W.
- ~3–5 °C cooler than the flat -100 mV offset at the cost of ~100–150 MHz on P-cores.

### -100 mV core offset, PL2 160 W

- 5-min PASS (26/26). P ~5.0–5.1 GHz, E ~4.6 GHz, pkg 90–98 °C, flat 160 W
  (power-capped, not thermally).
- +100 MHz on P and E vs. the 150 W config for +4–5 °C; the power cap buys more
  clocks than the deeper offset saves.

### -75 mV + LLC 5, PL2 150 W (PL1 200 W)

- 3-min PASS (26/26); 5-min pass also verified earlier on -75 mV + LLC 5 + 178 W.
- P ~4.9–5.0 GHz, E ~4.4–4.5 GHz, pkg 86–94 °C, 150 W.

### Stock-ish, PL2 178 W (original stock baseline)

- P ~5.1 GHz, E ~4.6 GHz, pkg 99–104 °C, flat 178 W (power-capped).

## PL1 clamp history

- BIOS "Long Duration Power Limit" (PL1) shows as set in the UI, but firmware
  doesn't reliably write it to the CPU — fresh reboots show
  `constraint_0_power_limit_uw` = 200000000 while PL2 applies correctly.
- A boot-time systemd oneshot `rapl-pl1` (in the NixOS config) was used to write
  `constraint_0` (150 W, later 160 W). Verified effective by measured power
  (170→160 W ~90 s into load), even though sysfs read-back kept lying.
- **Removed 2026-09-13** — with the Intel-baseline BIOS the platform self-limits
  to ~160 W anyway (never reaches the 177 W cap), so the clamp was redundant.
- Ad-hoc re-apply if ever needed (root, reverts on reboot):
  `pkexec sh -c "echo <uW> > /sys/class/powercap/intel-rapl:0/constraint_0_power_limit_uw"`.
- PL1 only bites after the long-duration time window on sustained load — short
  (2–5 min) stress runs still run at PL2.
