# Keybinds — homepc (Hyprland Lua + DMS)

> Scope: **homepc only.** The dell runs no DMS and has its own bind file —
> see [dell — bare Hyprland](#dell--bare-hyprland-no-dms-confighyprhostsdelllua) at the end.

Nothing in this file is generated, so counts and key tables are not kept here — they rot on every
DMS update (they already did, see [Gotchas learned](#gotchas-learned)). Read live state instead:

```bash
dms keybinds show hyprland | jq -r '.binds[][] | "\(.key)\t\(.action)\t\(.source)"' | sort
hyprctl binds                            # ground truth: modmask, flags, keycode
hyprctl binds | grep -cE '^bind'         # count
hyprctl binds | grep -oE 'modmask: +[0-9]+' | sort | uniq -c | sort -rn   # modmask census
```

Or press **`SUPER+Z`** for DMS's own cheatsheet overlay. `dms keybinds show` is *not* live state —
see [Inspecting live](#inspecting-live).

---

## Read this first: Alt *is* Super

`hyprland.lua` sets `kb_options = "altwin:swap_lalt_lwin"` — **physical Alt emits Super,
physical Win emits Alt.** So every `SUPER` row below is pressed with the physical **Alt**
key. That is how the old `mainMod = ALT` muscle memory survived the DMS migration; the
hyprlang ALT binds themselves are gone.

Only two binds carry ALT, both DMS defaults, reached with the physical **Win** key: `ALT+space`
(spotlight-bar) and `ALT+Print` (window screenshot). Verify any time with
`hyprctl binds | grep -B4 'modmask: 8$'`.

---

## Your binds — `dms/binds-user.lua`

The only keybind file you own — and it **is** tracked in dotfiles, unlike most of `dms/` (see the
gitignore note in [Gotchas learned](#gotchas-learned)). Rationale lives here, not in the Lua file:
DMS rewrites that file and drops comments.

| Key | Action | Note |
|---|---|---|
| `SUPER + Return` | `kitty` | terminal (replaces DMS's `SUPER+T`) |
| `SUPER + CTRL + Return` | `kitty pi` | pi inside kitty; carried over from the hyprlang config |
| `SUPER + E` | `nautilus --new-window` | Files; `SUPER+E` was free (only `SUPER+SHIFT+E` = exit and `SUPER+End` existed). Drop `--new-window` for raise-the-existing-window behaviour |
| `SUPER + B` | `dms ipc call bar toggle index 0` | hide / show the DMS bar |
| `SUPER + SHIFT + B` | `dms ipc call bar toggleAutoHide index 0` | bar auto-hide on/off |
| `SUPER + minus` (printed `-`) | `togglespecialworkspace magic` | scratch on/off; displaces DMS's `resizeactive -100 0`, which still lives on the printed `+` (`SUPER+code:20`). Width resize therefore = `+` / `\`, never `-` |
| `SUPER + SHIFT + code:61` (printed `-`) | `movetoworkspace special:magic` | window → scratch — the only one now (`SUPER+S` / `SUPER+SHIFT+S` unbound). **Must** be the `code:` form: on `no` the printed `-` key emits keysym `underscore` with Shift down, so `SUPER + SHIFT + minus` is unreachable — see [the shift trap](#the-shift-trap-why-supershiftminus-is-dead-on-no) |
| `SUPER + Z` | `dms ipc call keybinds toggle hyprland` | keybind cheatsheet overlay |
| `F11` / `F12` | `dms ipc call brightness decrement/increment 5 "ddc:i2c-11"` | = **Fn + `-` / `=`** on the Ducky One 3 Mini |
| `XF86MonBrightnessDown/Up` | same two brightness commands | unreachable on this keyboard — kept for a laptop |

**Unbound on purpose** (`hl.unbind()` entries in the same file, so they stay dead across DMS
updates): `SUPER + T`, `SUPER + grave`, `SUPER + code:61`, `SUPER + SHIFT + Slash`, `SUPER + S`,
`SUPER + SHIFT + S`, `F11`, `F12`, `XF86MonBrightness*` — the last four are re-bound to the
commands above — plus `SUPER + minus` and `SUPER + SHIFT + code:61`, re-bound to scratch. The two
`S` entries are kept as bare `hl.unbind()`s so they stay dead even though `hosts/dell.lua:149-150`
binds that same pair on the laptop.

Scratch map: `SUPER+minus` toggles it; `SUPER+SHIFT+code:61` (physical `Shift+-`) sends the window
there; `SUPER+S` and `SUPER+SHIFT+S` are unbound.

Still live but **unable to fire on this layout**: `SUPER + equal` (`equal` exists only as shifted
`0`). `SUPER + SHIFT + equal` does fire — as `SUPER+SHIFT+0` — but its `resizeactive 0 100` moves
nothing here. See [the shift trap](#the-shift-trap-why-supershiftminus-is-dead-on-no) and
[height is not a free axis](#height-resize-is-a-no-op-in-dwindle-here).

Why scratch sits on the keysym `SUPER+minus` and not `code:61` / `SUPER+grave`: they are the same
physical key (`code:61` = XKB keycode 61 = `<AB10>` = minus/underscore on `no`), so `code:61` is
left explicitly unbound to stop DMS's legacy scratch bind landing there twice. `SUPER+grave` is
unbound because `no(basic)` has no `grave` keysym — such a bind registers and then never fires.
Letters are layout-stable; punctuation keysyms are not.

---

## DMS defaults — deliberately not catalogued

`dms/binds.lua` is DMS-generated and gitignored; a hand-copied table of it goes stale on every DMS
update (the one that used to live here claimed `SUPER+SHIFT+minus` was a working resize pair — it is
unreachable on this layout, see [the shift trap](#the-shift-trap-why-supershiftminus-is-dead-on-no)).
Look the defaults up rather than trusting prose:

```bash
dms keybinds show hyprland | jq -r '.binds[][] | select(.source=="dms-default") | "\(.key)\t\(.action)"' | sort
```

The defaults that need knowing, not looking up:

| Default | Why it matters here |
|---|---|
| `SUPER + SHIFT + E` | **exits the compositor** — the only dangerous combo on this box |
| `SUPER + code:20` `code:21` | width resize (`resizeactive ∓100 0`) — the layout-proof forms, and now the only resize keys you have |
| `SUPER + minus` `equal` | same intent, keysym form: `minus` is unbound here (scratch), `equal` is unreachable on `no` |
| `SUPER + SHIFT + minus` `equal` | height resize: unreachable / mis-aimed (`equal` = shifted `0`), and a no-op in dwindle regardless — [height is not a free axis](#height-resize-is-a-no-op-in-dwindle-here) |
| `SUPER + space` · `ALT + space` | spotlight / spotlight-bar; the `ALT` one is the physical **Win** key |
| `SUPER + P` · `SUPER + SHIFT + P` | output-profile cycle · DPMS (monitors off) |
| unmodified `XF86Audio*` | `dms ipc call audio …` and mpris — the only modifier-free binds |
| `SUPER + O` `TAB` `Y` `V` `M` `X` `N` `W` | overview · overview · dash · clipboard history · process list · powermenu · notifications/notepad |

---

## Gone / intentionally unbound

- **`SUPER+T`** — DMS's terminal default; unbound in favour of `SUPER+Return`.
- **`CTRL+SHIFT+R`** — DMS's `workspace-rename open` default; Chrome/Chromium (and Firefox)
  own it as hard-reload — upstream [DMS #3485](https://github.com/AvengeMedia/DankMaterialShell/issues/3485).
  Rename on demand with `dms ipc call workspace-rename open`, or re-bind it elsewhere
  (`dms keybinds set hyprland <key> ...`).
- **`F1`–`F4` per-monitor brightness** — dropped in the Lua migration (survive only in
  `legacy/hyprland.lua.bak`). Moot: both MPG321UX panels share EDID serial `0x01010101`, so
  `--display 1`, `--display 2` and `--bus 16` all move *both* panels — there is no
  per-output DDC split on this box.
- **rofi, waybar, pamixer/dunstify binds** — died with the hyprlang config. The old
  `ALT+space` → rofi drun collision is resolved by simply not existing: DMS's
  `spotlight-bar` owns `ALT+space` now.
- Full old config for reference, both **versioned** in the dotfiles repo:
  `~/.config/hypr/legacy/hyprland.lua.bak` (the full Lua port of the old config — `cp` it over
  `hyprland.lua` to restore) and `~/.config/hypr/legacy/hyprland.conf` (the last hyprlang
  config). DMS's own rolling copies in `~/.config/hypr/.dms-backups/*/` are git-ignored and
  were byte-identical, so the repo keeps one.

---

## Brightness (DDC/CI) — why the device is named explicitly

**The keyboard has no brightness keys.** The `Ducky Ducky One 3 Mini RGB` (5 input
interfaces, `event9`–`event13`) advertises only these consumer codes in its kernel keybit
(`EVIOCGBIT(EV_KEY)`): `KEY_VOLUMEUP` 115 / `KEY_VOLUMEDOWN` 114 / `KEY_MUTE` 113 (event10)
and `KEY_NEXTSONG` 163 / `KEY_PLAYPAUSE` 164 / `KEY_PREVIOUSSONG` 165 / `KEY_STOPCD` 166
(event13). No `KEY_BRIGHTNESSDOWN` 224 / `KEY_BRIGHTNESSUP` 225 — so `XF86MonBrightness*`
can never fire here; brightness looked "missing in DMS" even though the DDC path works.
Check any board with `evtest --query <dev> 1 224 0`.

homepc is a desktop: `/sys/class/backlight` is empty, so the only path is DDC/CI over i2c
(`ddc:i2c-11` = HDMI-A-1, `ddc:i2c-16` = DP-3; `ddcutil detect` maps them). `light` /
`brightnessctl` are not installed.

DMS's stock binds pass `""` for the device, which resolves to DMS's *default* device — that
picked `leds:phy0-led` (a keyboard LED) here. Worse, DMS 1.6.2 hits upstream
[DankMaterialShell #3616](https://github.com/AvengeMedia/DankMaterialShell/issues/3616): the
initial DDC read fails at boot, the device is cached with `max=0/current=0`, and
`ForceRescan` skips devices already in the list — so "increment 5" could *lower* the panels
(observed 25% → 10%). Any explicit set re-primes the cache, which is why naming
`ddc:i2c-11` in the bind both targets the right device and keeps the cache honest.

```bash
dms brightness list --ddc          # device ids + % (slow: probes i2c)
dms brightness set ddc:i2c-11 40 --ddc
dms ipc call brightness status     # should say ddc:*, not leds:phy0-led
```

If the ids shift (replug/reboot), update `dms/binds-user.lua` from `list --ddc`. A newer DMS
than 1.6.2 should carry the #3616 fix; until then the cache goes stale after boot/resume and
the explicit-device binds are what keep the keys working.

---

## Height resize is a no-op in dwindle here

Making `SUPER+SHIFT+minus` reachable was only half the story: even fired correctly, **the action
has nothing to do on this desktop.** Measured on a tiled kitty window:

```console
hl.dispatch(hl.dsp.window.resize({x = -100, y = 0, relative = true}))   → size 1738 → 1838   ✅
hl.dispatch(hl.dsp.window.resize({x = 0, y = -300, relative = true}))   → size unchanged      ❌ (returned "ok")
```

Both ws1 windows are `size=[…,1578]` (`kitty [1141,41] 1738x1578`, `google-chrome [1,41] 1138x1578`)
while usable height is `1620 − 40` (bar reserve) = **1580** — every window already spans the full
workspace height. `tiledLayout: dwindle`, no horizontal split exists, and only left/right preselect
is bound (`bracketleft`/`bracketright`), so a vertical stack is never created and
`resizeactive 0 ±N` has no split edge to move. That is why DMS's whole `SHIFT + minus/equal` height
pair feels broken regardless of keysyms.

Sign caveat when reading resize binds: the number is relative to the **split gap**, not the window.
For a window right of the gap, `x = -100` *grows* it and `x = +100` shrinks it — hence
`SUPER+SHIFT+code:61 → resizeactive 100 0` is the true opposite of `SUPER+minus → resizeactive
-100 0`.

To make height real some day, bind vertical preselect first, e.g.
`hl.bind("SUPER + SHIFT + bracketleft", hl.dsp.layout("preselect t"))` / `…"preselect b")`;
after that, `code:`-form `resizeactive 0 ±100` binds start doing something.

---

## The shift trap: why `SUPER+SHIFT+minus` is dead on `no`

Hyprland matches a keysym bind on **two** conditions (`CKeybindManager::handleKeybinds`,
`src/managers/KeybindManager.cpp`):

```cpp
if (!IGNORECONDITIONS && ((modmask != k->modmask && !k->ignoreMods) || …)) continue;  // EXACT modmask
const auto KBKEY = xkb_keysym_from_name(k->key.c_str(), XKB_KEYSYM_NO_FLAGS);
if (key.keysym != KBKEY && key.keysym != KBKEYLOWER) continue;                        // EXACT keysym
```

`key.keysym` comes from `xkb_state_key_get_one_sym`, i.e. **shift has already been applied**. So
`bind = SUPER SHIFT, minus` needs some key that emits the keysym `minus` *while Shift is
held*. On `kb_layout = no` the printed `-` key is `<AB10>`, not `<AE11>`:

``` console
xkeyboard-config-2.47/share/X11/xkb/symbols/no:26
key <AB10>  { [     minus, underscore,       endash,       emdash ]  };
```

Shifted it emits `underscore`. Nothing on this layout emits `minus` with Shift down, so that
bind is not shadowed — it is **unaddressable**. It still shows up in `hyprctl binds`
(`modmask: 65, key: minus`), which is why "the bind exists but nothing happens" looks like a
conflict. Same trap, mirrored: keysym `equal` only exists on `no` as *shifted* `<AE10>`
(`[0, equal, braceright, notequal]`), so `SUPER+equal` is dead and DMS's `SUPER+SHIFT+equal`
fires as **`SUPER+SHIFT+0`**.

Fixes, in order of preference:

1. **`code:` binds** — they take the `sMkKeys` keycode branch and never look at the keysym, so
   shift state is irrelevant. `code:` is the XKB keycode = evdev + 8, and
   `keycodes/evdev` gives `<AE11>`=20, `<AE12>`=21, `<AB10>`=61 — layout-independent physical
   positions (`no` prints them `+`, `\`, `-`). This is what the `code:61` scratch bind already uses.
2. **Name the shifted keysym and keep SHIFT** — `hl.bind("SUPER + SHIFT + underscore", …)` fires,
   because modmask 65 == 65 and `underscore` == `underscore`.
3. **Never** `hl.bind("SUPER + underscore", …)` alone: modmask 64 ≠ 65 → no match. Exact modmask
   equality also means `SUPER+X` never fires while you happen to hold an extra modifier.

Proven on the live session: binding `SUPER + SHIFT + code:61` to `exec_cmd("touch /tmp/keyhit-61")`
created the file on the first press of physical `Alt+Shift+-` — the keycode path is right, modmask
`65` + keycode `61` arrive as designed. If a `code:` bind seems dead, suspect the *action* (see
[height is not a free axis](#height-resize-is-a-no-op-in-dwindle-here)), not the key.

Related parsing notes (`src/config/lua/bindings/LuaBindingsToplevel.cpp::parseKeyString`):
`code:N` leaves `kb.key` empty, so `hyprctl binds` prints the raw `displayKey` for those —
`key: SUPER + code:20` with `keycode: 0` is **normal**, not a failed parse (`keycode:` is the
unused legacy field; the real keycode lives in `sMkKeys`).

---

## Gotchas learned

- **Hand-copied key tables rot.** This file used to carry the full DMS-default inventory, and it
  was wrong in three ways: it listed `SUPER + SHIFT + minus` / `equal` as a working resize pair
  (unreachable on `no` — see [the shift trap](#the-shift-trap-why-supershiftminus-is-dead-on-no)),
  implied the keysym and `code:` forms are interchangeable (keysym `equal` is dead here), and claimed
  every `dms/*` fragment is gitignored. Only six are — `.gitignore` lists `dms/binds.lua`,
  `colors.lua`, `layout.lua`, `cursor.lua`, `input.lua`, `windowrules.lua`; **`dms/binds-user.lua`
  and `dms/outputs.lua` are tracked**. The tables are gone; query live state instead.
- **`dms keybinds set` writes Lua-config-broken actions.** It emits
  `hl.exec_cmd("hyprctl dispatch dms ipc call bar toggle index 0")`, and Hyprland 0.55 parses
  dispatch strings as Lua → `')' expected near 'ipc'`. Upstream
  [#2290](https://github.com/AvengeMedia/DankMaterialShell/issues/2290). Hand-write the
  working form instead: `hl.bind("SUPER + B", hl.dsp.exec_cmd("dms ipc call bar toggle index 0"), { description = "…" })`.
  The CLI still reports `success: true`, so verify with `hyprctl binds` after every `set`.
- **`dms/binds-user.lua` is rewritten wholesale** by `dms keybinds set/remove/reset` and
  Control Center: comments dropped, `[[...]]` normalized, an `hl.unbind()` inserted before
  each bind. Keep prose here, not there.
- **Lua key strings need `+` between modifiers.** Hyprlang's `bind = $mainMod CTRL SHIFT, 1`
  does **not** port as `"ALT + CTRL SHIFT + 1"` — Hyprland rejects it: `hl.bind: failed to
  parse key string: Unknown keysym: "CTRL SHIFT", did you forget a +?`.
  Enter is `"Return"`, not `"Enter"`.
- Lua-registered binds all report as `dispatcher: __lua` with an opaque id, so
  `hyprctl binds` cannot show the command — the source files (or `dms keybinds show`) are
  the reference.
- Hyprland picks Lua vs hyprlang **once at startup**: if `hyprland.lua` exists it wins and
  `hyprland.conf` is ignored (DMS keeps replacing that file with a stub).

---

## Inspecting live

Counts, the modmask census and the full key dump are at the top of this file. What they don't tell you:

```bash
hyprctl binds | grep -B4 -A7 "key: Return"   # is one specific bind registered? (unbinds show by absence)

# `dms keybinds show` is NOT live state — it also lists 8 source:"config" rows lifted from
# hosts/dell.lua (rofimoji, pamixer code:121-123, light code:232/233, SUPER+S, SUPER+SHIFT+S),
# which DMS parses even though the hostname gate skips that file on this host. None are bound here:
hyprctl binds | grep -c "key: S$"            # 0 → both S binds really are unbound

# With the Lua config, `hyprctl dispatch` is eval("hl.dispatch(...)"): hyprlang strings fail with
# "')' expected near '0'". Run a bind's exact action instead, and read geometry around it:
hyprctl eval 'hl.dispatch(hl.dsp.window.resize({x = -100, y = 0, relative = true}))'
hyprctl clients -j | jq -r '.[] | select(.workspace.id==1) | "\(.class) at=\(.at) size=\(.size)"'
hyprctl activeworkspace | grep tiledLayout

# is the key arriving at all? bind a probe — hl.bind("SUPER + SHIFT + code:61",
# hl.dsp.exec_cmd("touch /tmp/keyhit")) — press it, then look for the file.
# NB: a fullscreen window holding a keyboard lock (Chrome) can inhibit binds; probe on a tiled one.

hyprctl reload                       # apply config edits
grep -i "lua error" "$(ls -t $XDG_RUNTIME_DIR/hypr/*/hyprland.log | head -1)"
```

The header word's trailing letters are the bind flags (`src/debug/HyprCtl.cpp`), not state:
`l` locked · `m` mouse · `r` release · `e` repeat (`repeating = true`) · `n` nonConsuming ·
`a` autoConsuming · `d` **hasDescription** (not "no-repeat"!). So `binded` = repeating + has a
description. Unbinds do **not** appear here — verify by absence.

Modmask bits: `1` SHIFT · `4` CTRL · `8` ALT · `64` SUPER (Mod4) — so `65` = SUPER+SHIFT,
`68` = SUPER+CTRL, `69` = SUPER+CTRL+SHIFT, `72` = SUPER+ALT.

---

## Historical: pre-DMS hyprlang binds (`mainMod = ALT`, now deleted)

Kept only so old muscle memory has a paper trail. Source:
`~/.config/hypr/legacy/hyprland.conf` (repo copy of DMS's `.dms-backups` snapshot).

| Modifier | Keys → action |
|---|---|
| ALT | `Return` kitty · `C` close · `E` nautilus · `V` float · `F` fullscreen · `Space` rofi drun · `Tab` rofi · `P` pseudo (dwindle) · `backspace` rofi powermenu · `H J K L` focus · `code:61` special `magic` · wheel ±1 workspace · `mouse:272/273` drag/resize · `B` `pkill -SIGUSR1 waybar` (vestigial) |
| ALT+SHIFT | `4`/`5` hyprshot region/window · `H J K L` movewindow |
| ALT+CTRL | `Return` `kitty pi` · `Space` rofimoji · `H`/`L` movecurrentworkspacetomonitor · `1`–`4` workspace 1–4 |
| ALT+CTRL+SHIFT | `1`–`4` movetoworkspace 1–4 · `code:61` movetoworkspace `special:magic` |
| none | `F1`–`F4` ddcutil per-monitor · `XF86Audio*` pamixer + dunstify |

---

## dell — bare Hyprland, no DMS (`~/.config/hypr/hosts/dell.lua`)

Hand-owned, loaded by `hyprland.lua` only when the hostname is `dell`. The `dms/*`
fragments are DMS-generated **and** gitignored, so they do not exist on that laptop —
this file is the dell's entire keybind set (plus its monitor/cursor/gaps/touchpad rows).
Values ported from `legacy/hyprland.conf` + `legacy/dell.conf`; shape mirrors homepc
where a plain-Hyprland equivalent exists.

| Key | Action |
|---|---|
| `SUPER + Return` · `SUPER + CTRL + Return` | `kitty` · `kitty pi` |
| `SUPER + E` | `nautilus --new-window` |
| `SUPER + Space` · `SUPER + Tab` · `SUPER + CTRL + Space` | rofi drun · rofi `-show` · `rofimoji --action clipboard` |
| `SUPER + X` · `SUPER + SHIFT + P` | `~/.config/rofi/powermenu.sh` · `displaymenu_dell.sh` |
| `SUPER + Q` · `F` · `SHIFT+F` · `SHIFT+T` · `P` · `R` · `W` · `SHIFT+E` | close · maximize · fullscreen · float · pseudo · togglesplit · group · exit |
| `SUPER + H J K L` / arrows (＋`SHIFT` = move) | focus / move window |
| `SUPER + CTRL + H/L` · `SUPER + SHIFT + CTRL + H/L` | focus monitor · move window to monitor |
| `SUPER + 1…9` · `SUPER + SHIFT + 1…9` · wheel | workspace · move to workspace · `e±1` |
| `SUPER + S` · `SUPER + SHIFT + S` | scratch `special:magic` (created empty → `kitty`) |
| `SUPER + ALT + L` | `loginctl lock-session` → hypridle `lock_cmd` → hyprlock |
| `SUPER + B` | `systemctl restart --user waybar.service` (legacy was `pkill -SIGUSR1 waybar`) |
| `code:121/122/123` | `pamixer -t` · `-d 5` · `+i 5`, each with `dunstify` |
| `code:232/233` | `light -U 25` · `light -A 25` |
| `SUPER + SHIFT + 4` · `SUPER + SHIFT + 5` | `hyprshot -m region` · `-m window` |
| `SUPER + mouse:272` · `SUPER + mouse:273` | drag · resize |
| 3-finger horizontal swipe | workspace change |

`SUPER` is the physical **Alt** key on the dell as well — `kb_options =
altwin:swap_lalt_lwin` is set host-wide in `hyprland.lua`, not per host.

### Verify either host's config from any machine

```bash
Hyprland --verify-config                  # this host (homepc: loads the dms/* fragments)
HYPR_HOST=dell Hyprland --verify-config    # the dell branch: hosts/dell.lua
```

`--verify-config` is not a syntax-only check: it reports unknown config keys, nil API
fields and unparsable keysyms (`attempt to call a nil value`, `hl.bind: failed to parse
key string: Unknown keysym`, `unknown config key '…'`).
