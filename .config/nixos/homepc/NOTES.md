# homepc configuration.nix — rationale

Reasoning that used to live in `configuration.nix` comments. The `.nix` files carry
code plus one-line pointers; each pointer names the section (`§ name`) below.
Everything here describes the config **as it stands today**; disabled experiments are
marked as such and their code is still in the `.nix` file, commented out.

Index: [hardware](#hardware) · [wifi-firmware](#wifi-firmware) · [boot](#boot) ·
[memlock](#memlock) · [network](#network) · [readynas](#readynas) ·
[libvirt](#libvirt) · [dms-shell](#dms-shell) · [hyprland](#hyprland) ·
[waybar](#waybar) · [greeter](#greeter) · [udev](#udev) · [wifi-suspend](#wifi-suspend) ·
[llama-swap](#llama-swap) · [strata-logs](#strata-logs) · [lact](#lact) · [systemd](#systemd) · [packages](#packages)

---

## hardware

`hardware.nvidia`:

- **`powerManagement.enable = true`** — experimental. It can break sleep/suspend, but
  it saves the whole VRAM to `/tmp` on suspend, which fixes the corruption/crashes
  seen after wake. `powerManagement.finegrained = false` (per-GPU power-off is
  Turing+ only; this pair is a 3090 Ti + 5070 Ti).
- **`open = true`** — the open kernel module (Turing+, driver ≥ 515.43.04), *not*
  nouveau.
- **`package = unstable.linuxPackages_6_18.nvidiaPackages.latest`** — the kernel *and*
  the driver must come from the **same `linuxPackages` set**; mixing them once failed
  with "inconsistent kernel versions" in the modules aggregator (that is also why
  `boot.kernelPackages` is the same expression). It pinned **6.18.53 LTS + nvidia
  615.71.09 / CUDA 13.4** when written, both prebuilt on `cache.nixos.org`. The nixos-26.05 channel
  only prebuilds nvidia for 6.12/6.18 at **595.71.05 (CUDA 12.x)**, which would break
  the CUDA-13 `llama-cuda` container — hence `<nixpkgs-unstable>`.
  - 2026-09-22: this was `linuxPackages_7_2` (non-LTS) before. The same expression now
    resolves to **6.18.58 + nvidia 615.78.08** (confirmed booted: userspace and the loaded
    open module report the same version) — see the channel pin below, which is what
    actually decides the driver build today.
  - Still-disabled alternatives in the file: `config.boot.kernelPackages.nvidiaPackages.beta`
    and a hand-rolled `mkDriver` for the 570.124.04 legacy branch.
- **`nvidia-smi` segfaulting (`rc=139`) is a patchelf bug, not a GPU failure** — hit
  2026-10-25/26, and it fails *silently* for anything that shells out to the binary: the
  temp-monitor dashboard simply stopped showing its `gpu_N` cards. Diagnose before touching
  the driver:

  ```bash
  nvidia-smi -L                                                  # rc=139 + "Segmentation fault" = this bug
  readelf -lW "$(command -v nvidia-smi)" | awk '/LOAD/{print}'    # RW LOAD overlapping the R LOAD that holds .dynamic
  ```

  [NixOS/nixpkgs#576412](https://github.com/NixOS/nixpkgs/issues/576412): patchelf 0.19.2
  handed `--interpreter` **and** `--set-rpath` in one invocation emits an ELF whose writable
  `LOAD` runs into the read-only one holding `.dynamic`, so `ld.so` segfaults in `dl_main`
  *before* any NVIDIA library loads. The kernel module, `/dev/nvidia*`,
  `/proc/driver/nvidia` and NVML itself (`ctypes` → `libnvidia-ml.so.1`) were all healthy the
  whole time — so **do not** work around it by rewriting consumers to call NVML.
  The crashing binary was
  `/nix/store/liy6bd3ijqgc7pnr8mfh4zx6cig7fr8h-nvidia-x11-615.78.08-bin/bin/nvidia-smi`
  (1982 `coredumpctl` entries over the two days, plus two `ld-linux-x86-64` cores at the
  same moments — the loader dying, not the driver).
- **Fixed upstream in the builder, not in patchelf** — since 2026-10-21
  [PR #576397](https://github.com/NixOS/nixpkgs/pull/576397) splits the call in
  `pkgs/os-specific/linux/nvidia-x11/builder.sh` (`--set-rpath`, then `--interpreter`
  separately), so any current `nixos-unstable` gives a working `nvidia-smi`. The upstream
  patchelf bug itself is only half closed:
  [patchelf#672](https://github.com/NixOS/patchelf/pull/672) merged 2026-10-20 but is
  **unreleased** — nixpkgs still ships patchelf **0.19.2**, [patchelf#674](https://github.com/NixOS/patchelf/issues/674)
  and [#576412](https://github.com/NixOS/nixpkgs/issues/576412) are still open, and the
  `autoPatchelfHook` path stays broken for non-PIE binaries (worked around per-package with
  `patchelfFlags = [ "--page-size" "2097152" ]`). Only the NVIDIA binaries are covered.
- **Channel pin history (2026-10-26 → 2026-10-28, now REMOVED).** Root's `nixpkgs-unstable`
  was pinned to rev `d059931ba096` (the first rev carrying #576397). It was never about the
  GPU after that fix reached the tip: the tip renamed `dms-shell → dux-shell` 2.0.0
  (`pkgs/by-name/du/dux-*`, aliases kept in `pkgs/top-level/aliases.nix`) and the local
  preview-path patch stopped applying. It was re-anchored for 2.0.0 (§ dms-shell) and the
  channel unpinned on 2026-10-28 — Flow A build on `nixos-unstable`
  `26.11pre1103272.31ecbaca1bde`, `dux-shell`/`dux-greeter` 2.0.0 in the closure. If a future
  tip again breaks the DMS pairing, that pin is the escape hatch; a root-level channel
  setting is invisible in this repo, so record it here the moment it changes.
- `modesetting.enable` is commented out (the channel default already enables it).
- `nvidia.prime` (offload + the two bus IDs) is commented out — this is not a laptop
  Optimus setup; both cards are always present.
- `nvidia-container-toolkit.enable = true` gives the `--device nvidia.com/gpu=all`
  CDI hook used by the llama-swap backends ([§ llama-swap](#llama-swap)). Separate bug,
  same binary: the CDI-injected `nvidia-smi` is **not runnable inside the Strata image**
  (its `PT_INTERP` is a `/nix/store` path absent there) — § llama-swap/strata.
- After a driver/kernel bump the **userspace and loaded module versions can disagree until
  reboot**; the 2026-10-26 upgrade moved 6.18.57 → 6.18.58 and GPU workloads kept running on
  the old loaded module while `nvidia-smi` already reported the new one. `cat
  /proc/driver/nvidia/version` (loaded) vs `modinfo -F version nvidia` (on disk) tells
  them apart; compare `/run/current-system` and `/run/booted-system` by **full store path**,
  not version string (they can share a version string and still differ).
- `graphics.extraPackages` = `intel-media-driver` + `vpl-gpu-rt` (the iGPU's
  Quick Sync/oneVPL stack); `bluetooth`, `i2c` are plain enables, matching the
  `i2c-dev` kernel module used by `ddcutil`.

## wifi-firmware

**DISABLED 2026-09-20 — rolled back to stock `linux-firmware` (c106).** The `let`
binding `linuxFirmwareNoC102Newer` (top of `configuration.nix`) plus the commented
`hardware.enableRedistributableFirmware` / `hardware.firmware` overrides are a test
harness for the Intel BE200: stripping `iwlwifi-gl-c0-fm-c0-c106.ucode` and `…-c103.ucode`
from `linux-firmware` forces the driver back to **c102**, to compare firmware
revisions side by side. Un-comment the `let` binding *and* the two overrides together
to re-run the test; leave them alone otherwise (the `let` binding is unused, so it
costs nothing but must not be referenced by live code).

## boot

- **`pci-stub` (initrd modules + `pci-stub.ids=10de:22e9,10de:1aef` + the two
  `driver_override` udev rules).** `pci-stub` claims the two headless NVIDIA
  HDMI-audio functions (5070 Ti `10de:22e9`, 3090 Ti `10de:1aef`) so `snd_hda_intel`
  can never bind them. Their codecs are power-gated (no display attached), so the
  first HDA verb times out — `azx_get_response timeout, switching to polling mode` →
  `irq 17: nobody cared … Disabling IRQ #17`. MSI is off for both (they are
  `vga_switcheroo` audio clients), so they share the legacy PIC **IRQ 17**, which the
  kernel masked after ~200k unhandled interrupts. It is in the **initrd** so the claim
  precedes `snd_hda_intel` being loadable at all. Audio is unaffected — the sinks are
  the iGPU/PCH card3 (HDMI) and USB Audio. **To revert:** drop the two `initrd` lines,
  the `pci-stub.ids` kernelParam, and the `driver_override` udev rules.
- **`consoleLogLevel = 3`.** Silences the two Intel DPTF/DTT `ACPI BIOS Error (bug)`
  pairs printed at boot *and* reboot:
  - `\_SB.PC00.LPCB.HEC.DPTF.FCHG AE_NOT_FOUND` → aborts `\_SB.IETM.CHRG.PPSS`
  - `\_TZ.ETMD AE_NOT_FOUND` → aborts `\_SB.IETM._OSC`

  They are bugs in this BIOS' AML, not in our config, and ACPICA prints them
  unconditionally at `KERN_ERR`. Verified: `acpi.debug_level=0` does *not* gate them
  (`ACPI_MSG_BIOS_ERROR` is hard-coded `KERN_ERR`). Dropping the console loglevel
  4 → 3 hides exactly `KERN_ERR` from the console; `KERN_CRIT` and worse (panics)
  still print and nothing is lost from the journal — `journalctl -k -p err`.
  **Revert:** delete the line (back to default 4).
- **`kernelPackages = unstable.linuxPackages_6_18`** — must be the same set as
  `hardware.nvidia.package`, see [§ hardware](#hardware).
- `blacklistedKernelModules = [ "spd5118" ]` — SPD5118 (DIMM EEPROM) driver, no
  rationale recorded in the old comments.
- `loader.systemd-boot.consoleMode = "max"`, `loader.timeout = 0`, and the
  `quiet splash … reboot=pci,cold` kernel params.
- `kernel.sysctl vm.blockdev.readahead = 2048` pairs with the `read_ahead_kb=2048`
  udev rule for `nvme0n1` ([§ udev](#udev)).
- `extraModprobeConfig` with `NVreg_PreserveVideoMemoryAllocations=0` is commented out;
  its own inline note was "disabled — `powerManagement.enable = false` handles this".

## memlock

`security.pam.loginLimits` (memlock unlimited for `javi`) + `DefaultLimitMEMLOCK=infinity`
in `systemd.user.extraConfig`:

- Strata and Maya both `mlock()` their expert arena and ask for `MAP_HUGETLB`; both
  need a real `RLIMIT_MEMLOCK`. A rootless container's `CAP_IPC_LOCK` does **not**
  count against `init_user_ns`, so the capability is not enough.
- Rootless podman inherits the **user manager's 8 MiB default**, so the unit's
  `--ulimit memlock=-1` is dropped silently and the engine logs
  `mlock failed (raise ulimit -l)`.
- Chain: PAM raises javi's hard limit at login → the user manager hands it to its
  units (`podman.service` → `crun` → container).
- Needs a **re-login** for the limit; the hugepages need a **reboot**.

## network

`:8080` is llama-swap, the single front door; it publishes its backends on 5800+
(`startPort`), which the firewall leaves closed. `8080` itself is opened by
`services.llama-swap.openFirewall`, so the port is declared in exactly one place.
`interfaces.enp3s0.mtu = 9000` (jumbo frames) and the `wireless.enable` override are
left commented out.

## readynas

`/mnt/readynas-media` NFS mount:

- Mounted **on first access** (`noauto` + `x-systemd.automount`), never at boot, so an
  absent NAS cannot slow or fail boot (`nofail` + `x-systemd.mount-timeout=30`); it
  unmounts itself after 10 min idle (`x-systemd.idle-timeout=10min`).
- **NFSv3** because the NAS runs `nfsd --no-nfs-version 4`; `nolock` avoids needing
  `rpc.statd`.
- Addressed by **IP** because `readynas` resolves via DNS only, not `/etc/hosts`.

## libvirt

- `virtualisation.libvirtd.qemu.runAsRoot = false` — unprivileged qemu; fixes libvirt's
  "tainted: running with undesirable elevated privileges" warning. Guest files must
  then be owned by `qemu-libvirtd`.
- `users.users.javi.homeMode = "751"` — searchable `$HOME` so `qemu-libvirtd` can
  reach the images in `~/images/omarchy-vm` without opening `$HOME` to the world.

## dms-shell

`programs.dms-shell` is **homepc-only**. It lived in `common.nix` until 2026-10-18;
moving it here keeps the dell on the bare hyprland stack (waybar + dunst + hypridle +
hyprlock) instead of having `dms.service`, matugen theming and DMS's
`org.freedesktop.Notifications` owner everywhere.

- It is the quickshell-based desktop shell (bar, notifications, launcher, lock screen,
  OSD) for the hyprland session. Trial config: the shell's own settings are imperative
  in `~/.config/quickshell/ii/` and `~/.config/hypr` (deployed by `dms setup`); only the
  package/service is declared here.
- **Version pairing.** The nixos-26.05 channel build is **1.4.6, two majors behind**
  upstream, and the module's feature toggles track it. So the shell *and* quickshell
  are taken from `<nixpkgs-unstable>` **together** — Dux Shell **2.0.0** (renamed from
  `dms-shell`/DankMaterialShell upstream at 2.0.0, 2026-10-20; old name kept only as a
  `warnAlias`) + `qs` 0.3.2 — because mixing shell and quickshell across sets risks QML
  calling into `qs` APIs that do not exist yet. Both are on the tip and unchanged there.
  **The option namespace stays `programs.dms-shell`** (and `services.displayManager.dms-greeter`):
  the NixOS *module* is evaluated from the **nixos-26.05 channel** — only packages come from
  `<nixpkgs-unstable>` — and 26.05 has no `programs.dux-shell` at all, so writing the new name
  fails with "The option `programs.dux-shell` does not exist". When the system's modules move
  to 26.11, rename the options *and* drop the feature toggles (next bullet).
- **Local patch** (`./patches/dux-preview-path.patch`, added 2026-10-24 as
  `dms-preview-path.patch`, re-anchored for 2.0.0 on 2026-10-28): Settings →
  Browse Themes builds every card's preview URL from the official registry
  (`…/dux-plugin-registry/master/themes/<id>/preview.svg` since 2.0.0; the AvengeMedia URL
  before it) and ignores the `previewPath` the daemon already resolves for third-party
  registries (core/internal/themes/registry.go stats `themes/<id>/preview.svg` in the local
  clone), so all `omarchy-*` cards render blank. That is the two-line fix. Still needed at
  v2.0.0 — `themePreviewUrl()` (ThemeBrowser.qml:113) has no `previewPath` branch. Drop the
  override once upstream ships it: check for `theme.previewPath` in
  `quickshell/Modules/Settings/ThemeBrowser.qml` of the new tag.
  The `postPatch` wrapper needs its own care: nixpkgs sets
  `sourceRoot = "${src.name}/core"`, the QML tree is one level up, and the fetched tree is
  read-only → `chmod -R u+w` before `patch`. It is a **build-time** fix: neither 1.6.3 nor
  2.0.0 installs the QML into the output (no `share/quickshell/dms/…` in either package;
  the tree is compiled into `bin/dms`, `tags = [ "withshell" ]`), so verify it took by the
  build log printing `patching file quickshell/Modules/Settings/ThemeBrowser.qml` — a failed
  hunk fails the build outright, since `patch -N --batch` exits non-zero on a reject.
- **Second local patch** (`./patches/dux-registry-filter.patch`, added 2026-10-30; it applies after
  the preview one, with its hunks 4–6 landing on a 6-line offset): Browse Themes merges every
  configured registry into **one flat list** and the theme JSON carried no registry name at all
  (`ThemeInfo.SourceDir` is the directory *inside* a registry, not the registry), so with `omarchy`
  added there was no way to see only its 186 themes. The patch adds `Theme.SourceName` /
  `ThemeInfo.sourceName` — `loadThemesFrom` takes the `registries.Source` now, and the name rides
  into an installed `theme.json` as provenance — and puts a second `DFilterChips` row under
  All/Installed/Available: one chip per registry, counts that respect the search and the status
  chips, row hidden while only one registry is configured — plus a `store` badge on each card. Probed
  against the live cache (`/tmp/dankdots-plugin-registry`): official 47, omarchy 186, none
  mislabelled; Qt 6.12 `qmllint` on the patched QML is clean, and the package's `checkPhase` runs the
  two touched Go packages, whose `TestUpdateMultiRegistry` the patch teaches about dedupe-vs-source
  pairing. Drop it once upstream carries a registry name: look for `sourceName` in
  `core/internal/server/themes/types.go` of the new tag — and if upstream names it differently,
  re-anchor the QML half to that name too.
- **Third local patch** (`./patches/dux-empty-mode-palette.patch`, added 2026-10-30; order
  immaterial for it — it touches `Common/Theme.qml`, neither of the other two does):
  `Theme.resolveCustomTheme` (`Common/Theme.qml:1493`) takes the mode block by `||`, and `{}` is
  **truthy** in JS, so a theme shipping `"light": {}` — what an honest dark-only palette used to
  look like — got *nothing* for the light mode: the cross-mode fallback never fired, every role
  resolved to undefined, each `property color` took the undefined as no assignment at all, and the
  shell looked applied while painting nothing (the symptom: "applying an omarchy theme changes the
  wallpaper and nothing else"). The patch puts a `modeColors()` that guards the empty block by
  `Object.keys().length` rather than by presence, so an **empty** block counts as **absent** and the
  theme resolves its other mode's own palette. Live-proved end to end, in the running shell, with
  its control: the *active* theme's own installed `theme.json` doctored (`light` emptied, `dark`
  kept) → the shell's *own* `FileView` watcher (`onFileChanged → reload() → onLoaded →
  parseAndLoadTheme()`) took it → the bar band sampled as **184726 px of the dark `surface`
  `#232136`** while the session stayed **light**; the real file put back → the same band back to
  **207893 px of `#e9e9eb`**. No setting write, no scratch dir, one file doctored and restored.
  Worth the *why what first attempt proved nothing*: `settings set customThemeFile` writes the
  setting and nothing else; only `switchTheme("custom")` (`:1415`) re-routes
  `loadCustomThemeFromFile`, which is what re-points `customThemeFileView`.
  The guard is what bites for a theme carrying **nothing** for a mode (the official registry's own
  dark-only ones, anyone else's); this machine's registry ships **both** modes per theme since
  `tool/build.py:synth_other_mode`, so nothing here needs it. Sibling gaps left
  patched-by-nobody: the same `||` shape below in `resolveCustomTheme`'s variants branch
  (`flavor[colorMode] || flavor.dark || …`), and in `ThemeBrowser.themePalette()`
  (`(Theme.isLightMode ? theme.light : theme.dark) ?? theme.dark`), which shows a dark-only theme's
  card swatches blank in a light-mode browser. Drop it once upstream guards the empty block: look
  for `Object.keys` near `baseColors =` in `resolveCustomTheme`, of the new tag.
- **2.0.0 renames that do *not* reach this config** (release notes: package names, binary
  names and systemd units are unchanged): `dms`, `dms.service`, `bin/dms-greeter` all stay,
  and both new attrs set `meta.mainProgram` (`dux-shell` → `dms`, `dux-greeter` →
  `dms-greeter`), which is why `lib.getExe unstable.dux-greeter` in the forced greetd command
  still resolves. What does change for us: the desktop files and window class move to the app
  ID **`dev.duxlabs.shell`** (was `com.danklinux.dms`) — the rule in
  `~/.config/hypr/dms/windowrules.lua` is DMS-generated and gitignored, so DMS rewrites it;
  and user config/state/cache move from `DankMaterialShell` to `dms` on first run with the old
  paths left as **symlinks**, which is what keeps the greeter's `configHome` copy
  (§ greeter) resolving.
- **`systemd.enable = true`**: `dms.service` ships in the package
  (`lib/systemd/user/dms.service`) and the module pulls it in through `systemd.packages`.
  uwsm brings up `graphical-session.target`, which the unit is `PartOf`/`Requisite` of,
  so the module's default target is correct for the uwsm hyprland session.
  `restartIfChanged = true` restarts it on config changes.
- Feature toggles: `enableSystemMonitoring` (dgop: CPU/RAM/net widgets + process list),
  `enableDynamicTheming` (matugen: wallpaper → DMS/rofi/gtk palette),
  `enableCalendarEvents` (khal; needs `~/.config/khal`), `enableClipboardPaste`
  (wtype for Shift+Return in clipboard history).
  They are **26.05-module** options, and the packages they add come from the **channel**, not
  from unstable — `dgop 0.2.2`, `matugen`, `cava`, `khal`, `wtype`, `glib`/`networkmanager`
  (`optionalPackages` in the 26.05 module) — so the shell 2.0.0 runs against a channel dgop.
  That skew predates the 2.0.0 bump; it is the thing to look at first if the CPU/RAM/net
  widgets stop updating. In nixpkgs ≥ the 2.0.0 module every one of these is
  `mkRemovedOptionModule` (monitoring/theming/cava are built in, matugen and cava move into
  the package with `programs.dux-shell.excludePackages` to drop them, and a calendar backend
  must be installed separately) — so these assignments become hard errors the moment the
  system's modules pass 26.05.
- **`enableVPN = false`** — the VPN widget drives NetworkManager, which is inactive
  here (plain iwd).
- **`enableAudioWavelength` is deliberately left at its default (true → installs cava).**
  It was pinned to `false` here until 2026-10-18, which is the only reason `dms doctor`
  reported "cava: Missing" (the doctor treats cava as an important dep and warns
  whenever it is off PATH, whether or not the visualizer widget is used).
  **Do not re-add the assignment:** newer nixpkgs removes the option entirely (cava is
  unconditional in `programs.dms-shell`'s environment), so the assignment breaks the
  build on the modules past 26.11 (§ dms-shell). `CavaService.qml` still gates the process on the
  widget actually asking for it, and `DMS_DISABLE_CAVA=1` disables it.

- **The app-side theming halves — the `gtk-theme` wire (wired 2026-10-30, no new patch).**
  The shell paints its own chrome off the theme JSON per mode (capture-proven), paints
  Hyprland's borders/glow/group bars off the theme's `primary` through the generated
  `~/.config/hypr/dms/colors.lua` (the accent is **mode-invariant by matugen's own design** —
  monolith holds `#9ccfd8` in *both* mode schemes, so flipping modes changes those borders
  **nothing**, which alone reads as "the window chrome didn't switch"), and — the part that
  was **silent** here — was meant to paint **other people's windows** through two wires of
  its own:
  - `Common/Theme.qml` **`refreshGtkTheme`** writes dconf `org.gnome.desktop.interface`
    `gtk-theme` = `adw-gtk3` in light / `adw-gtk3-dark` in dark, and its own comment there
    names who obeys: *"toolkit-following apps (Chromium without a portal) latch on it"*.
  - `Services/PortalService.qml` **`setSystemColorScheme`** writes the same schema's
    `color-scheme` = `default` light (or `prefer-light` when the portal sits dark) /
    `prefer-dark` dark, for portal-following apps — and **that half was never a patch
    candidate: it is the `SettingsData.syncModeWithPortal` setting, on here since ever**, and
    measured publishing on every flip (`dconf color-scheme` read `'prefer-dark'` right after
    `dms ipc theme dark`, `'default'` through light).
    **And the shell's own mode here is auto, on since ever** — read straight off the daemon's
    own socket (`/run/user/1000/dms-<pid>.sock`, which *greets* every connection with a
    `{"apiVersion":38,"capabilities":[… "theme.auto" …}` hello before it will take a
    `{"id":1,"method":"<full.dotted.method>","params":{}}` line — `dms ipc` itself never
    reaches these: its `call` path goes to **the shell's** IPC socket, and `theme` is not one of
    the targets that `qs ipc show` lists, so `dms ipc call theme auto.getState '{}'` answers
    **"Function not found."** from the *shell*, while the *daemon* serves the method fine):
    `{"config":{"enabled":true,"mode":"location","startHour":18,"startMinute":0,"endHour":6,
    "endMinute":0,"useIPLocation":true,"elevationTwilight":-6,"elevationDaylight":3},
    "isLight":false,"nextTransition":"2026-10-31T08:02:36+01:00"}` — sunset measured 16:03:30,
    and **the session sitting dark is the auto-correct state at 16:3x, not an accident of the
    test flips**. **`PortalService.canSyncColorScheme` returns false while auto is on**, so
    *portal* transitions never drive the shell here: the `color-scheme` DMS publishes rides
    DMS's **own** location clock, and no other publisher's value moves it.

  **Neither GTK3 wire could run, for exactly one reason:** `refreshGtkTheme` is called *only*
  when `patchGtk3colors` exits **0**, and `scripts/gtk.sh` patches the theme **in place**,
  which needs **a user-writable copy of `adw-gtk3{,-dark}`** under `~/.local/share/themes` —
  `ensure_user_adw_gtk3` copies from `get_system_adw_gtk3_root` (walked over
  `$XDG_DATA_DIRS`-derived `…/share/themes` roots) into `$XDG_DATA_HOME/themes/adw-gtk3{,-dark}`
  with a `.dms-copy` `src=`+`sha256=` marker — and the **colour work that actually repaints
  other windows is the `patch` mode's `BEGIN DMS OVERRIDE … END DMS OVERRIDE`
  `@define-color` blocks re-sed into the copy's own stylesheets** (`gtk.css` for the light
  pick, `gtk-dark.css` for the dark), backing them up as `.dms-backup` first. Measured after
  one dark flip: `adw-gtk3-dark/gtk-3.0/gtk.css` **and** `adw-gtk3-dark/gtk-3.0/gtk-dark.css`
  carry **one** OVERRIDE block each, while `adw-gtk3/gtk-3.0/gtk.css` carries **none** *yet*
  (the next light-mode `patch` writes its own).
  **The `@import url("dank-colors.css");` first-line is a different, user-level route —
  `~/.config/gtk-{3,4}.0/gtk.css` — which nothing here has ever taken**: **no user-level
  `gtk.css` exists** under `~/.config/gtk-3.0` or `~/.config/gtk-4.0` at all (both hold
  matugen's own `dank-colors.css`, written fresh every matugen run — 827 B gtk-3.0, 2 KiB
  gtk-4.0 — plus `settings.ini` (`[Settings]` + `gtk-icon-theme-name=macOS-White`, 43 B),
  **unimported and inert**), and `inject_dank_import`'s own comment is the contract: *gtk.css
  is DMS-managed if it is our symlink or carries our import line*, with the `else`-branch
  **creating** it outright (`echo "$DANK_IMPORT" > "$gtk_css"`), while the script's `remove`
  path (`remove_gtk3_colors`) `remove_dank_import`s that same user-level file. So *those*
  *copies* carry **zero** import lines, on purpose. **With no system copy to copy
  from** — both `$XDG_DATA_DIRS` `share/themes` roots **empty**, no `~/.themes`, no
  `~/.local/share/themes` — `gtk.sh patch` exits **2 = "nothing patched", silent**, so
  `refreshGtkTheme` never runs, the `gtk-theme` key is **never written**, and
  `~/.config/dconf/user` held **no `gtk-theme` key at all** as the fingerprint. The symptom
  reads as *"light and dark stopped working"*: every window outside the shell keeps its own
  look however the shell's mode flips, while the shell's own chrome follows it perfectly.

  **Wired by: `pkgs.adw-gtk3`** ("Unofficial GTK 3 port of libadwaita", **6.5**, present in
  the pinned 26.05 input at `pkgs/by-name/ad/adw-gtk3/package.nix`; **one package ships both
  variants**) — appended **dead last** of `environment.systemPackages` in `common.nix`, dead
  last rather than reordered into the main list, per the system-path `buildEnv` re-hash
  warning written up there. Then **DMS's own button**, Settings → Themes → Apps → *Apply GTK
  colors* (`Modules/Settings/ThemeAppsTab.qml:74 → Theme.applyGtkColors()` →
  `gtk.sh <configDir> apply <isLight>`; that tab carries **no IPC route**, so only the user
  pressing it 2026-10-30 could do it) **made the copies**: both
  `~/.local/share/themes/{adw-gtk3,adw-gtk3-dark}/` at once, each `gtk-3.0/`+`gtk-4.0/`+
  `index.theme`, each `.dms-copy` carrying `src=/run/current-system/sw/share/themes/…` +
  `sha256=…` verbatim, and the `.dms-backup` pairs from the next `patch`.

  **The next mode flip did the rest, through the mode's own IPC verbs** — `dms ipc theme`
  carries **`dark`, `light`, `getMode`, `toggle`**, which is the way to set the mode without
  touching the UI — matugen regenerated, `gtk.sh patch` **found the copies**, **exited 0**,
  `refreshGtkTheme()` ran, and **`dconf gtk-theme` read `'adw-gtk3-dark'`** in the dark beat.
  **GTK3 mirrors dconf live all by itself**, through its own `GtkSettings` GSettings backend:
  a **running** nautilus (GTK3, the *Files* window) **repainted fully dark with no restart**
  in that same flip — dark sidebar, dark headerbar, dark path bar, sampled by capture — and
  the shell and the borders darkened in the same beat. **There is no XSETTINGS owner here**
  (Hyprland provides none) **and none is needed for GTK3**.

  **Chromium is the exception and it is not fixable from `~/.config/nixos` or from the
  registry.** *Latched at startup* — proven, twice, against a running window: it ignored
  `gtk-theme → 'adw-gtk3-dark'` written to dconf while it ran, and it then ignored a
  **transient `pkgs.xsettingsd` (1.0.2) run out of `nix-shell`, never installed**, owning
  XSETTINGS as `Net/ThemeName "adw-gtk3"` (`xsettingsd -c /tmp/shot/xset.conf`, alive as one
  pid), then a rewrite of that conf to `"adw-gtk3-dark"` + `pkill -HUP xsettingsd` (the
  ArchWiki live-reload recipe) — Chrome stayed light through **both** live wires. Its
  `~/.config/google-chrome/Default/Preferences` holds **no** color-scheme / dark-mode /
  theme pref at all — the only theme-shaped keys are
  `should_read_incoming_syncing_theme_prefs=false` and
  `syncing_theme_prefs_migrated_to_non_syncing=true` — and its own
  `chrome://settings/appearance` deep-link opens into a Google **"Who's using Chrome?"**
  interstitial before it shows anything. So: **Chrome repaints per mode only when Chrome
  restarts after the key flips** — the key *does* now flip itself, per mode — and the shape of
  a keybind that also relaunches it (`dms ipc theme toggle; pkill chrome; (google-chrome &)`,
  `~/.config/hypr/dms/binds-user.lua` is the user's own hand-written binds file and the place
  such a line would live) is **the user's to love**; nothing here or in the registry changes
  that. Browser truth for the profile record: `xdg-mime query default text/html` →
  **`google-chrome.desktop`**, and `~/.mozilla` holds **no firefox profile at all** (only
  `native-messaging-hosts/com.1password.1password.json`), so DMS's generated
  `~/.config/dms/firefox.css` — Material chrome CSS, freshly carrying the *light* scheme,
  `--md-sys-color-on-primary: #1b1b1d` and friends — is **linked into nothing**, and no
  `userChrome.css` exists under `~/.mozilla`/`~/.var/app`/`~/.config` at all (`~/.var/app`
  does not exist).

  **Probe hygiene from that live test, so the record stays the machine's own state:** the
  hand-written `color-scheme 'no-preference'` + `gtk-application-prefer-dark-theme false`,
  and later `'prefer-dark'` + `true`, and the `gtk-theme 'adw-gtk3-dark'` probe were all
  **reverted** (`dconf reset …/gtk-theme` → the key unset again; and note the *reset* not the
  *write* — there was **no value** there to restore, ever); **`gtk-application-prefer-dark-
  theme` carries no key again** (nothing here has ever written it, and **neither** of the
  two live wires moves Chrome is that key — the probe pair moved *no*thing outside the shell
  at the time); the probe-launched gedit (a GTK3 text editor, from `environment.systemPack-
  ages`) was closed again — and mind the `pkill -f 'gedit'` self-match: the pattern matches
  **the calling shell's own cmdline**, the call killed itself at exit **143** before reaching
  later steps; use `pkill -x gedit`. The xsettingsd probe's nix-shell died with the call.

  **Drop tests / future-module notes.** Past 26.05 the *options* move as the § above already
  records; the **wires** to re-anchor on 2.0.0-ist tips: `refreshGtkTheme`'s
  `GSettings.setCmd(schema, key, isLight ? "Adwaita" : "HighContrastInverse")` **reset-then-
  apply pair** — the `HighContrastInverse` value is the tell, per the code's own comment it's
  a *same-polarity built-in intermediate* the toolkit-followers latch on — and
  `PortalService.setSystemColorScheme`'s `preferLight ? "prefer-light" : "default"` ternary
  (`'prefer-light'` is **not** a classic GNOME schema value; the `gtk` portal impl is
  1.15.3 old here, and an unknown string maps to no-preference, i.e. light — worth re-reading
  the impl's mapping before chasing that value). `Common/GSettings.js` is the shape the
  writes ride: `setCmd` = `GSETTINGS_BACKEND`-guarded `dconf write <path> "'<value>'"` `||
  gsettings set …` with `getCmd` reading-and-stripping quotes — **a bool key must be passed
  bare** (`"true"`, not `"'true'"`, or dconf rejects the type and the `gsettings` fallback
  misparses it). **`scripts/gtk.sh`'s copy/marker/inject contract above** is what a future
  DMS may rename — re-read `ensure_user_adw_gtk3`/`inject_dank_import` before trusting the
  copies' `.dms-copy` `sha256=` markers to *auto-refresh* on a system-theme change (they do:
  a changed store hash refreshes the copy, by design).
  **`home-manager` has carried a `services.xsettingsd` module the whole time**
  (`~/.nix-defexpr/channels/home-manager/modules/services/xsettingsd.nix`: `settings` an
  `attrsOf (oneOf [bool int str])` with the `"Net/ThemeName"` example, `configFile` an
  `internal`+`readOnly` `pkgs.writeText` (**a store path — nothing at runtime can `sed` it**,
  so no per-mode rewrite rides that module), the unit `After=graphical-session-pre.target`,
  `PartOf=graphical-session.target`, `Restart=on-abort`, `ExecStart` baking the store conf
  in with `-c`) — **not enabled here**, and **it would not help Chrome anyway** (proven two
  wires up); its right shape is only for X11/XSETTINGS-following apps, of which this machine
  has none.

## hyprland

Hyprland **0.56+** is needed for DMS compositor blur (`ext-background-effect-v1`).
The channel (nixos-26.05) ships **0.55.4**, which predates
`src/protocols/BackgroundEffect.cpp`; 0.56.2 is the first release with the global, so
`dms doctor`'s "Background Blur: Unsupported" is *unfixable by config* on 0.55 — DMS
probes the Wayland registry for `ext_background_effect_manager_v1`
(core/internal/blur/probe.go).

Same channel-mixing trick as [§ dms-shell](#dms-shell): take the compositor **and** its
portal from `<nixpkgs-unstable>` as a pair (hyprland 0.56.2 +
xdg-desktop-portal-hyprland 1.4.1) while the *module* stays the channel's (0.56.2 adds
no breaking config changes, and the Lua `hyprland.lua` works). Scoped to homepc — the
dell keeps the bare channel stack.

Note this also moves the **DMS greeter's** compositor, because
`services.displayManager.dms-greeter` builds its session from
`config.programs.hyprland.package`. If 0.56 misbehaves at the login screen, drop these
two lines and rebuild to get 0.55.4 back.

## waybar

DMS draws its own bar, so homepc drops the waybar unit's `WantedBy`
(`programs.waybar` stays enabled in `common.nix`). The package and
`~/.config/waybar/homepc.jsonc` remain; deleting this line brings the bar straight back
on this host only.

## greeter

The DMS greeter (greetd-backed) replaces **SDDM** on this machine. Scoped to homepc
while trialing: a broken greeter means no graphical login, so the dell keeps sddm until
this is proven. To roll it out, move the block into `common.nix` and drop the sddm
`mkForce` there instead. `sddm.enable = lib.mkForce false` overrides the enable in
`common.nix`.

- **`package = unstable.dux-greeter`** — the greeter has always shipped as its own package
  (`bin/dms-greeter` unchanged through the 2.0.0 rename, and `meta.mainProgram` is set, so
  `lib.getExe` still finds it). The module default would be `programs.dms-shell`'s package,
  whose build no longer contains the Greetd assets this module execs — same reason applies to
  2.0.0, which installs no `share/quickshell/dms` tree at all.
- **`compositor.name = "hyprland"`** — the greeter runs inside hyprland (the module
  asserts `programs.hyprland.enable` and uses `programs.hyprland.package`).
- **`compositor.customConfig` must be LUA (`hl.*`), not hyprlang.** The greeter runs
  hyprland as the `dms-greeter` user, which has no config of its own, so Hyprland would
  default to a US layout at the login screen. dms-greeter sniffs the `-C` file
  (`launcher.isHyprlandLuaConfig`: a `.lua` suffix or a `(^|[^[:alnum:]_])hl\.` match)
  and writes the config it hands Hyprland as either `$TMPDIR/dms-greeter-*.lua` or, in
  the hyprlang branch, `$TMPDIR/dms-greeter-1234567890` with **no extension at all**.
  Hyprland picks the config manager by that extension (src/config/ConfigManager.cpp:
  anything not `.lua` → Legacy/hyprlang manager), and the legacy manager paints the
  on-screen "You are using the .conf config format, support for which will be removed
  in Hyprland 0.57." notification — which is why that nag only ever showed on the login
  screen while the session itself is driven by `~/.config/hypr/hyprland.lua`. Hyprland
  0.57 drops hyprlang outright, so a `.conf` greeter config would stop being read at
  all, warning or not.
  - Inside that Lua: the cursor theme must come from **env** here — the greeter's
    Hyprland loads no DMS fragment (`dms/cursor.lua` belongs to the session) and
    Hyprland 0.55/0.56 has no `cursor:theme` option at all, so `HYPRCURSOR_*`/`XCURSOR_*`
    are the only mechanism. XCursor only: `apple-cursor` ships XCursor, not hyprcursor.
    The theme package comes from `environment.systemPackages` (`pkgs.apple-cursor`,
    see [§ packages](#packages)) because this `serviceAccount` has no per-user profile.
    Keyboard: `kb_layout = "no"`, `kb_options = "altwin:swap_lalt_lwin"` (mirrors
    `services.xserver.xkb` in `common.nix`).
- **`configHome = "/home/javi"`** — copies `~/.config/DankMaterialShell/settings.json`,
  `~/.local/state/DankMaterialShell/session.json` and `~/.cache/DankMaterialShell/dms-colors.json`
  (plus the wallpapers they reference) into `/var/lib/dms-greeter` at greetd `preStart`,
  so the greeter shows your wallpaper/theme.
- **`defaultSession = "hyprland-uwsm"`, not `hyprland`** — uwsm is what brings up
  `graphical-session.target`, which `dms.service` is `PartOf`/`Requisite` of. Plain
  `hyprland.desktop` would log in with no DMS bar.
- **`services.greetd.settings.default_session.command` override.** The 26.05
  dms-greeter module execs
  `${package}/share/quickshell/dms/Modules/Greetd/assets/dms-greeter`, which only exists
  in dms-shell ≤ 1.4.x, so with 1.6.2 greetd loops on "greeter exited without creating a
  session" until it hits `start-limit-hit`. This replicates the newer (unstable)
  module's invocation: `${package}/bin/dms-greeter --cache-dir /var/lib/dms-greeter
  --command hyprland [-C <lua config>]`, with a `PATH` containing quickshell, the
  configured hyprland and `glib` (gdbus: the fprintd probe + portal reads).
  **Delete this override once the system channel's module uses `bin/dms-greeter`.**

## udev

- `nvme0n1` `read_ahead_kb=2048` — pairs with the `vm.blockdev.readahead` sysctl
  ([§ boot](#boot)).
- NVIDIA/Jetson USB idVendor `0955` → `plugdev` group.
- **`wlan0`/`wlan1` naming by MAC.** The BE200 MLD driver re-registers under a new
  `wiphy` index every time the iwlwifi-reload sleep hook runs ([§ wifi-suspend](#wifi-suspend)),
  which would otherwise leave `wlan2`, `wlan3`, … behind. Pinning the two card MACs
  keeps stable names; iwd follows the device by wiphy, so the (variable) *station*
  interface name is not functionally important.
- **`driver_override="pci-stub"` for `0x10de:0x22e9` / `0x10de:0x1aef`** — belt and
  braces for the initrd claim ([§ boot](#boot)): only `pci-stub` may ever match these
  two HDA functions, so a manual `echo 1 > /sys/bus/pci/rescan` or a hot re-bind cannot
  put `snd_hda_intel` back on legacy IRQ 17.

## wifi-suspend

**The reload hook is DISABLED since 2026-09-24** to test whether kernel 6.18.53 LTS
fixes the BE200 suspend/resume issue on its own. If throughput collapses again after a
suspend cycle, un-comment the `environment.etc."systemd/system-sleep/iwlwifi-reload"`
block.

The problem being worked around: the Intel Wi-Fi 7 BE200 (`iwlmld`) firmware state gets
corrupted by suspend/resume — the link stays nominal (80 MHz 2x2, no retries) but
throughput collapses (~25 up / ~320 down on a 600/600 line) until the driver is fully
reloaded. Unloading the wifi stack before suspend and reloading it after resume
re-initialises the firmware cleanly on every cycle — equivalent to a reboot, without
one. iwd reconnects automatically after the module reloads. Inside the hook: bring all
`/sys/class/net/wlan*` down before `modprobe -r iwlmld iwlwifi` (the MLD driver
registers several interfaces), and note systemd calls post hooks as `post <sleep-type>`
(e.g. `post suspend`), hence the `post/*` match; the station may come back as wlan0 or
wlan1.

## llama-swap

One front door on `:8080` that picks the engine by the requested model name and swaps
the container behind it — **topology A: llama-swap owns every `podman run`**, so only
one backend holds the two cards at a time. Verified against llama-swap v249.

- **`package = unstable.llama-swap` (249) is required**: the `capabilities` key needs
  llama-swap ≥ 225, and the channel's `pkgs.llama-swap` is 224, which drops the unknown
  key *silently* — the YAML carries the block but `/v1/models` never renders it.
- **Model keys are model names, never engine names**: `handleListModels`
  (internal/server/api.go) always emits a record for the key, and `unlisted: true`
  continues *before* the alias loop — it hides the aliases with it. There is no
  "hide the primary, keep the aliases" switch.
- **`${MODEL_ID}` / `${PORT}` are llama-swap macros**: inside a Nix indented string
  they must be written `''${...}` or they reach the YAML doubled.
- **Keep comments OUT of `cmd` strings**: llama-swap renders `cmd` as one YAML scalar
  whose newlines fold to spaces, so a `#` there comments out the rest of the
  `podman run` line (mounts, env, image) and the container never starts.
- **Backends are no longer systemd units** (2026-10-20): llama-swap starts every
  container itself (per-model `cmd`), so the old `llamacpp`/`strata`/`maya` fallback
  units are gone. A hand-run `podman` is the fallback if weights are re-downloaded.
- Settings:
  - `logLevel = "info"`.
  - `logToStdout = "both"` — llama-swap always captures upstream (the `podman run`
    client, i.e. the container's stdout/stderr) in its monitors (`/logs/stream/upstream`)
    but only echoes it to stdout when asked, and `podman run --replace` destroys the
    container on every swap — without this, the previous engine's log is simply gone
    (it ends up in journald). v249 accepts exactly one of `proxy | upstream | both |
    none`; a comma list (`"proxy,upstream"`) is a newer spelling that fails the unit
    with "logToStdout must be one of: proxy, upstream, both, none". `both` also emits
    one access line per request. `logTimeFormat = "rfc3339"`.
  - `healthCheckTimeout = 900` — Strata binds its port only once the model is in
    memory, so this must cover a cold load (Strata `docs/LLAMA_SWAP.md`: 80 s on a
    Tesla V100 with the GGUFs on a SATA SSD, 105 s while a download used the disk). It
    is **global, not per-model** (llama-swap v262's own embedded docs), so Maya's cold
    load sets the floor: Maya pins its 44 GiB RAM tier, copies the starting expert
    profile into VRAM and warms its caches before the port opens — minutes, not
    seconds. Raising it costs nothing on fast backends: it is an upper bound on the
    wait, not a delay.
  - `unloadTimeout = 40` (graceful stop of the `podman run` client and the container),
    `startPort = 5800` (backends get 5800+; only 8080 stays open in the firewall),
    `sendLoadingState = true` (a client waiting through a swap sees "loading …" in the
    reasoning field instead of a silent stall), `includeAliasesInList = true` (no
    aliases right now, but keep them visible if a backend gets them back),
    `globalTTL = 0` (nothing is evicted by a timer; the group swaps on demand).

### llama-swap/lact-temps — local patch (wired 2026-10-30, llama-swap 262)

GPU stats for the Performance page and the `llamaswap_gpu_*` gauges come from **LACT, not
`nvidia-smi`**: `getGpuStats` (`internal/perf/monitor_unix.go`) probes LACT first, and `hardware.lact`
puts the socket at `/run/lactd.sock`, so that probe wins. Falling back to `nvidia-smi` is not a
workaround either — `temperature.memory` is `N/A` for both cards and llama-swap's query
(`index,name,uuid,temperature.gpu,utilization.gpu,…`) does not even ask for it, so the nvidia-smi path
reports **no** VRAM temperature at all.

262's LACT probe reads two literal keys out of LACT's `temps` map — `"mem"` (AMD) and `"VRAM"` — and
leaves `VramTempC = 0` when neither is present. LACT builds those names from NVAPI
(`lact-daemon/src/server/gpu_controller/nvidia.rs`): the aggregate `VRAM` entry only exists when the
driver exposes a VRAM thermal *channel*. Live dump, `lact cli -g <n> stats`:

- 3090 Ti: `GPU`, `GPU Hotspot`, **`VRAM`**, `VRAM Chip A0…F1` — VRAM chart worked.
- 5070 Ti (Blackwell/GDDR7): `GPU`, `GPU Hotspot`, `VRAM Chip A0…D1` — **no `VRAM`** → chart pinned at 0.

The same probe picks `TempC` from a bare map iteration when `edge`/`junction` are missing (they are, on
NVIDIA), so the "GPU Temperature" series alternated between core, hotspot and VRAM-chip sensors —
`llamaswap_gpu_temperature_celsius` for the 3090 Ti read 56 and then 61 seconds apart.

`homepc/patches/llama-swap-lact-temps.patch` (applied in `postPatch`) adds `lactGpuTemp` /
`lactVramTemp`: core temperature prefers `edge`/`junction`/`GPU` and never falls back to a
`vram`/`hotspot`/`mem`-named sensor; VRAM temperature keeps the aggregate keys and otherwise takes the
**hottest** `*VRAM*` sensor, which is the real signal on GDDR7. Tests cover both sensor-name sets. Recheck
on every bump — `patch --fuzz=0` fails the build rather than half-applying. Upstream master (`4af269a`)
still has the same two-key lookup; the probe rewrite in mostlygeek/llama-swap#1264 only makes
unreported values `nil` instead of `0`, it does not add a per-chip fallback.

The override also sets `checkFlags = [ "-skip=^TestServer_APILogEvents_NoHistory$" ]`: that upstream
test is flaky/racy in v262 — it failed 10/10 locally on a **pristine** v262 checkout (`go test
./internal/server -count=10`) and once in the nix build, so without the skip the patched package never
builds here. The rest of the suite, including the new `internal/perf` tests, still runs.

### llama-swap/strata — `qwen3.8-flash-next-iq3_s`

- The key doubles as the podman name via `${MODEL_ID}` — legal under podman's
  `[a-zA-Z0-9][a-zA-Z0-9_.-]*` (a llama.cpp-style `org/name:quant` key would not).
- `--network host`, so the container needs the port llama-swap assigned
  (`docker/entrypoint.sh` passes `PORT` to `strata launch --port`).
- **The 0.2.x image reads `MODEL_PATH`, not `HF_CACHE`** (the latter is unknown to it:
  no warning, just a fresh ~62 GB download into the volume).
- Mounts: `strata-data:/data` holds the pack, the MTP draft and `/data/gguf/IQ3_S`;
  `~/.config/strata/1slot:/data/install` (`XDG_CONFIG_HOME`) keeps the run settings and the
  web app's chat settings host-editable. **One install tree per entry since 2026-10-25**: this
  entry gets `1slot/`, the batch entry gets `parallel/` (was `3slots/` until that tree and its entry were
  removed 2026-10-26; § llama-swap/strata-parallel) — the run
  config, the launch preset and the profile all live under `/data/install`, so the split is what
  keeps one entry's start from rewriting the other's. **Mount the directory, not the file**:
  `setup.py` saves via `<name>.tmp` + `os.replace`, and renaming over a bind-mounted
  file fails with `EBUSY`.
- **The three model files are bind-mounted as FILES** (from the HF cache blobs). They
  used to be symlinks inside the volume pointing at `/hf-cache/…` — a target that only
  exists inside a container — and that silently cost the tuned setup on every start:
  `strata launch` decides whether to reuse the installed run settings with
  `installed_serves_request` (strata_cli/launch/runner.py), which resolves every
  `.gguf` in the config and requires it **inside `MODEL_PATH`**. Resolving a link lands
  in `/hf-cache`, so the answer was no: `setup.py` ran each start, failed to see the
  cards (the image has no runnable `nvidia-smi` — the CDI one from this host is a Nix
  binary whose `PT_INTERP` is a `/nix/store` path that is not in the image), and its
  adopt fallback rewrote `strata-iq3_s.json` from defaults — dropping the layer split,
  the tuned options, the vision section and any `user_args`. Bind-mounting the blobs
  makes those paths real files and that reuse check passes, so the settings stay ours —
  but it is only half of the reuse test, and a preset whose context/KV differ from the
  installed file sends the start through setup anyway (§ llama-swap/strata-p3, parked
  2026-10-25). Within this tree there is one preset again, so nothing disagrees with it here;
  the batch entry disagrees, but it boots on its own install tree (§ llama-swap/strata-parallel).
  **If the model is ever re-downloaded the blob names change:
  relink those three lines** (a missing file makes podman create an empty mount point,
  and the entrypoint then stops with "MODEL_PATH holds no .gguf files" — it refuses to
  download a second copy). The whole hub is **not** mounted any more (nothing in the
  image reads `/hf-cache`, and an HF cache path is not a variable this image knows):
  with no `/hf-cache` in the container, links that point there dangle and the start
  fails loudly instead of quietly sending the launcher back through setup — which is
  how the tuned settings were lost.
- **The cards and the layer split are deliberately NOT env here**: `GPUS`/`LAYER_SPLIT`
  env is ignored by this image or makes setup re-derive the split as "auto". They live
  in the launch preset `~/.config/strata/1slot/strata/launch-presets/docker.json`
  (`"gpus": [0, 1]` plus `extra` carrying `--layer-split 32`, `--trim-stage-weights`,
  `--vram-reserve-* 1024`, `--pipeline-windows 2`, `--spec-min-p 0.70`,
  `--pcie-frac 0.00`, which `derive_config` re-applies to every launch; `"context": 262144`
  and `"kv": "int8"` are top-level preset fields, not `extra`, and they are what the reuse
  test compares); the picture reader lives in `strata-iq3_s.json`'s `"vision"` section
  (see `~/.config/strata/1slot/strata-vision`) and **had** to be re-pasted there by hand after
  every p1↔p3 switch — the p3 pair is gone and its successor boots on its own tree, so this file
  is written only by this entry and the section survives on its own.
- **`--cgroup-conf memory.swap.max=0` (inside `cmd`).** The expert arena here is
  anonymous memory: the engine's `MAP_HUGETLB` ask fails
  ("needed 23983 2 MiB pages, vm.nr_hugepages=0", see `~/.config/strata/1slot/strata-iq3_s.log`)
  and the `MADV_HUGEPAGE` fallback does not land either (`AnonHugePages` stays 0), so
  the 51 GiB arena sits on ordinary 4 KiB anon pages, and anon is reclaimable only
  through swap. `cudaHostRegister PORTABLE` and `mlock` are already in play and still
  left ~1.4 GiB of `strata-host` in swap, so neither is the guarantee;
  `memory.swap.max=0` is: the kernel then refuses to page any of it out, so neither the
  desktop nor `buff/cache` growth can take it. Nothing sets `memory.min` anywhere, and a
  min would need every level from `user.slice` down (effective min is capped by
  ancestors' `memory.min`). *Cost:* a strata that over-budgets is OOM-killed instead of
  thrashing, and pages already swapped when the limit is set are not pulled back
  eagerly — they fault in as the arena touches them and can then never leave again.
- `cmdStop = podman stop -t 120` (a cold strata shutdown is slow), `checkEndpoint = "/health"`, `ttl = 0`.
- `capabilities` render as `capabilities.function_calling = true` plus
  `supported_parameters: ["tools","tool_choice"]` (api.go `renderCapabilities`); without
  it Strata under-reports itself to clients doing capability discovery.
  `context = 262144`, in `text`+`image`, out `text`, `tools = true`.
- No aliases: the key is the public name, and every alias is listed too
  (`includeAliasesInList`) — so the old engine name "strata" is dropped.

### llama-swap/strata-p3 — `qwen3.8-flash-next-iq3_s-p3` (PARKED 2026-10-25)

**Dropped 2026-10-25:** the backend and its launch preset are both out (it lost its `gpu` group
seat to `swift-1.5-iq3_s`, which has since lost its own seat to this idea's second attempt —
§ llama-swap/strata-parallel). The preset is in git at `8e620d7`, the nix entry at `42d8314`;
reviving *this* shape is those two back plus `-e PRESET=docker-p3 -e PARALLEL=3`. Batch 3 itself
is running again, as its own install tree rather than a second preset in this one. Everything
below stays because re-measuring it costs a full engine restart per arm.

What dropping it fixes for free: the two presets disagreed on `context`/`kv` **by design**
(262144/int8 vs 131072/q4_0), which is what made `desc_matches` fail and sent every switch
through `setup.py` — the rewrite that emptied `user_args` and dropped the `"vision"`
section twice (2026-10-25 13:11 and 16:04). With one preset left for this model, the
installed file always already holds p1's own numbers, so the reuse test passes and setup
stops running. The batch entry is that pair again (131072/q4_0 against 262144/int8), but it
cannot reach this file any more — it boots on its own `/data/install` (§ llama-swap/strata-parallel).

The original reasoning, kept for the next time batch is worth trying:

The same model, image, mounts and weights as the entry above, started with **three batch
slots** instead of one — a second llama-swap model so clients pick the mode by name.

- **`parallel` is an engine-start setting, not a request parameter.** It reaches the engine
  as `--batch N`, and **`-e PARALLEL=3` on this backend is what carries it** — the
  entrypoint passes `--parallel 3`, which both overrides the preset at start and writes the
  number back into `docker-p3.json`'s `"parallel"` field. Editing that field is futile: a
  `2` there was back to `3` after the next start (2026-10-25 13:11), and the live engine had
  never seen `--batch 2`. So the only way to have both is two backends, and every switch
  between them is a full engine restart (the load lines differ per mode, see mmap below).
- **`-e PARALLEL=3` alone would have broken the entry above.** The image's entrypoint
  defaults `PRESET` to `docker` and re-saves it whenever settings are given
  (`--save-preset`), so the p3 container would (a) collide with the running
  `launch-docker` profile — `check_serving` refuses with "A model is already running …
  These choices are different" (exit 6), and (b) write `parallel: 3` into the shared
  preset, making the single-stream backend batched on its next start. Hence the second
  launch preset **`~/.config/strata/strata/launch-presets/docker-p3.json`** and
  `-e PRESET=docker-p3`.
- **The preset was copied from `docker.json`, not created by the entrypoint** — a fresh
  preset carries none of the tuned `extra` (`--layer-split 32`, `--pipeline-windows 2`,
  `--spec-min-p 0.70`, `--pcie-frac 0.00`, `--vram-reserve-* 1024`, conversation cache)
  or `gpus: [0, 1]`; only `name`, `parallel`, the context and the KV format differ.
- **Batch mode runs at 128k, not 256k.** Conversation memory is what a slot costs: `int8`
  KV is 1056 B/token over 13 layers (`catalog.kv_gb` / `setup.UD_FIT_KV_BYTES`) = 3.6 GiB
  per conversation at 262144 and 1.8 GiB at 131072, so three slots go from ~10.7 GiB to
  ~5.4 GiB of the KV pool the expert cache also lives in.
  **Two lines do it**: the `extra` line `"--max-context": "131072"`, and `-e CONTEXT=128k`.
  The cap the server obeys is the engine arg (`serve/server.py` reads `--max-context` out
  of them), and `tune_knobs.apply_to_argv` deletes the base config's `--max-context 262144`
  before appending the new one: `derive_config` (strata_cli/launch/runner.py) never puts a
  preset's `context` field into `args`, only its `extra` gets there. What `-e CONTEXT=128k`
  and the preset's `"context": 131072` settle is the **reuse test** (two bullets down) —
  they are what makes setup run, and setup writes 131072 into the shared
  `strata-iq3_s.json`, so that file holds p3's numbers today and p1's next start writes back
  256k. 128k needs no rope scaling and no repack (the trained limit is 256k, `check_context`
  warns only above it).
  `capabilities.context = 131072` on this entry keeps `/v1/models` from promising 256k;
  check with `/v1/status` → `context`.
- Everything else is shared and that is fine because the group keeps one up at a time: the
  `strata-data` volume (API key, `profile-learned.bin`, `/data/state/strata/launch/`), and
  the run settings file `strata-iq3_s.json` — `strata launch` builds its own copy per preset
  at `/data/state/strata/launch/<preset>.json`, and that copy is where the p3-only choices
  land (`--batch-mtp`, `--mmap-experts`, `--conversation-cache-slots 3`, `host`, `port`,
  `api_key: none`, `gpu: [0, 1]` — from the preset, and never in the shared file).
- **Every switch between the two entries runs `setup.py` inside the container**, and that is
  what rewrites the shared `strata-iq3_s.json`. Reusing the installed config needs **both**
  halves of the test: `installed_serves_request` (same `MODEL_PATH`, same pack folder — that
  part does hold, thanks to the file bind mounts) **and** `desc_matches` (runner.py:217,
  reached from `ensure_model`, runner.py:913-920) finding the installed
  `context`/`kv`/`images` equal to this launch's. Those come from the preset plus
  `-e CONTEXT=128k` (entrypoint.sh:180), and the two presets deliberately disagree: 262144
  against 131072, int8 against q4_0. So p3's start sees 256k/int8 and p1's sees 128k/q4_0 —
  the answer is always "no", and setup runs. Restarting the **same** entry is harmless: by
  then the shared file already holds that entry's own numbers, the test passes, and nothing
  is rewritten.
- **What that setup run costs: `args`, the profile and `user_args`.** It rewrites `args` to
  its own choices (`--max-context 131072 --kv q4_0` on p3, and p1's next start flips them
  back), puts `--expert-profile` back on the shipped `expert-profile.bin`, and empties
  `user_args` outright (2026-10-25 13:11) — which would have silently stripped p1's hand
  tuning on its next start. With `MODEL=IQ3_S` shared by both entries, neither entry's
  `user_args` is safe from the other, so **every hand setting lives in the preset's `extra`
  instead** (it is per-preset and beats what the launch builds, the same way
  `--vram-reserve-mib` does); `user_args` is now empty on purpose. The expert profile is
  wired there for both entries: `"--expert-profile": "/data/state/strata/profile-learned.bin"`
  — without it a preset gets the shipped profile, which is why p3 ran the unlearned ranking
  until 2026-10-25.
- **And it takes the `"vision"` section with it, which has no preset home.** `SETUP_KEYS`
  (setup.py:6005) counts `vision` among the keys setup writes itself, and a setup that cannot
  see the cards (no runnable `nvidia-smi` in the image) resolves pictures off; with no vision
  dict in the new config, `carry_over` (setup.py:6016) has nothing to merge the old keys into,
  so the section is gone — `"cuda_device"`/`"max_tokens"` sit outside `SETUP_VISION` and
  survive only when setup writes a vision dict of its own. Setup is the only writer at all
  (`vision_reader.vision_section` is called from setup.py:7533/7803/9085), and a preset's
  `"vision": "on"` merely feeds setup's command line, so **the reader has to be pasted back
  into `strata-iq3_s.json` after any p1↔p3 switch**: `exe: /data/install/strata-vision` (the
  shim, never the version-pinned path), the BF16 mmproj, `gpu: true`, `cuda_device: 1`,
  `max_tokens: 512`. `serve/server.py:2974` derives the bare `--vision` from the section, so
  nothing else is needed. Until it is back, both entries still advertise
  `"in": ["text", "image"]` from the static llama-swap `capabilities` while the engine has no
  reader; the engine's `strata-vision: warmed up at N image tokens` line is the proof it is
  on. Making both presets agree on context and KV would stop the setup runs — at the price of
  p1's 256k.
- **The reported `model` field stays `qwen3.8-flash-next-iq3_s` for both**: llama-swap
  passes the upstream body through (verified) and the name comes from the shared run
  config's `model_name`, which no env overrides. Only the *request* name and
  `/v1/models` distinguish them.
- What batch costs here (Strata `docs/BATCHING.md`): one request alone keeps the solo MTP
  path (unchanged speed); overlapping requests share verify windows. Each slot takes VRAM
  out of the expert cache (0.56 GiB at 32K with int8 KV, more at 256K), and this 83 GB MoE
  on 40 GB of VRAM is exactly the "experts do not all fit" case where a shared window can
  cost 10–25 % per request. `fit_parallel(24 GB) = 3`, so 3 is the top that launch would
  recommend for the 3090 Ti and it is honoured as asked; the engine may still run fewer —
  it logs `INFO batch_slots=N` and `/v1/status` → `concurrency.serving` says the truth.
- **Measured 2026-10-25 (batch 3, `--kv q4_0`, `--mmap-experts`) against the p1 entry the
  same day** — `serving-smoke --repeat 5`, `/data/bench/p3-smoke-a` vs `smoke-pg512-e/f`:
  serial **123 tok/s (101.6–133.7) against p1's 171**, i.e. −28 %, so "a solo request keeps
  the solo MTP path, unchanged speed" does not hold here; mixed (4 clients) ~101 against
  ~135, but *better* tail latency: p95 TTFT 1.16–1.22 s against 1.41–1.69. Hit rate 81.3 %
  (4626 CUDA0 slots) against 84.6 % (4841). A direct probe (250-token completions, p3 solo
  vs N concurrent): **solo 67 tok/s aggregate → 3 concurrent 104 → 5 concurrent 102** —
  ~1.55× and flat, per-request decode 105 → 36–51 tok/s. One decode stream already
  saturates the CPU expert pool, so **slots buy concurrent long contexts, not throughput**;
  a second slot is nearly free after the first, a third is not the win it looks like.
- **`--pipeline-windows 2` is silently off in batch mode** — the log prints
  `--pipeline-windows 2 is off: not with --batch slots` — so p3 does not get the 0.1.48
  CUDA1 interleaving that p1 has. Count it as part of the batch cost, not as a bad config.
- **`--mmap-experts` is what makes 3 × 128k fit in RAM.** No pinned arena: the engine's own
  guard reads `current 5.3 GiB … available 56.9 GiB` where the arena mode reads
  `current 51.6 GiB, available 5.4 GiB` (host: 11 GiB used, 50 GiB available). The experts
  live in the page cache instead — `experts via mmap (--mmap-experts; the GGUF shards in
  place, no experts.bin)` — and once warm the I/O line reports `page cache held 234783.3 MB
  at the read, not 0.0 MB` with ~0 major faults. Parking then works, which p1 cannot do at
  all: `parked 462 tokens … parked=3 bytes=1577661064 evictions=0`,
  `restored 42529 tokens (live) in 55.8 ms`. The catch is the engine's own A/B warning for
  this mode, `71.97 vs 34.78 ms/token cold vs warm`: keep host RAM (page cache) free, and
  do not let anything else on this machine eat 46 GiB.
- **KV sizing for the cache numbers** (`vram_fit.KV_BYTES`, 13 layers): q4_0 576 B/token =
  0.80 GiB per 131072 slot — matches `--batch: 3 slot sessions on CUDA0 (0.80 GiB each)`
  and `the slot sessions take 2.41 GiB of VRAM on CUDA0 that the expert cache would
  otherwise hold`; CUDA1 keeps `8192 slots, 8192 of its 8192 profiled pairs`. At int8 those
  three slots would take ~3.9 GiB (projected) and CUDA1's full coverage would not survive.
  Hence `"kv": "q4_0"` on this entry only. `--conversation-cache-mib 7168` with
  `--conversation-cache-slots 3` covers three parked 128k conversations (~1.27 GiB each at
  q4_0) with ~1.9× headroom. Bench p3 without owning its lifecycle: `strata bench run
  --suite serving-smoke --url http://127.0.0.1:5802 --repeat 5 --condition X
  --out /data/bench/X` (`--out` is required for the serving suites; `compare` refuses runs
  whose source config digests differ, so diff `results.json` `phases[].summary` by hand).
- **Untuned on purpose**: the 0.1.4x default `--batch-groups` is `auto`, i.e. one
  pipelined group per stage, and the pipelined path turns off `--batch-mtp` *and* the
  adaptive expert tier between windows (`--adapt-*`, `STRATA_ADAPT_LAG=2` are live here).
  The measured better arm at 2–4 streams on a two-stage split was `--batch-groups 1` (+
  optionally `STRATA_BATCH_MTP=1`); try it in `docker-p3.json`'s `extra`, one change per
  restart. Check `/metrics` → `live.slots` and `/v1/status` while measuring.
- Not in `hooks.on_startup.preload`: the boot backend stays the single-stream one, and
  this entry swaps in on first request like Maya.

### llama-swap/swift — `swift-1.5-iq3_s` (DROPPED 2026-10-25)

Wired the day it was fetched, **never started once**. `qwen3.8-flash-next-iq3_s-parallel` took
its seat in the `gpu` group (§ llama-swap/strata-parallel). The weights are still in the HF
cache: `ukisai/Swift-1.5-Qwen3.8-Flash-Next-GSQ-RCO-GGUF` IQ3_S — shard 1 `46cb3996cd1a…`
(44.9 GB), shard 2 `70ce6fb48a94…` (38.8 GB), and its own
`mmproj-Swift-Qwen3.8-Flash-Next-BF16.gguf` `cd1140f4abba…` (907,543,520 B — **not** the
original's 907,543,008 B, so the mount lines differ; same 83.6 GB class, `MODELS`: `ram_gb` 62).
Revival: the preset is in git at `42d8314`, the nix entry at `ade7e50`, plus `-e FAMILY=swift`
`-e PRESET=docker-swift` — and after 2026-10-25 its own `/data/install` tree, which is now the
house style rather than a second preset in someone else's.

What that wiring learned, kept because the facts are the engine's, not swift's:

- **Install identity is `<family tag><MODEL>`.** The run config is `strata-<family tag + MODEL>.json`
  (`setup.py:7392` + `:7507`, read back by `catalog.tag_of`/`installed_config`, `catalog.py:355,463`)
  and the `swift` family's tag is `swift-` (`setup.py:571-578`) — so swift owned
  `strata-swift-iq3_s.json`, `packs/swift-iq3_s`, `models/swift-IQ3_S`, and nothing it did could
  touch the IQ3_S file. p1 and p3 collided only because they shared family **and** MODEL; the
  parallel entry keeps that collision and separates the *directory* instead.
- **A fine-tune of the same weights shares the MTP draft and the shipped expert profile**: setup
  builds `mtp/rt` from the original Qwen checkpoint for every family (`setup.py:8737-8745`) and
  only `coder` overrides the profile (`"profile": "expert-profile-coder.bin"`, `setup.py:592` in engine 0.1.52
  — the family entry starts at 586; it was 585 on 0.1.48).
- **`--expert-profile-save` had quietly left `docker.json` and `docker-p3.json`** — it lived in
  `user_args`, which every setup run empties, while the launcher re-saves the preset on each
  start; `profile-learned.bin` stopped changing at 2026-10-24 22:53 while both entries kept
  reading it ("without the key nothing is counted or written", `docs/DETAILS.md:752`). The engine
  writes the learned file only on a clean exit — `cmdStop = podman stop -t 120` gives it the
  chance. `1slot` carries that wiring again; the parallel entry runs the shipped ranking.
- Stale in the volume: `/data/Strata-data/models/IQ3_S/…-00001-of-00002.gguf.part` (4.6 GB,
  2026-10-21) is a half-download nothing reads — the model files are bind mounts now.

### llama-swap/strata-parallel — `qwen3.8-flash-next-iq3_s-parallel` (wired 2026-10-25, **REMOVED 2026-10-26**)

**Dropped 2026-10-26** once the pi-subagents budget moved to 4 concurrent children. It was replaced by
`qwen3.8-flash-next-iq3_s-parallel` — batch slots (5 when it was written, 4 since 2026-10-27; the key was
`…-parallel5` and the tree `5slot/` until that rename), port `5802` (the port this entry had; 5801 is the
single-stream 1slot tree), booting off `~/.config/strata/parallel` — which is
the preloaded batch engine now. What went with it: this nix entry, its `gpu` group member, the
`~/.config/strata/3slots` tree, the Pi `modelOverrides`/`modelThinkingLevels` entries for the name, and the exited
container. The 5-slot preset ties this one's best aggregate (166.7 vs 167.1 tok/s measured on the same box);
`~/.config/strata/parallel/TUNING_NOTES.md` § Removed: 3slots holds the restore recipe, and the old 3-slot preset still
survives verbatim there as `strata/launch-presets/docker.json.bak-pre-batch5`. Everything below stays as history —
its paths and port `5802` describe the removed layout, not what is on disk.

Batch 3 is back — the p3 numbers, in a different shape. Instead of a second preset inside the p1
install tree (§ llama-swap/strata-p3, parked), this entry boots on `~/.config/strata/3slots` as
its own `/data/install`, so its run config `strata-iq3_s.json`, its launch preset
`strata/launch-presets/docker.json`, its `launch-docker` profile and its `strata-vision` shim are
separate files. That is what the split buys: `desc_matches` failing can no longer rewrite the
single-stream entry's file — the setup pass that emptied `user_args` and dropped the `"vision"`
section twice now only ever touches its own tree.

- **Numbers** (`3slots/strata/launch-presets/docker.json`): `parallel: 3`, port `5802`,
  `context 131072`, `kv q4_0`, `--conversation-cache-mib 7168` (three parked 128k conversations
  at q4_0, ~1.27 GiB each) and `--resident-experts on` — **not** p3's `--mmap-experts`, so this
  one wants the pinned 51 GiB arena, which is what `--cgroup-conf memory.swap.max=0` guards. The
  rest of the tuned `extra` is p1's (`--layer-split 32`, `--pipeline-windows 2`, `--spec-min-p
  0.70`, `--pcie-frac 0.00`, `--trim-stage-weights`, `--vram-reserve-* 1024`), minus the
  `--expert-profile*` pair: it runs the shipped ranking.
- **No `-e PRESET` / `-e PARALLEL` / `-e CONTEXT` in nix.** The preset is named `docker` here as
  well, and the batch comes from the preset's own `"parallel": "3"`; the p3-era collision was the
  *shared* preset, and there isn't one any more. Worth checking once: without `-e CONTEXT` the
  entrypoint's default context is what `desc_matches` compares against the preset's 131072, and a
  mismatch means every start runs setup on *this* tree (§ llama-swap/strata-p3 for what that
  costs) — `POST /v1/status` → `context` and the file's mtime say which way it went.
- **Vision is wired from the start**: the run config carries the `"vision"` section
  (`exe`/`cpu_exe: /data/install/strata-vision`, the BF16 mmproj, `gpu: true`, `cuda_device: 1`,
  `max_tokens: 512`) and `args` carry `--vision`, so the paste-it-back-after-every-switch step
  (§ llama-swap/strata-p3) does not apply to this tree.
- **Still shared, so keep the group**: `strata-data:/data` is one volume for both entries, and
  **both profiles' `source_config` is `/data/state/strata/launch/docker.json`** — the launcher's
  derived run-config copy is keyed by *preset name*, not per entry, and both presets are called
  `docker`. That file on disk is the batch entry's today: `--max-context 131072 --kv q4_0
  --resident-experts`, port 5802, written 2026-10-25 18:07. Same for `profile-learned.bin`, the
  API key, the pack and `mtp/rt`. The install split did not separate any of that; the `gpu`
  exclusive group is what keeps the two from meeting, and they still can never run together (two
  expert arenas, ~2 × 51 GiB against 62 GB of RAM).
- **`capabilities.context = 131072`** — the engine's own cap, not p1's 256k. `--max-context
  131072` sits in this tree's run-config `args` and the launcher's derived copy agrees with it.
  It shipped as 262144, inherited from the swift entry this one replaced, and llama-swap publishes
  the *static* `capabilities` — so a wrong number here is what `/v1/models` reports whatever the
  engine actually loaded; p3 set 131072 on its entry for exactly this reason. Cross-check with
  `/v1/status` → `context`.
- Reported `model` stays `qwen3.8-flash-next-iq3_s` for both entries (`model_name` in each tree's
  run config, same string; nothing overrides it) — only the request name separates them.
  `--pipeline-windows 2` is off in batch mode (the engine logs `… is off: not with --batch slots`),
  so this entry loses p1's CUDA1 interleaving; count it as batch cost. The measured better arm at
  2–4 streams was `--batch-groups 1` (+ optionally `STRATA_BATCH_MTP=1`) — try it in **this**
  preset's `extra`, one change per restart. Not in `hooks.on_startup.preload`: the boot backend
  stays the single-stream one. (Superseded: its `-parallel5` successor — today's `-parallel` — **is** preloaded since
  2026-10-26 — see § routing / activity / preload.)

### llama-swap/strata-parallel — where each serving setting lives (2026-10-27)

- **Renamed 2026-10-27** (same day as the queue work): install tree `~/.config/strata/5slot/` →
  `~/.config/strata/parallel/`, llama-swap key / podman name `qwen3.8-flash-next-iq3_s-parallel5` →
  `qwen3.8-flash-next-iq3_s-parallel`, pi keys in `~/.pi/agent/settings.json` + `models.json` likewise. The `5`
  left the name because the slot count is 4 and moves (`-e PARALLEL`), so a name that says 5 lies. Inside the tree
  nothing changed — the preset is still `docker`, the profile still `launch-docker`, the port still `5802`, so the
  tree's whole state moved with `mv`. Two traps the rename springs: **podman `--replace` only matches the same
  name**, so the old container has to go by hand (`podman rm -f qwen3.8-flash-next-iq3_s-parallel5`) or both
  backends load and the second one fails on VRAM; and `strata` running **on the host** (not in the container)
  resolves its config dir from `XDG_CONFIG_HOME`, so a host-side `strata` invocation has to be pointed at the new
  path. Worse than the VRAM race: the old container records `Source = /home/javi/.config/strata/5slot`, which is
  gone, so `podman restart` on it recreates the bind as an **empty** directory — no preset, no profile, no run
  config — and the start goes through setup's adopt fallback, which rewrites `strata-iq3_s.json` from defaults
  (§ llama-swap/strata). Drop the old container; never revive it.
  **Done and verified 2026-10-27:** old container removed before the switch, new one created 12:09 with
  `-v /home/javi/.config/strata/parallel:/data/install`, `-e PARALLEL=4`; llama-swap `/v1/models` lists
  `qwen3.8-flash-next-iq3_s-parallel`; boot checklist unchanged (`4 slot sessions`, expert cache 5270, CUDA1 8192
  of 8192 profiled pairs, lend sizing 3657, 667/998 MiB free); queue bound live (`max_queue 3` in the derived
  config, telemetry `admission_limit 7`, `parallel-overload-v1` at c=8 → `peak_active 7`, `occupied 4`, one 429,
  `queue_timeouts 0` — `/data/bench/2026-10-27-rename-check`). The running engine follows the *inode*, so the `mv`
  itself never disturbed a live session.

Three knobs, three different layers, and only one of them is a launch flag. Read off the image's
`strata_cli/launch/runner.py` and confirmed by watching container restarts do it to my edits.

- **Slots → `-e PARALLEL=4` in the nix cmd** (`configuration.nix`, batch entry). The entrypoint passes
  `--parallel 4`, which overrides the preset at start *and* writes it back (`--save-preset`) — the same
  mechanism that made § llama-swap/strata-p3 conclude "editing that field is futile". The parallel preset's
  `"parallel"` is kept at `"4"` anyway so `strata launch --list-presets` reads honestly (`4 requests`), but
  the env line is the one that cannot drift. Changing it needs a system switch (llama-swap regenerates its
  config and the container is recreated with a new cmd); the queue bound below does not.
- **Queue bound → top-level keys in `~/.config/strata/parallel/strata-iq3_s.json`**: `"max_queue": 3`,
  `"queue_timeout": 90`. There is **no launch flag and no env** for these — the entrypoint's settings list is
  fixed (`MODEL FAMILY MODEL_PATH CONTEXT PARALLEL VISION KV GPU(S) GPU_ROLES TUNE PORT API_KEY PRESET
  STRATA_SET`), and `STRATA_SET`/preset `extra` reach **engine** argv only (`as_argv_changes` →
  `tune_knobs.apply_to_argv`; an unknown `--max-queue` would be handed to the engine). But they *are* run-config
  keys: `serve/server.py` takes `max_queue = a.max_queue if a.max_queue is not None else cfg.get("max_queue")`,
  same for `queue_timeout` (and errors if `queue_timeout` is set without `max_queue`), and
  `derive_config` opens with `cfg = json.loads(json.dumps(base))` — a deep copy of the **installed** run config —
  replacing only `host port api_key drafting exe open_browser log cards mtp args env`. So extra top-level keys
  survive every start. Check without restarting:
  `podman exec -e PYTHONPATH=/opt/strata/terminal <ctr> /opt/strata/terminal/python/bin/python3 -c "…derive_config…"`
  printed `max_queue 3 / queue_timeout 90 / 29 tuned args intact`.
  Effect: `admission_limit = slots + max_queue = 7` — 4 decoding, 3 waiting, 429 past that.
- **Context cap → four places have to agree, plus one redundant pi pin** (lowered 131072 → **98304** on 2026-10-27 ~15:10 because 4 × 100k
  conversations hit the RAM wall; rationale and measurements in `~/.config/strata/parallel/TUNING_NOTES.md`
  § the RAM wall). The engine arg is the only one the server *obeys*; the rest are either agreements or
  advertisements, and getting them wrong fails in different ways:
  1. `~/.config/strata/parallel/strata-iq3_s.json` args `--max-context 98304` — what `serve/server.py` reads.
  2. preset `extra` `"--max-context": "98304"` — the layer that wins, and `tune_knobs.apply_to_argv` deletes the
     base config's flag before appending it, so there is exactly one in the derived argv (verified: x1, 30 flags).
  3. preset `"context": 98304` — **never reaches argv** (`derive_config` puts only `extra` there, §
     llama-swap/strata-p3); it exists for the *reuse test* against the installed file, and a mismatch there sends
     the start through setup, which rewrites the run config from defaults.
  4. nix `capabilities.context = 98304` on this entry — llama-swap advertises it as `context_window` / `n_ctx` in
     `/v1/models`; leaving it at 131072 makes the router promise a context the engine refuses. Needs a switch to
     regenerate the llama-swap config; check `curl -s localhost:8080/v1/models` → `context_window: 98304`.
  5. `~/.pi/agent/models.json` → `modelOverrides["qwen3.8-flash-next-iq3_s-parallel"].contextWindow = 98304` is
     **insurance, not the mechanism — pi does discover the advertised number.** `curl -s localhost:8080/v1/models`
     carries `context_window` / `context_length` / `meta.n_ctx` for **every** model, loaded or not, straight from
     nix `capabilities.context`, and pi uses it: the solo `qwen3.8-flash-next-iq3_s` entry has **no pi override at
     all** and pi still runs the full 262144 (checked 2026-10-29). The old "101k prompts accepted happily" was
     101k < the then-advertised 131072, not a 128000 fallback — the **128000 default in
     `docs/models-configuration.md` belongs to declared `models` entries**, not to models discovered over
     `/v1/models`. `modelOverrides` *replaces* the discovered field ("other fields replace it"), so a stale pin
     now actively hides the real cap: it is worth keeping only where pi must use **less** than the router
     advertises, and worth deleting rather than letting drift. With 98304 and pi's default `reserveTokens 16384`,
     auto-compaction starts above 81,920 tokens (245,760 on the solo tree). Read at pi start, so a running
     session keeps the old number.
  Checking the derived argv without touching the live engine:
  `podman exec -i -e PYTHONPATH=/opt/strata/terminal <ctr> /opt/strata/terminal/python/bin/python3 -c "…derive_config…"`
  → `--max-context x1 = 98304`, `--conversation-cache-min-free-mib 1536`, `max_queue 3/90`. Do this after every
  edit to the args array: mine once wrote the value **over** the flag name (`args.index(flag)` is the flag index,
  the value is `+1`) and left `131072` orphaned, which would have broken the next start.
- **The saved profile is not a config place.** `launch/runner.py:ensure_profile` replaces its whole override
  set with exactly `host port parallel`, taken from the preset — "the overrides are replaced as a set". Two
  `strata profile set launch-docker max_queue=…` edits were silently undone by the following container starts.
  `strata profile set` + `strata runtime restart --profile launch-docker` (take the `--if-*` ids from `--plan
  --output json`) *does* make them live inside a running container — measured once: `admission_limit 7`, one
  429 at c=8, `queue_timeouts 0` — but that is a hotfix for a live box, not a setting; leave the profile at
  whatever the launch writes (`47e97cdb5e924d68` = `host port parallel:4`) so there is one source of truth.
- **`--pull newer` in the cmd means a switch can swap the engine under you.** The 2026-10-27 ~21:57 switch (the one
  that made `capabilities.context = 98304` live) pulled `strata:latest-cuda13` and the container came up on engine
  **0.1.52** instead of 0.1.48 — the version every number in `~/.config/strata/parallel/TUNING_NOTES.md` was measured
  on. It accepted all 30 tuned flags with no unknown/deprecated warnings, and actually fit **more** CUDA0 experts
  (5226 slots / 9.64 GiB vs 5134 / 9.47 at the same 1280 MiB reserve), so nothing broke. But the margins in that file
  are 0.1.48 numbers, and the same surprise will happen on any future switch. If that bothers you more than free
  upgrades, pin the image by digest instead of `latest-cuda13`.
- **Verify after any restart.** `--parallel 4` shows on the serve cmdline, but values that came from the run
  config do **not** — read telemetry instead: bench report `environment` → `slots_effective 4`, `max_queue 3`,
  `queue_timeout_s 90`, and `before/after` → `admission_limit 7`. A `parallel-mixed-v1`/`parallel-overload-v1`
  run at c=8 must show exactly one 429. **If a setup pass ever rewrites `strata-iq3_s.json`** (§ llama-swap/strata:
  `installed_serves_request` failing → setup's adopt fallback) the two keys vanish with it — `grep -n max_queue
  ~/.config/strata/parallel/strata-iq3_s.json` is the one-line check.
- Why 4 + 3: `~/.config/strata/parallel/TUNING_NOTES.md` § batch 4 + queue back-pressure — 179.3 agg / 45.0 per
  stream at 4 streams (best measured point on this box), 150 at 5, and the bound keeps TTFT ≈0.01 s out to 7
  concurrent instead of the unbounded p95 2.88 s at c=8.

### llama-swap/maya — `glm-5.3-flash-maya-s24`

Project Maya: GLM-5.3-Flash (321 B MoE; the hottest experts in VRAM, the rest read
through the page cache — RAM where they fit, NVMe otherwise). Image from
`~/dev/personal/project-maya` (`podman build -t maya .`).

- `maya-data:/data` holds the pack and the **links** to the model files, not their
  bytes; `/data/config` is the host's `~/.config/maya`. Unlike Strata, Maya keeps its
  state **next to its code** (`ROOT.glob("maya-*.json")` in `maya.py`'s `configs()`, and
  `write_config()` writes `ROOT/maya-<quant>.json`), and `/opt/maya` is the image's own
  throwaway layer — so `docker-entrypoint.sh` keeps the config, its `.log` and its
  `.shared-settings.json` on the host bind and symlinks them into `/opt/maya`. Every
  write to those paths is a plain `write_text` (no tmp + `os.replace`), so it follows
  the link and lands in `~/.config/maya`, where you can edit it.
- The model bytes live in the **HF hub cache**, not in the volume (unlike Strata's
  bind-mounted blobs): `docker-seed-hf.py` links
  `peasantsmith/GLM-5.3-Flash-Maya-GGUF`'s files from `/hf-cache` into maya-data's
  models folder, where `maya.py`'s step 5 sees them as a finished download; the cache
  is mounted `:ro` and never written to, and the pack plus the `.maya-verified.json`
  record go beside the links. **Keep mounting it after setup** — the links in the
  volume only resolve while `/hf-cache` is mounted. Prime the cache once with your
  usual HF downloader (`hf`'s `--include` takes one pattern per flag; verified 5 files,
  95.8 GB, sha256s matching maya.py's pins):
  `hf download peasantsmith/GLM-5.3-Flash-Maya-GGUF --include "Maya-S24/*" --include "vision/*"`
- The model is **not** downloaded by llama-swap: if the cache has nothing usable and no
  config exists, the entry point prints how to prime the volume and exits 1 rather than
  pulling 95 GB inside a backend llama-swap is already timing out on.
- `RAM_GB=44`: Maya would otherwise size the tier from `MemAvailable` (~15 GiB here,
  because the 47 GiB pool is already charged against it) and stream the rest of the
  model on every token. *(The hugepages block that used to be referenced here is not
  in the current `kernelParams`.)*
- No API key and `HOST=0.0.0.0`: `:8080` is llama-swap, the backend port stays closed,
  and `--network host` only works if the server binds outside loopback. Maya prints its
  own "WARNING: no API key" line at start for the same reason; it is about direct
  access on the backend port, which the firewall keeps closed anyway.
- `cmdStop = podman stop -t 35` — 35 s, inside `unloadTimeout` above: podman's SIGTERM
  reaches `maya.py` (PID 1), which stops `serve/server.py` the way Ctrl+C does
  (`stop_signals`), and Maya's own stop waits up to 150 s for the request in flight
  plus the engine's QUIT (`STOP_WAIT_S`). A stop that outlives llama-swap's wait is
  untidy but survivable: the next `cmd` uses `--replace`, which removes whatever
  container is left.
- `capabilities.context = 131072` vs Maya's own defaults (`maya.py`'s `DEFAULT_CONTEXT`
  65536 and the `CONTEXT` env) — keep the two in step; the pack and the config are
  written at setup time with it. The vision tower runs on GPU 0 beside the model
  (`in: [text, image]`); tools = OpenAI + Anthropic tool calls.

### llama-swap/strata-coder — `qwen3.8-flash-next-coder-iq1_m-parallel` (wired 2026-10-28)

Third Strata backend: `ISTA-DASLab/Qwen3.8-Flash-Next-GSQ-RCO-Coder-GGUF`, the expert-**pruned** coding
build of the same family (256 of 512 routed experts per layer survive). Install tree
`~/.config/strata/coder/`, forked from `parallel/` (§ llama-swap/strata-parallel — where each serving setting
lives); **port 5801**, which only overlaps the retired 1slot engine, so it never coexists with anything
holding GPU memory. It shares the exclusive GPU group, so llama-swap will not run it alongside iq3_s or Maya.

> **Tuning numbers live in the tree, not here:** `~/.config/strata/coder/TUNING_NOTES.md` carries the model shape,
> the layer-split and kv-resident arithmetic with the measured ladder, the conversation-cache sizing, the
> boot checklist and the failure-mode table. This section covers the **entry** — env, mounts, advertised
> capabilities, and the store mount that makes the model installable at all.

- **`-e FAMILY=coder -e MODEL=IQ1_M` — `MODEL` is a SIZE, not a name or path.** A repo's short name is not
  a valid `MODEL`: family+size resolve against `setup.py:570`'s `FAMILIES` table (the coder entry sits at
  `setup.py:586`), and `IQ1_M` is the only size coder offers — `setup.py:420` spells it out:
  `"IQ1_M": {"about": "the Coder's only size: half the experts, stored like IQ3_S (3.5 bits)", "download_gb": 58.4}`,
  with the two shard names and hashes pinned just above it (`setup.py:398-402`). `tag_of()` = `fam["tag"] + model`, which names the run config
  (`strata-coder-iq1_m.json`), the pack (**`packs/coder-iq1_m`**, so coder cannot reuse or clobber the base
  model's `packs/iq3_s` — 1.5 GB per pack, one per quant), and the model folder. A family the table does not
  know dies before setup starts: `strata-setup failed (rc=1)` with nothing in the log.
- **`MODEL_PATH=/data/gguf/coder-IQ1_M` and the three blob mounts use `fam["file"]` verbatim** —
  `Qwen3.8-Flash-Next-GSQ-RCO-IQ1_M-00001-of-00002.gguf`, `…-00002-of-00002.gguf`,
  `mmproj-Qwen3.8-Flash-Next-BF16.gguf`. **There is no "Coder" in those names.** Rename the files and setup
  reports "the model folder you pointed at is empty" and re-downloads the 58.4 GB pair. Shard 1 is **29.6 GB** (the pruned
  expert mass, vs IQ3_S's 54.8 GB: IQ4_NL 9.2 vs 18.4, IQ3_XXS 5.5 vs 10.9) — that ~25 GB is what lets 4 × 128k
  conversations fit in RAM (§ parallel/TUNING_NOTES.md § the RAM wall: ~3.5 GiB per 128k slot, engine HWM
  55.9 of 62.3 GiB). Shard 2 (**28.8 GB**, the n-gram PLE table) and the mmproj are the base model's own files,
  mounted from the same blob hashes as the `-parallel` entry.
- **`--max-context 131072` here, unlike the parallel tree's 98304.** Four places have to agree — preset
  `extra` (the layer that reaches argv), preset `"context"` (the reuse check only), `capabilities.context`
  below (llama-swap advertises `context_window` / `n_ctx`), and Pi's `modelOverrides[…].contextWindow` in
  `~/.pi/agent/models.json` — that last one is **optional**: pi discovers what llama-swap advertises, and a stale
  pin replaces the discovered value and hides the real cap (§ llama-swap/strata-parallel item 5). The engine arg
  is the only one the server obeys; the rest are agreements or advertisements. § TUNING_NOTES.md § kv-resident
  has the budget arithmetic for why 131072 of *context* is fine while 131072 of *kv-residency* is not.
- **`--pcie-frac 0.20`** instead of that tree's `0.00` — the streaming-headroom default, which is right for
  coder. The 1slot engine measured `pcie_share ~0.000-0.011` at expert hit rates in the high 90s, and
  **PCIe is not the limiter here at any frac** (measured: 12.44 ms streamed of a 4500 ms request, hit rate 91%,
  share 0.0027 at frac 0.05). CUDA1's card is `00:06.1` behind an **x4** bridge (`max_link_width = 4`, 6.6 GB/s
  usable of the slot's 19.7) and cannot be raised without changing upstreams. What `frac` decides is *where*
  experts land; the miss cost is asymmetric (26.7 vs 6.6 GB/s, ×4.07), which is the reason the layer split is
  biased toward CUDA0 (§ TUNING_NOTES.md § Layer split).
- **The run config's `--expert-profile` is `expert-profile-coder.bin`** (`fam["profile"]`), not the shipped
  base profile: the base profile mispredicts coder's routing, and the whole residency picture (12288 pairs,
  6912/5376 per card) is read off that file.
- **`-v /nix/store:/nix/store:ro` — without it the model is not installable at all.** The image ships
  `nvidia-smi` copied off a NixOS host, so its `PT_INTERP` is
  `/nix/store/pqyiidz5mi73wv5f91d48s9plcqyj5bz-glibc-2.44-57/lib/ld-linux-x86-64.so.2`; that path is absent
  inside the container, `execve` fails with **ENOENT**, and `setup.py:9099` concludes "no NVIDIA GPU found
  (nvidia-smi did not answer)". The launcher then takes the adopt path — `launch/runner.py:1233`
  `adopt_prepared_files` — which raises "the files Strata would need to write the settings itself are not all
  there" at `runner.py:1256` with exit 5. Packs are **downloaded** by setup, never built by the Terminal: the
  manifest entries in `setup.py` (279-292) name `pack/dense.bin`, `pack/index.txt` and
  `pack/native_experts.txt` with byte sizes and sha256. Mounting
  the store read-only gives the loader back: `nvidia-smi` answers both cards (5070 Ti 16303 MiB / 3090 Ti
  24564 MiB, driver 615.78.08), setup runs its GPU fit, and `packs/coder-iq1_m` is prepared on first start.
  Verify once with `podman run --rm --entrypoint '' /bin/sh -c 'readelf -lW /usr/bin/nvidia-smi | grep INTERP'`.
  - **Deliberately NOT added to the two iq3_s entries**: their starts never reach the GPU fit (they short-circuit
    on an existing pack + run config, "qwen IQ3_S is already installed with these choices"), and letting setup
    size cards it has never sized before could walk the tuned `layer-split` / `kv-resident` / conversation-cache
    choices those trees have accumulated. Add it there only on purpose.
- **`user_args` shadowing is a hazard for the *entry* too**, because the entry's env is the only layer that
  cannot drift: `--parallel` comes from `-e PARALLEL=4`, which overrides the preset at start *and* writes it back
  (`--save-preset`). The conversation-cache flags live in both the preset and the run config's persisted
  `user_args`, and the latter is appended last (§ TUNING_NOTES.md § Where each setting lives) — editing only the
  preset is silently ignored for those flags. Observed live 2026-10-28: preset said 8192 / 10 / 4096, start logged
  6144 / 6 / 256; the same preset edit *did* move `--kv-resident` and `--layer-split` (absent from `user_args`).
- **Verified live 2026-10-28** (preset at `layer-split 21`, `kv-resident 86016`, conv-cache 8192 / 10 / 4096): argv
  `--kv-resident 86016 --layer-split 21 --max-context 131072 --pcie-frac 0.20 --batch 4 --parallel 4 --port 5801
  --conversation-cache-mib 8192 --conversation-cache-slots 10 --conversation-cache-min-tokens 4096`;
  `layer split: 100% of the experts resident`, `expert_slots 12288` / `expert_slots_primary 5376`, free
  **675 / 1343 MiB** (`nvidia-smi` 626 / 1258 after window capture), no `- LOW`, RAM 31.1 of 62.3 GiB,
  `KV streaming: 86016 of 131072`. Config hash for the whole system was unchanged by these edits (`agf6264v…`):
  tuning lives in the bind-mounted preset, so a `podman restart` is enough — a `capabilities.*`, env or mount
  change is not.

### llama-swap/llamacpp — PARKED 2026-10-20

`bartowski/Qwen3.8-27B-GGUF:Q8_0` is commented out (kept in the file, not deleted):
its weights are gone from the HF cache (bartowski Qwen3.8-27B Q8_0, the HermiHg
DFlash2 draft, the ggml-org MTP draft), and the matching `[sections]` were dropped from
`~/.config/llamacpp/llama-preset.ini`. Strata is the only live backend. The SC117
abliterated entry was deleted outright (same engine as the live Strata entry, only its
weights were gone).

To bring it back: re-download the weights, restore the preset sections (from
`~/.config/llamacpp/llama-preset.ini.bak-20261020-mtp-and-27b-removal`), uncomment the
entry **and** its group member below. Note the ISTA names in its `aliases` collide with
the Strata entry's name space — keep at most one of them claiming
`ISTA-DASLab/…Flash-Next…IQ3_S`. Every name (the key included) must match a `[section]`
in `~/.config/llamacpp/llama-preset.ini` and stay unique across llama-swap.

### routing / activity / preload

- `routing.router.use = "group"`, one `gpu` group: `swap = true` (one at a time),
  `exclusive = true` (it evicts every other group), members = Strata + Strata-parallel + Maya
  (+ the parked llama.cpp entry) — the batch `…-parallel` member and its entry left the group
  2026-10-26. Strata wants both cards: `gpus [0,1]` with
  `layer_split 32` — which is why the two Strata entries (the single-stream `iq3_s` and the
  batch `…-parallel`) live in this group and can never run together: two expert arenas
  (~2 × 51 GiB) against 62 GB of RAM.
- `store.path = /var/lib/llama-swap/activity.sqlite` — the Activity page and
  `/api/metrics/activity` record to sqlite instead of the in-memory ring
  (`metricsMaxInMemory` then has no effect); text logs (`/logs`, `/logs/stream/*`) stay
  in-memory ring buffers either way. The directory comes from `StateDirectory` in the
  unit override below: `ProtectSystem=strict` leaves `/var` read-only apart from what
  systemd opens.
- `hooks.on_startup.preload = [ "qwen3.8-flash-next-iq3_s" ]` — changed 2026-10-29 from
  `qwen3.8-flash-next-coder-iq1_m-parallel` (which was renamed 2026-10-27 from `…-parallel5`, and
  before that 2026-10-26 from `qwen3.8-flash-next-iq3_s`): llama-swap v262 has no `default_model`
  key — the preload list *is* the boot default — and the model actually being served was the
  single-stream one, so a parallel preload meant paying an exclusive-group swap (full reload + cold
  re-prefill) on the first request after every boot. Flip back to the batch entry when concurrency
  is the real workload (parallel/TUNING_NOTES.md: 4 streams = 179.3 agg / 45.0 per stream). Either
  way only one entry: the exclusive gpu group evicts whatever else is preloaded. Strata
  is still loaded at boot, not on first request. **Maya is deliberately not
  preloaded**: its cold load is minutes and it pins 44 GiB, so it swaps in on request
  (its first request pays for that, and `sendLoadingState` says so).

## strata-logs

Post-incident forensics: what survives an engine restart, a model swap, or a hard reset.

- **Why this exists (2026-10-29 09:36 incident).** The engine logs live in the *shared*
  `strata-data` volume under a **preset**-keyed name — `state/strata/launch/docker.engine.log`
  and `state/strata/runtime/launch-docker.server.log` — not a per-model name. All three strata
  entries boot on the `docker` preset, so the next launch truncates the run that just died. The
  coder session that slowed to 18 tok/s and ended in the wedge was overwritten at the 09:38
  relaunch: its per-request file-tier/KV-streaming counters were gone. journald carried the boot
  (`Storage=persistent`; the hard reset only rotated `system.journal`, logged as
  "corrupted or uncleanly shut down, renaming and replacing"), the engine's own log did not.
- **`strata-log-archive`** (`let` binding) copies the live logs + `docker.choices.json` + the
  `~/.config/strata/*/strata-*.log` install logs + a `context.txt` (strata containers, per-GPU
  memory/free/clock/watt/temp, load, `free -m`, **PSI cpu/mem/io**, this boot's kernel warn+,
  and `/sys/class/drm/card*/error` — that last one only exists *before* the reboot, which is why
  it is captured here) into `~/.local/state/strata-logs/<UTC>-<tag>/`. Two triggers:
  `llama-swap`'s first `ExecStartPre` (`tag=boot` — covers boot after a hard reset, running
  before `hooks.on_startup.preload` truncates the log) and every strata model's `cmdStop`, which
  runs `${strataLogStop}/bin/strata-log-stop` → **archive first, then `podman stop -t 120`**.
  Archive-first is not cosmetic: `unloadTimeout = 40` cuts the `cmdStop` client off long before
  a slow stop finishes, so a post-stop archive is the one that gets skipped. v262 has no
  per-model shell hooks (`hooks.on_startup` is the preload list only), which is why this rides on
  `cmdStop` at all. Skips when nothing was written since the last run (`.fingerprint` =
  `size:mtime` of the two live logs), keeps the newest 25 dirs, appends `index.txt`. Hand-run it
  any time: `strata-log-archive manual`.
- **`strata-toksample.service`** (system unit, `User=javi`, `Restart=always`) appends one line
  every 10 s to `~/.local/state/strata-logs/samples.csv`: host (`load1`, MemAvailable, swap used,
  **PSI** cpu/mem/io avg10) + both GPUs (`used,free,util,clk,w`) + the **iGPU idle state**
  (`igpu_card`, `igpu_rc6_ms`, per-GT `gt0_rc6_ms` / `gt0_cur_mhz` / `gt0_act_mhz` / `gt0_thr` and the
  `gt1_` twins, read from `/sys/class/drm/<card>/gt/gt*/…` and resolved by the presence of `gt/` so a
  card rename can't break it) + llama-swap's newest request
  (`tok/s`, `prompt/s`, cached KV, **draft / accepted draft tokens**, duration, status). Those
  three groups are what separate the failure modes the engine log cannot: VRAM/KV wall
  (`g*_free_mib` ~0 with high `req_cached`), GPU starved on tier paging (low util + low watts at
  low tok/s), clocks throttled (`g*_clk_mhz` down, and `journalctl -k | grep throttled`), host
  reclaim/IO stall (`psi_mem`/`psi_io`). Rotates at 20 MB, keeps 20 files. stdout is `null` on
  purpose: the loop is the point and it must not land in journald (see the conmon flood below).
- **Why the iGPU idle columns exist.** The wedge signature here is GuC dying on the wake out of RC6
  (Render Standby) — upstream [i915 kernel#14469](https://gitlab.freedesktop.org/drm/i915/kernel/-/issues/14469),
  blamed by the i915 team in [Dasharo#1786](https://github.com/Dasharo/dasharo-issues/issues/1786) — and
  boot `-1` had 15 min of complete i915 silence before the first `TLB invalidation response timed out`,
  so nothing pinned the idle→wake sequence. Exposure here is extreme because all graphics load is on
  NVIDIA: GT1 sat in RC6 ~96% of uptime, GT0 ~75%. These columns are measurement only — `rc6_enable`
  is read-only in 6.18 (`power/rc6_enable` and `gt/gt*/rc6_enable`) and `i915.enable_rc6` was removed
  in 2018; see NOTES § lact for what can actually be changed.
- **Gotcha editing these scripts.** A `writeShellScriptBin` service gets a PATH of only coreutils,
  findutils, gnugrep, gnused, systemd — so `gawk`/`jq`/`curl`/`nvidia-smi` need absolute store paths,
  while plain `ls`/`head`/`tr`/`cut` are already there (they are **coreutils**: `${pkgs.findutils}/bin/head`
  does not exist, and the failure is silent — the iGPU columns came out `na`, one field short of the
  header). Inspect the unit's real env with `systemctl show <unit> -p Environment`; and note that a
  header change rotates the current CSV into `samples-<date>.csv` by itself.
- **Triage after the fact, in order.**
  1. `~/.local/state/strata-logs/index.txt` → the last archived run; read its `context.txt`.
  2. `/var/lib/llama-swap/activity.sqlite` **already survives reboots** (`StateDirectory`) and
     holds every request: `tok/s`, `prompt/s`, cached/input/draft tokens, duration, status.
     `sqlite3 /var/lib/llama-swap/activity.sqlite` (copy it plus the `-wal` first; the CLI is in
     `environment.systemPackages`). Group by `draft_tokens > 0`: across the whole history that
     split is ~118–131 tok/s vs ~32–49 tok/s per stream — the 2026-10-29 window was 52 rows
     without drafts (26.5 avg) against 4 with (98.2), i.e. MTP/spec drafting falling out is the
     single biggest tok/s lever on this box, not VRAM size or clocks.
  3. `journalctl -b <n>` (find the boot with `journalctl --list-boots`) for the machine side: the
     wedge read as 16× `i915 *ERROR* GT0: GUC: TLB invalidation response timed out` inside 29
     `*ERROR*` lines (the other 13 = `Failed to set param 6/7 … -ENODEV`, i.e. GuC clock writes on
     the dead GPU) → `Failed to reset GuC, ret = -110` → `device wedged,
     needs recovery` (29 in that boot, 0 in every boot since) → Hyprland's GL assert + the
     quickshell crash-loop. The kernel was alive throughout (llama-swap served to 09:36:46, then
     `Activating special unit System Power Off` at 09:37:19 = power button), so the "lockup" was
     the display path, not the machine. LACT then looped on DRM change events → GPU reload →
     iGPU clock writes against a dead GPU (`min/max_freq_mhz_dev_store` WARNINGs) every few
     seconds; its stale PCI entries (`could not find GPU … defined in configuration`, also at a
     clean boot) are noise, and the i915 min/max-clock churn is its own doing → § lact.
     Grep the GPU narrowly or the machine side lies to you — and check the index first with
     `journalctl --list-boots`, because `-1` walks back every reboot (the wedge boot was `-1`
     that morning, `-2` after the next reboot):
     `journalctl -k -b -2 | grep -E "i915.*(\*ERROR\*|wedged|GPU HANG|Resetting chip|Failed to reset GuC|freq_mhz_dev_store)"`
     → 32 hits in the wedge boot, 0 in every clean boot. Do **not** grep a bare `GUC` (it matches
     the normal `GUC: submission/SLPC/RC enabled` bring-up lines) or bare `TLB invalidation|WARNING`
     (that catches the IOMMU boot banner `iommu: DMA domain TLB invalidation policy: lazy mode`,
     which is the VT-d **IOTLB** flush policy for `dma_unmap` — lazy = batched flush queue,
     strict = synchronous via `iommu.strict=1` — not the GPU's GTTLB that GuC failed to flush, and
     moot here anyway: every group in `/sys/kernel/iommu_groups/*/type` reads `identity`, and
     `pci-stub.ids` is the audio IRQ-storm fix → § boot, not VFIO, so strict mode buys nothing).
  4. Two gotchas: llama-swap's `prompt_per_second` counts **new tokens only**, so a request that
     restores 44k cached KV and reads 34 new tokens prints ~19 "prompt" tok/s — that is the KV
     restore, not prefill (real prefill stayed 1,500–2,300 tok/s through the collapse). And the
     `strata monitor` containers paint their TUI to stdout, so conmon pushes it to journald
     (~76 lines/s, 32k lines in 7 min) — which is exactly where the tok/s curve came from when
     the engine log was gone, and why the sampler writes CSV instead.

## lact

LACT manages every GPU it detects, so there is no iGPU entry in `~/.config/lact/config.yaml` to delete — the iGPU (`8086:7D67-1849:7D67-0000:00:02.0`) only shows up at runtime (`lact cli list`). That file is hand-edited: `services.lact` does not generate it, `environment.etc."lact/config.yaml".source` symlinks `/etc/lact/config.yaml` to it. Edit with `lactd` stopped, because the daemon rewrites it.

What turned the 09:36 wedge into a 22-second kernel WARNING storm was LACT's **clock reset** path: every config reload resets clock tables for each GPU it holds, including i915's min/max clock files. With GuC dead those writes failed inside i915 — `lact: could not reset max/min clock` plus 28 i915 `min/max_freq_mhz_dev_store` / `max_freq_mhz_dev_store` backtraces in ~12 s — and the daemon stop at 09:37:19 failed the same way on NVIDIA (`could not reset the clocks table: Could not reset VF curve`). Two switches, both active: `daemon.disable_clocks_cleanup: true` in that config (daemon-level, so it needs `systemctl restart lactd`), and `systemd.services.lactd.serviceConfig.ExecStartPost`, which runs `lact cli --gpu-id=8086:7D67-1849:7D67-0000:00:02.0 detach` on every lactd start. `detach`/`reattach` (0.10.0+) is runtime daemon state — no config key for it — so it is re-applied per start; `lact cli list` afterwards should list only the two NVIDIA cards.

Stale GPU ids from another machine (`0c:00.0`, `01:00.0`, `81:00.0`, `05:00.0`) were pruned: they logged `could not find GPU … defined in configuration` on every start and could apply a profile to the wrong card if slot numbering shifted after resume. Live ids are `10DE:2203-1458:40A6-0000:03:00.0` (3090 Ti) and `10DE:2C05-19DA:2765-0000:02:00.0` (5070 Ti), with `current_profile: LLM`. None of this fixes the wedge itself — i915 GuC on Meteor Lake after an S3 cycle is the trigger, and the display still hangs on card1.

## systemd

- `sleep.settings.Sleep`: suspend allowed, hibernation / hybrid / suspend-then-hibernate
  off.
- `tmpfiles.rules` `Z /sys/class/powercap/intel-rapl:0/energy_uj 0444` — makes the RAPL
  energy counter world-readable so btop can show Intel CPU package wattage.
- **`llama-swap.service` override.** The module hardens its unit for a self-contained
  Go server (`DynamicUser`, `PrivateUsers`, `ProtectHome`, syscall deny list).
  llama-swap must exec the podman client against javi's rootless socket, so it runs as
  `javi`/`users` with those off (`DynamicUser`/`PrivateUsers`/`ProtectHome`/
  `NoNewPrivileges`/`RestrictNamespaces` forced false, `SystemCallFilter` back to
  `@system-service`), with `PATH=/run/current-system/sw/bin` and
  `CONTAINER_HOST=unix:///run/user/1000/podman/podman.sock`. `StateDirectory =
  "llama-swap"` creates `/var/lib/llama-swap` owned by javi and writable through
  `ProtectSystem=strict` — that is where `store.path`'s activity.sqlite lives.
  `ExecStartPre` `mkdir -p`s the two config binds: **every bind in the cmds is a
  directory, and the host side must exist as one** — an absent path becomes an empty
  directory, and an empty `/data/install` sends the strata entrypoint through a full
  setup pass with none of the tuned settings. No single-file binds are left, so there
  is nothing to `touch`.
- **`llamacpp-sleep-guard`** stops llama-swap (and whichever backend container it holds)
  before NVIDIA suspend and restarts it after resume. llama-swap stops its upstream
  process on SIGTERM, so stopping the unit is enough; the preloaded Strata returns with
  it. It stops the **unit**, not just the container: `Restart=on-failure` would have
  systemd bring llama-swap straight back mid-suspend, and `systemctl stop` takes it out
  of the active set, which the `ExecStop` bookkeeping keys on. `ExecStart` is not run
  through a shell, so the "which units were active before suspend" bookkeeping lives in
  a `writeShellScript` (written to `/run/llm-sleep-guard.active`).

## packages

`pkgs.apple-cursor` used to sit in `environment.systemPackages` here — it now lives
inline in `common.nix`'s `systemPackages` list, hostName-gated to homepc. Reason:
moving it between module contributions re-hashes the system profile and drags a dbus
restart into an otherwise byte-identical switch (see the comment in `common.nix`).

Remaining homepc-only packages: `jellyfin-media-player`, `level-zero` (oneAPI Level
Zero), `libmtp`, `nvidia_oc`, `nvtopPackages.nvidia`, `unstable.btop-cuda` (wrapped
below with `cap_perfmon`), and the `security.wrappers.btop` root-owned wrapper that
gives btop `cap_perfmon=ep` for GPU/CPU perf counters. `environment.etc."lact/config.yaml"`
binds the host-editable `~/.config/lact/config.yaml` into `/etc` for the LACT GPU
overclocker (enabled with `unstable.lact`).

`imports`: `../common.nix` (shared config, `unstable` comes from its `_module.args`)
and `./hardware-configuration.nix`; `./openvino.nix` is commented out.
