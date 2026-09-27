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

BIOS on **Intel baseline + -50 mV core offset + NGU 32x + D2D 32x**, PL1 200 W /
PL2 177 W. Input offset was tested and removed (regression). -50 mV core only
remains the coolest/simplest; the fabric OC trades +10 °C peak for +100–200 MHz
transients (see run log). The `rapl-pl1` systemd service (OS PL1
clamp) was **removed**. The full tuned profile (-50/-50 mV + vdroop 224 + PL2 170 W) still
exists in a BIOS profile, untested since.

## Run log (newest on top)

### Intel baseline + -50 mV core offset + NGU 32x + D2D 32x, PL1 200 W / PL2 177 W — 2026-09-13

- Full 3-min PASS (26/26, 0 untrustworthy). P 4.9–5.1 GHz (5.03–5.1 GHz blips —
  highest CPU clocks yet), E ~4.3–4.5 GHz, pkg 87–101 °C (peak 101 — first
  soft-thermal touch), power 169–177 W (nearly at the cap). Idle ~50–52 °C.
- NGU Max OC Ratio (GPU/NPU domain, range to 34) and CPU D2D Ratio (die-to-die
  link, range 15–40) both set to 32x. Effect: raises the CPU turbo ceiling
  (+100–200 MHz transients vs the flat 5.00 of the -50 mV-core-only run) but
  adds ~+10 °C peak and ~+15 W package heat from the SoC-die domains. Stable
  but at the thermal edge in ITX — the trade is transient clocks vs. sustained
  temps.
- **Research follow-up (2026-09-14):** NGU = "Next-Generation Uncore" = SoC-tile
  NoC/UFI fabric ("NGU OC is essentially NoC OC" — SkatterBencher); stock NGU
  26x = 2.6 GHz, D2D 21x = 2.1 GHz on *normal* Arrow Lake. **The 270K Plus
  already ships D2D at 3.0 GHz stock** (+43% vs normal chips, done by Intel to
  cut memory latency — ServeTheHome), so 32x is only +200 MHz (+7%) here. Perf
  data: D2D alone <1% (7-Zip, 1.5→3.5 GHz — SkatterBencher); D2D+NGU+DDR5
  timings tuned together ~+10% avg FPS in gaming, gain "mostly D2D and
  timings, not so much NGU" (TechPowerUp 285K); full D2D/NGU/ring tuning
  2–20% (Tom's Hardware). Conclusion: little fabric headroom left on the Plus
  chip; DDR5 timings are the better latency lever than pushing NGU/D2D higher.

### Intel baseline + -25 mV core input + -50 mV core offset, PL1 200 W / PL2 177 W — 2026-09-13

- Full 3-min PASS (26/26, 0 untrustworthy). P 5.00 GHz (one 5.05 GHz blip),
  E ~4.4–4.48 GHz, pkg 91–98 °C (peak 98), power 171–177 W — nearly at the cap,
  the highest power of any 2026-09 run. Idle ~52 °C.
- **The -25 mV core input offset made it WORSE than the -50 mV core-only run:
  same clocks, +5–8 °C, +~15 W.** Consistent with the Aug runs (the -25 mV input
  variant was always hotter than -50 mV input / auto input). On this board the
  "core input voltage" offset does not reduce effective Vcore as expected — it
  interacts with the VRM/LLC chain. Avoid the input offset; core offset alone is
  better.

### Intel baseline + -50 mV core voltage offset (only change), PL1 200 W / PL2 177 W — 2026-09-13

- Full 3-min PASS (26/26, 0 untrustworthy). P pinned 5.00 GHz (occasional
  4.93–4.96 dips), E ~4.40–4.48 GHz, pkg 82–90 °C (peak 90), power 152–161 W
  settling ~155 W. Idle ~46 °C (vs 51–52 °C stock).
- Vs. the stock baseline run: **+~100 MHz P, +~75 MHz E, −5 to −8 °C pkg, and
  ~5 W less power.** A plain -50 mV core offset on an otherwise stock profile is
  already a clean win; the extra vdroop/PL2 tweaks of the tuned profile buy the
  5.2 GHz bursts and extra E-freq, at slightly more heat.

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
