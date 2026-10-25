# homepc configuration.nix — rationale

Reasoning that used to live in `configuration.nix` comments. The `.nix` files carry
code plus one-line pointers; each pointer names the section (`§ name`) below.
Everything here describes the config **as it stands today**; disabled experiments are
marked as such and their code is still in the `.nix` file, commented out.

Index: [hardware](#hardware) · [wifi-firmware](#wifi-firmware) · [boot](#boot) ·
[memlock](#memlock) · [network](#network) · [readynas](#readynas) ·
[libvirt](#libvirt) · [dms-shell](#dms-shell) · [hyprland](#hyprland) ·
[waybar](#waybar) · [greeter](#greeter) · [udev](#udev) · [wifi-suspend](#wifi-suspend) ·
[llama-swap](#llama-swap) · [systemd](#systemd) · [packages](#packages)

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
  `boot.kernelPackages` is the same expression). This pins **6.18.53 LTS + nvidia
  615.71.09 / CUDA 13.4**, both prebuilt on `cache.nixos.org`. The nixos-26.05 channel
  only prebuilds nvidia for 6.12/6.18 at **595.71.05 (CUDA 12.x)**, which would break
  the CUDA-13 `llama-cuda` container — hence `<nixpkgs-unstable>`.
  - 2026-09-22: this was `linuxPackages_7_2` (non-LTS) before.
  - Still-disabled alternatives in the file: `config.boot.kernelPackages.nvidiaPackages.beta`
    and a hand-rolled `mkDriver` for the 570.124.04 legacy branch.
- `modesetting.enable` is commented out (the channel default already enables it).
- `nvidia.prime` (offload + the two bus IDs) is commented out — this is not a laptop
  Optimus setup; both cards are always present.
- `nvidia-container-toolkit.enable = true` gives the `--device nvidia.com/gpu=all`
  CDI hook used by the llama-swap backends ([§ llama-swap](#llama-swap)).
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
  are taken from `<nixpkgs-unstable>` **together** — DMS 1.6.2 QML API + `qs` 0.3.1 —
  because mixing 1.6.2 with the channel's quickshell 0.3.0 risks QML calling into `qs`
  APIs that do not exist yet.
- **Local patch** (`./patches/dms-preview-path.patch`, added 2026-10-24): Settings →
  Browse Themes builds every card's preview URL as
  `https://raw.githubusercontent.com/AvengeMedia/dms-plugin-registry/main/themes/<id>/preview.svg`
  and ignores the `previewPath` the daemon already resolves for third-party registries
  (core/internal/themes/registry.go stats `themes/<id>/preview.svg` in the local clone),
  so all `omarchy-*` cards render blank. That is the two-line fix. Drop the override
  once upstream ships it — check for `theme.previewPath` in
  `quickshell/Modules/Settings/ThemeBrowser.qml` of the new version (upstream master
  still has the hardcoded line as of writing).
  The `postPatch` wrapper needs its own care: nixpkgs sets `sourceRoot = "source/core"`,
  the QML tree is one level up, and the fetched tree is read-only → `chmod -R u+w`
  before `patch`.
- **`systemd.enable = true`**: `dms.service` ships in the package
  (`lib/systemd/user/dms.service`) and the module pulls it in through `systemd.packages`.
  uwsm brings up `graphical-session.target`, which the unit is `PartOf`/`Requisite` of,
  so the module's default target is correct for the uwsm hyprland session.
  `restartIfChanged = true` restarts it on config changes.
- Feature toggles: `enableSystemMonitoring` (dgop: CPU/RAM/net widgets + process list),
  `enableDynamicTheming` (matugen: wallpaper → DMS/rofi/gtk palette),
  `enableCalendarEvents` (khal; needs `~/.config/khal`), `enableClipboardPaste`
  (wtype for Shift+Return in clipboard history).
- **`enableVPN = false`** — the VPN widget drives NetworkManager, which is inactive
  here (plain iwd).
- **`enableAudioWavelength` is deliberately left at its default (true → installs cava).**
  It was pinned to `false` here until 2026-10-18, which is the only reason `dms doctor`
  reported "cava: Missing" (the doctor treats cava as an important dep and warns
  whenever it is off PATH, whether or not the visualizer widget is used).
  **Do not re-add the assignment:** newer nixpkgs removes the option entirely (cava is
  unconditional in `programs.dms-shell`'s environment), so the assignment breaks the
  build on the next channel bump. `CavaService.qml` still gates the process on the
  widget actually asking for it, and `DMS_DISABLE_CAVA=1` disables it.

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

- **`package = unstable.dms-greeter`** — 1.6.x ships the greeter as its own package
  (`bin/dms-greeter`). The module default would be `programs.dms-shell`'s package,
  whose 1.6.x build no longer contains the Greetd assets this module execs.
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

### llama-swap/strata — `qwen3.8-flash-next-iq3_s`

- The key doubles as the podman name via `${MODEL_ID}` — legal under podman's
  `[a-zA-Z0-9][a-zA-Z0-9_.-]*` (a llama.cpp-style `org/name:quant` key would not).
- `--network host`, so the container needs the port llama-swap assigned
  (`docker/entrypoint.sh` passes `PORT` to `strata launch --port`).
- **The 0.2.x image reads `MODEL_PATH`, not `HF_CACHE`** (the latter is unknown to it:
  no warning, just a fresh ~62 GB download into the volume).
- Mounts: `strata-data:/data` holds the pack, the MTP draft and `/data/gguf/IQ3_S`;
  `~/.config/strata:/data/install` (`XDG_CONFIG_HOME`) keeps the run settings and the
  web app's chat settings host-editable. **Mount the directory, not the file**:
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
  makes those paths real files, the reuse check passes, setup never runs, and the
  settings stay ours. **If the model is ever re-downloaded the blob names change:
  relink those three lines** (a missing file makes podman create an empty mount point,
  and the entrypoint then stops with "MODEL_PATH holds no .gguf files" — it refuses to
  download a second copy). The whole hub is **not** mounted any more (nothing in the
  image reads `/hf-cache`, and an HF cache path is not a variable this image knows):
  with no `/hf-cache` in the container, links that point there dangle and the start
  fails loudly instead of quietly sending the launcher back through setup — which is
  how the tuned settings were lost.
- **The cards and the layer split are deliberately NOT env here**: `GPUS`/`LAYER_SPLIT`
  env is ignored by this image or makes setup re-derive the split as "auto". They live
  in the launch preset `~/.config/strata/strata/launch-presets/docker.json`
  (`"gpus": [0, 1]` plus `extra` carrying `--layer-split 32`, `--trim-stage-weights`,
  `--vram-reserve-* 1024`, `--pipeline-windows 2`, `--spec-min-p 0.70`,
  `--pcie-frac 0.00`, `--kv int8`, which `derive_config` re-applies to every launch);
  the picture reader lives in `strata-iq3_s.json`'s `"vision"` section
  (see `~/.config/strata/strata-vision`).
- **`--cgroup-conf memory.swap.max=0` (inside `cmd`).** The expert arena here is
  anonymous memory: the engine's `MAP_HUGETLB` ask fails
  ("needed 23983 2 MiB pages, vm.nr_hugepages=0", see `~/.config/strata/strata-iq3_s.log`)
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
  `exclusive = true` (it evicts every other group), members = Strata + Maya (+ the
  parked llama.cpp entry). Strata wants both cards: `gpus [0,1]` with `layer_split 32`.
- `store.path = /var/lib/llama-swap/activity.sqlite` — the Activity page and
  `/api/metrics/activity` record to sqlite instead of the in-memory ring
  (`metricsMaxInMemory` then has no effect); text logs (`/logs`, `/logs/stream/*`) stay
  in-memory ring buffers either way. The directory comes from `StateDirectory` in the
  unit override below: `ProtectSystem=strict` leaves `/var` read-only apart from what
  systemd opens.
- `hooks.on_startup.preload = [ "qwen3.8-flash-next-iq3_s" ]` — keeps today's behaviour:
  Strata is loaded at boot, not on first request. **Maya is deliberately not
  preloaded**: its cold load is minutes and it pins 44 GiB, so it swaps in on request
  (its first request pays for that, and `sendLoadingState` says so).

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
