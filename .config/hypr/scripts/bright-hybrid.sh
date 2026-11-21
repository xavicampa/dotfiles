#!/usr/bin/env bash
# Hybrid brightness for DMS: DDC (hardware) is primary. When DDC is already at
# its floor and another DECREASE comes in, flip DMS to software brightness
# (toggles DMS_NO_DDC on dms.service and restarts the shell — the only way
# DMS registers a software:<output> device) and keep dimming there.
# An INCREASE while the software device is at 100 flips back to DDC.
# Never touches the gamma/contrast settings.
#
# 2026-11-21: plain F11/F12 (+XF86) reach this script via the soft-* subcommands
# once the SDR-white segment (hyprland.lua, floor 80) bottoms out — that ladder
# SKIPS DDC entirely (software crossover only). SHIFT+F11/F12 run the original
# up/down hybrid: DDC stepping with the software crossover at the floor.
# The plain keys detect "software mode" by io.open()-ing the OVERRIDE file
# below (the Lua config can't shell out), so keep this file as the mode marker.
set -u
DDC_STEP=${DDC_STEP:-10}
SOFT_STEP=${SOFT_STEP:-10}
DDC_DEV=ddc:i2c-11
OVERRIDE=~/.config/systemd/user/dms.service.d/override.conf

exec 20>"${XDG_RUNTIME_DIR:-/tmp}/bright-hybrid.lock"
flock 20

ipc_pct() { dms ipc call brightness status 2>/dev/null | grep -oE 'Brightness: [0-9]+' | grep -oE '[0-9]+'; }
soft_pct() { dms ipc call brightness status 2>/dev/null | grep -oE 'software:[^ ]+ - Brightness: [0-9]+' | grep -oE '[0-9]+$'; }

in_software_mode() {
  case "$(systemctl --user show dms.service --property=Environment --value)" in
    *DMS_NO_DDC*) return 0 ;;
    *) return 1 ;;
  esac
}

wait_ipc() {
  for _ in $(seq 20); do
    dms ipc call brightness status >/dev/null 2>&1 && return 0
    sleep 0.5
  done
}

to_software_mode() {
  mkdir -p "$(dirname "$OVERRIDE")"
  printf '[Service]\nEnvironment=DMS_NO_DDC=1\n' > "$OVERRIDE"
  systemctl --user daemon-reload
  systemctl --user restart dms.service
  wait_ipc
}

to_ddc_mode() {
  rm -f "$OVERRIDE"
  rmdir "$(dirname "$OVERRIDE")" 2>/dev/null
  systemctl --user daemon-reload
  systemctl --user restart dms.service
  wait_ipc
}

case "${1:-}" in
  down)
    if in_software_mode; then
      dms ipc call brightness decrement "$SOFT_STEP" ""
    else
      before=$(ipc_pct); before=${before:-0}
      if [ "$before" -gt 0 ]; then
        dms ipc call brightness decrement "$DDC_STEP" "" >/dev/null
        sleep 0.3
        after=$(ipc_pct); after=${after:-$before}
        if [ "$after" = "$before" ]; then
          # DDC at its floor -> cross into software mode
          to_software_mode
          dms ipc call brightness set $((100 - SOFT_STEP)) ""
        fi
      else
        to_software_mode
        dms ipc call brightness set $((100 - SOFT_STEP)) ""
      fi
    fi
    ;;
  up)
    if in_software_mode; then
      before=$(soft_pct); before=${before:-100}
      if [ "$before" -ge 100 ]; then
        # software at full -> cross back into hardware
        to_ddc_mode
        dms ipc call brightness increment "$DDC_STEP" ""
      else
        dms ipc call brightness increment "$SOFT_STEP" ""
      fi
    else
      dms ipc call brightness increment "$DDC_STEP" ""
    fi
    ;;
  soft-down)
    # plain-key lane: software brightness only, never touches DDC values
    if in_software_mode; then
      dms ipc call brightness decrement "$SOFT_STEP" ""
    else
      to_software_mode
      dms ipc call brightness set $((100 - SOFT_STEP)) ""
    fi
    ;;
  soft-up)
    if in_software_mode; then
      before=$(soft_pct); before=${before:-100}
      if [ "$before" -ge 100 ]; then
        # software at full -> leave the lane (DDC devices get re-registered)
        to_ddc_mode
      else
        dms ipc call brightness increment "$SOFT_STEP" ""
      fi
    fi
    ;;
  *)
    echo "usage: $(basename "$0") up|down|soft-up|soft-down" >&2
    exit 2
    ;;
esac
