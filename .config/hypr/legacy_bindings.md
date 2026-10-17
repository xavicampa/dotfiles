# Keybinds — homepc (Hyprland Lua + DMS)

Written 2026-10-16 during the DankMaterialShell trial.

- **`mainMod = "ALT"`** (from the old hyprlang config; kept in the Lua port)
- Your binds: `~/.config/hypr/hyprland.lua`
- DMS defaults: `~/.config/hypr/dms/binds.lua` (DMS-managed — regenerate with
  `dms setup binds`, edit via DMS Settings → Keybinds)
- Old hyprlang config (reference): `~/.config/hypr/.dms-backups/2026-10-16_11-17-13/hyprland.conf`

## Your binds

### Plain ALT

| Key | Action |
|---|---|
| `Return` | kitty |
| `C` | close window |
| `E` | nautilus |
| `V` | toggle float |
| `F` | toggle fullscreen |
| `Space` | `rofi -show drun` ⚠ collides with DMS (see below) |
| `Tab` | `rofi -show` |
| `P` | pseudo (dwindle) |
| `backspace` | `~/.config/rofi/powermenu.sh` |
| `H` `J` `K` `L` | focus left / down / up / right |
| `code:61` | toggle special workspace `magic` |
| `mouse_down` / `mouse_up` | workspace `e+1` / `e-1` |
| `mouse:272` / `mouse:273` | drag / resize window |
| `B` | `pkill -SIGUSR1 waybar` — vestigial, waybar is no longer autostarted |

### ALT+SHIFT

| Key | Action |
|---|---|
| `4` / `5` | `hyprshot -m region` / `-m window` |
| `H` `J` `K` `L` | movewindow left / down / up / right (via `hyprctl dispatch`) |
| `P` | `~/.config/rofi/displaymenu_homepc.sh` (homepc-specific, was in `homepc.conf`) |

### ALT+CTRL

| Key | Action |
|---|---|
| `Return` | `kitty pi` |
| `Space` | `rofimoji --action clipboard` |
| `H` / `L` | movecurrentworkspacetomonitor (via `hyprctl dispatch`) |
| `1`–`4` | workspace 1–4 |

### ALT+CTRL+SHIFT

| Key | Action |
|---|---|
| `1`–`4` | movetoworkspace 1–4 |
| `code:61` | movetoworkspace `special:magic` |

### Unmodified keys (no modifier)

| Key | Action |
|---|---|
| `F1`–`F4` | **dropped** in the Lua migration (survive only in `hyprland.lua.bak`). Were `ddcutil setvcp 10 ±25 --display 1/2`. Moot now: both MPG321UX panels share EDID serial `0x01010101`, so `--display 1`, `--display 2` and `--bus 16` all move *both* panels — there is no per-output DDC split on this box. |
| `F11` / `F12` | brightness down / up — `dms ipc call brightness decrement/increment 5 "ddc:i2c-11"`. On the Ducky One 3 Mini that is **Fn + `-`** and **Fn + `=`** (60% board: Fn + number row = F1–F12). |
| `XF86MonBrightness*` | bound (DMS stock, re-pointed at `ddc:i2c-11`) but **unreachable on this keyboard** — see Brightness note. Kept for a laptop. |
| `XF86Audio*` | **DMS's** — `dms ipc call audio` with DMS's OSD. Your old `pamixer`/`dunstify` binds were dropped (dunst is gone). Restorable from the commented block in `hyprland.lua.bak`. |

## DMS defaults that touch ALT

From `~/.config/hypr/dms/binds.lua` (118 binds total, almost all SUPER-based):

| Key | Action | Note |
|---|---|---|
| `ALT + space` | `dms ipc call spotlight-bar toggle` | ⚠ **the one real collision** — you bind `ALT + Space` → rofi drun. Yours loads after `require("dms.binds")`, so rofi wins. Delete your line to hand the key to DMS. |
| `ALT + Print` | `dms screenshot window` | No clash — your screenshots are `ALT+SHIFT+4/5`. |
| `SUPER + ALT + L` | `dms ipc call lock lock` | No clash. |

Everything else DMS binds is SUPER-based (`SUPER+T` terminal, `SUPER+Space`
spotlight, `SUPER+V` clipboard, `SUPER+X` powermenu, `SUPER+O`/`SUPER+TAB`
overview, `SUPER+comma` settings, `SUPER+P` output profile, `Print` screenshot, …).
Since `mainMod` is ALT, they sit alongside your set without interference.

## Brightness (DDC/CI) — why the device is named explicitly

**The keyboard has no brightness keys.** `Ducky Ducky One 3 Mini RGB` (5 input
interfaces: `event9`–`event13`) advertises only these consumer codes in its kernel
keybit (`EVIOCGBIT(EV_KEY)`): `KEY_VOLUMEUP` 115 / `KEY_VOLUMEDOWN` 114 / `KEY_MUTE` 113
(event10) and `KEY_NEXTSONG` 163 / `KEY_PLAYPAUSE` 164 / `KEY_PREVIOUSSONG` 165 /
`KEY_STOPCD` 166 (event13). No `KEY_BRIGHTNESSDOWN` 224 / `KEY_BRIGHTNESSUP` 225 /
`KEY_BRIGHTNESS_CYCLE` 243 — so `XF86MonBrightness*` can never fire here; that is why
brightness looked "missing in DMS" even though the DDC path works. Check any board with:

```bash
# prints the KEY_* codes each interface can emit
python3 -c "...EVIOCGBIT(1, 96) on /dev/input/eventN..."   # or: evtest --query <dev> 1 224 0
```

homepc is a desktop: `/sys/class/backlight` is empty, so the only brightness path is
DDC/CI over the i2c buses (`ddc:i2c-11` = HDMI-A-1, `ddc:i2c-16` = DP-3; `ddcutil
detect` maps them). `light`/`brightnessctl` are not installed.

DMS's stock binds pass `""` for the device, which resolves to DMS's *default* device —
that picked `leds:phy0-led` (a keyboard LED) here. Worse, DMS 1.6.2 hits upstream
[DankMaterialShell #3616](https://github.com/AvengeMedia/DankMaterialShell/issues/3616):
the initial DDC read fails at boot, the device is cached with `max=0/current=0`, and
`ForceRescan` skips devices already in the list — so an "increment 5" could *lower* the
panels (observed 25% → 10%). Any explicit set re-primes the cache ("move it once and it
works from then on"), which is why naming `ddc:i2c-11` in the bind both targets the right
device and keeps the cache honest.

```bash
dms brightness list --ddc          # device ids + % (slow: probes i2c)
dms brightness set ddc:i2c-11 40 --ddc
dms ipc call brightness status     # should say ddc:*, not leds:phy0-led
```

If the ids shift (replug/reboot), update `dms/binds-user.lua` from `list --ddc`.
A newer DMS than 1.6.2 should carry the #3616 fix; until then the cache goes stale again
after boot/resume, and the explicit-device binds are what keep the keys working.

## Gotchas learned

- **Lua key strings need `+` between modifiers.** Hyprlang's
  `bind = $mainMod CTRL SHIFT, 1` does **not** port as `"ALT + CTRL SHIFT + 1"` —
  Hyprland rejects it: `hl.bind: failed to parse key string: Unknown keysym:
  "CTRL SHIFT", did you forget a +?`. Use `"ALT + CTRL + SHIFT + 1"`.
- Lua-registered binds all report as `dispatcher: __lua` with an opaque id, so
  `hyprctl binds` cannot show the command — the source files are the reference.
- Hyprland picks Lua vs hyprlang **once at startup**: if `hyprland.lua` exists it
  wins and `hyprland.conf` is ignored (DMS keeps replacing that file with a stub).

## Inspecting live

```bash
# your ALT binds (modmask 8 = ALT, 9 = ALT+SHIFT, 12 = ALT+CTRL, 13 = ALT+CTRL+SHIFT, 72 = SUPER+ALT)
hyprctl binds | grep -B2 -A6 "modmask: 8"

# count
hyprctl binds | grep -c '^bind$'

# config errors
grep -i "lua error" "$(ls -t $XDG_RUNTIME_DIR/hypr/*/hyprland.log | head -1)"
```
