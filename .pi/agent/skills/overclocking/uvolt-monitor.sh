#!/usr/bin/env bash
# Sample CPU freq (P/E), temps, and RAPL power.
# Usage: uvolt-monitor.sh [duration_s] [interval_s]   (defaults: 60 5)
# No root required. Reads /sys cpufreq, coretemp hwmon, and RAPL powercap.
set -u
DUR=${1:-60}; INT=${2:-5}

# Locate coretemp hwmon dynamically (avoid find — it returns nothing on sysfs here)
HW=""
for h in /sys/class/hwmon/hwmon*; do
  [ -r "$h/name" ] || continue
  if [ "$(cat "$h/name" 2>/dev/null)" = coretemp ]; then HW="$h"; break; fi
done
if [ -z "$HW" ]; then echo "ERROR: coretemp hwmon not found" >&2; exit 1; fi

# Find P-core temp = 'Package id 0' (lowest pkgT label), fallback to first temp
PKG0=""
declare -A TVAL
for f in "$HW"/temp*_input; do
  [ -e "$f" ] || continue
  i=$(basename "$f" | sed 's/temp\([0-9]*\)_input/\1/')
  lbl=$(cat "$HW/temp${i}_label" 2>/dev/null)
  TVAL[$i]="$f"
  case "$lbl" in *"Package id 0"*) PKG0="$f";; esac
done
if [ -z "$PKG0" ]; then
  for f in "$HW"/temp*_input; do [ -e "$f" ] && { PKG0="$f"; break; }; done
fi

# P/E split: on this CPU (270K Plus, no SMT) P = cpu0-7, E = cpu8+.
# Override with P_MAX if your layout differs: P_MAX is the highest P-core index.
P_MAX=${P_MAX:-7}

end=$((SECONDS + DUR))
printf "%4s  %-15s  %-16s  %-8s  %-14s  %s\n" \
  "time" "P-freq_max(MHz)" "E-freq_max(MHz)" "pkgT(C)" "coreT_max(C)" "RAPL(W)"
while [ $SECONDS -lt $end ]; do
  pmax=0; emax=0; tmax=0
  for c in /sys/devices/system/cpu/cpu[0-9]*/cpufreq; do
    n=$(basename "$(dirname "$c")" | sed 's/cpu//')
    f=$(cat "$c/scaling_cur_freq" 2>/dev/null || echo 0)
    if [ "$n" -le "$P_MAX" ] && [ "$f" -gt "$pmax" ]; then pmax=$f; fi
    if [ "$n" -gt "$P_MAX" ]  && [ "$f" -gt "$emax" ]; then emax=$f; fi
  done
  for i in "${!TVAL[@]}"; do
    v=$(cat "${TVAL[$i]}" 2>/dev/null || echo 0)
    [ "$v" -gt "$tmax" ] && tmax=$v
  done
  pkgT=$(cat "$PKG0" 2>/dev/null || echo 0)
  e1=$(cat /sys/class/powercap/intel-rapl:0/energy_uj 2>/dev/null || echo 0)
  sleep "$INT"
  e2=$(cat /sys/class/powercap/intel-rapl:0/energy_uj 2>/dev/null || echo 0)
  if [ "$e1" -gt 0 ] || [ "$e2" -gt 0 ]; then
    w=$(( (e2 - e1) / 1000000 / INT ))
  else
    w=-1
  fi
  printf "%4ds  %-15s  %-16s  %-8s  %-14s  %s\n" \
    "$((DUR - (end - SECONDS)))" "$((pmax/1000))" "$((emax/1000))" "$((pkgT/1000))" "$((tmax/1000))" "$w"
done
