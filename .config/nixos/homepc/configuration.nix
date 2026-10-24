{
  config,
  lib,
  pkgs,
  # modulesPath,
  unstable,
  ...
}:

let
  # --- TEMPORARY iwlwifi firmware test (DISABLED 2026-09-20, rolled back
  # --- to stock linux-firmware / c106). Un-comment this binding + the
  # --- enableRedistributableFirmware/firmware overrides below to force
  # --- the driver to load c102 again (hides c106 + c103).
  # linuxFirmwareNoC102Newer = pkgs.runCommand "linux-firmware-no-iwlwifi-c103-c106"
  #   { src = pkgs.linux-firmware; } ''
  #   cp -r $src/. $out
  #   chmod -R u+w $out
  #   rm -f $out/lib/firmware/iwlwifi-gl-c0-fm-c0-c106.ucode
  #   rm -f $out/lib/firmware/iwlwifi-gl-c0-fm-c0-c103.ucode
  # '';
in
{
  # Hardware configuration
  hardware = {
    bluetooth.enable = true;
    # TEMPORARY iwlwifi firmware test (see let-block at top) — DISABLED:
    # enableRedistributableFirmware = lib.mkForce false;
    # firmware = with pkgs; [
    #   linuxFirmwareNoC102Newer
    #   ipw2200-firmware
    #   rtl8192su-firmware
    #   rt5677-firmware
    #   rtl8761b-firmware
    #   zd1211fw
    #   alsa-firmware
    #   sof-firmware
    #   libreelec-dvb-firmware
    # ];
    graphics = {
      enable = true;
      extraPackages = with pkgs; [
        intel-media-driver
        vpl-gpu-rt
      ];
    };
    i2c.enable = true;
    nvidia = {
      # Modesetting is required.
      # modesetting.enable = true;

      # Experimental, can break sleep/suspend; saves the whole VRAM to /tmp on
      # suspend, which fixes corruption/crashes after wake.
      powerManagement.enable = true;
      powerManagement.finegrained = false;  # per-GPU off; Turing+ only
      # Open kernel module (Turing+, driver >= 515.43.04) - not nouveau.
      open = true;
      nvidiaSettings = true;

      # Kernel AND driver must come from the same linuxPackages set (mixing them
      # once failed with "inconsistent kernel versions" in the modules
      # aggregator). 6.18.53 LTS + nvidia 615.71.09 / CUDA 13.4, both prebuilt on
      # cache.nixos.org. The release channel prebuilds nvidia only for 6.12/6.18
      # at 595.71.05 (CUDA 12.x), which would break the CUDA-13 llama-cuda
      # container - hence unstable. (2026-09-22: was linuxPackages_7_2, non-LTS.)
      package = unstable.linuxPackages_6_18.nvidiaPackages.latest;
      # package = config.boot.kernelPackages.nvidiaPackages.beta;
      # package = config.boot.kernelPackages.nvidiaPackages.mkDriver {
      #   version = "570.124.04"; # use new 570 drivers
      #   sha256_64bit = "sha256-G3hqS3Ei18QhbFiuQAdoik93jBlsFI2RkWOBXuENU8Q=";
      #   openSha256 = "sha256-DuVNA63+pJ8IB7Tw2gM4HbwlOh1bcDg2AN2mbEU9VPE=";
      #   settingsSha256 = "sha256-9rtqh64TyhDF5fFAYiWl3oDHzKJqyOW3abpcf2iNRT8=";
      #   usePersistenced = false;
      # };
    };
    nvidia-container-toolkit.enable = true;
    # nvidia.prime = {
    #   offload = {
    #     enable = true;
    #     enableOffloadCmd = true;
    #   };
    #   intelBusId = "PCI:0:2:0";
    #   nvidiaBusId = "PCI:1:0:0";
    # };
  };

  # Boot configuration
  boot = {
    # pci-stub claims the two headless NVIDIA HDMI-audio functions (5070 Ti
    # 10de:22e9, 3090 Ti 10de:1aef) so snd_hda_intel can never bind them. Their
    # codecs are power-gated (no display attached), so the first HDA verb times
    # out ("azx_get_response timeout, switching to polling mode" -> "irq 17:
    # nobody cared ... Disabling IRQ #17"): MSI is off for both (vga_switcheroo
    # audio client), so they share legacy PIC IRQ 17, which the kernel masked
    # after ~200k unhandled interrupts. In the initrd so the claim precedes
    # snd_hda_intel being loadable. Audio is unaffected (sinks are the iGPU/PCH
    # HDMI card3 + USB Audio). To revert: drop these two lines, the
    # pci-stub.ids kernelParam, and the driver_override udev rules.
    initrd.availableKernelModules = [ "pci-stub" ];
    initrd.kernelModules = [ "pci-stub" ];
    initrd.systemd.enable = true;
    initrd.verbose = false;
    kernelModules = [ "i2c-dev" "pci-stub" ];
    # boot.extraModulePackages = [ ];
    loader.systemd-boot.consoleMode = "max";
    loader.timeout = 0;
    kernelParams = [
      "quiet"
      "splash"
      "boot.shell_on_fail"
      "rd.systemd.show_status=auto"
      "udev.log_priority=3"
      "reboot=pci,cold"
      # IDs for pci-stub to claim (reaches it in the initrd and the root system).
      "pci-stub.ids=10de:22e9,10de:1aef"
    ];
    # Silence the two Intel DPTF/DTT "ACPI BIOS Error (bug)" pairs on the
    # console (boot + reboot):
    #   \_SB.PC00.LPCB.HEC.DPTF.FCHG AE_NOT_FOUND -> aborts \_SB.IETM.CHRG.PPSS
    #   \_TZ.ETMD                     AE_NOT_FOUND -> aborts \_SB.IETM._OSC
    # They are bugs in this BIOS' AML, not ours, and ACPICA prints them
    # unconditionally at KERN_ERR (verified: acpi.debug_level=0 does not gate
    # them - ACPI_MSG_BIOS_ERROR is hard-coded as KERN_ERR). Dropping the
    # console loglevel 4 -> 3 hides exactly KERN_ERR from the console; KERN_CRIT
    # and worse (panics) still print, and nothing is lost from the journal:
    # journalctl -k -p err. Revert by deleting this line (back to default 4).
    consoleLogLevel = 3;
    kernelPackages = unstable.linuxPackages_6_18; # 6.18.53 LTS; must match hardware.nvidia.package (same set)
    blacklistedKernelModules = [ "spd5118" ];
    # extraModprobeConfig = ''
    #   options nvidia NVreg_PreserveVideoMemoryAllocations=0
    #   (disabled - powerManagement.enable = false handles this)
    # '';
    kernel.sysctl = {
      "vm.blockdev.readahead" = "2048";
    };
  };

  # RLIMIT_MEMLOCK for Strata and Maya: mlock() of the expert arena and MAP_HUGETLB both
  # need it (a rootless container's CAP_IPC_LOCK does not count against
  # init_user_ns). Rootless podman inherits the user manager's 8 MiB default, so
  # the unit's `--ulimit memlock=-1` is dropped silently and the engine logs
  # "mlock failed (raise ulimit -l)". PAM raises javi's hard limit at login and
  # the user manager hands it to its units (podman.service -> crun -> container).
  # Needs a re-login; the hugepages need a reboot.
  security.pam.loginLimits = [
    { domain = "javi"; type = "-"; item = "memlock"; value = "unlimited"; }
  ];
  systemd.user.extraConfig = ''
    DefaultLimitMEMLOCK=infinity
  '';

  # Network configuration
  networking = {
    hostName = "homepc"; # Define your hostname.
    useDHCP = lib.mkDefault true;
    # :8080 is llama-swap, the single front door; it publishes the backends on
    # 5800+ (startPort), which the firewall leaves closed. 8080 itself is opened
    # by services.llama-swap.openFirewall - one place to change the port.
    # interfaces.enp3s0.mtu = 9000;
    # wireless.enable = lib.mkForce false; # Enables wireless support via wpa_supplicant.
  };

  # Nix configuration
  nixpkgs.config.cudaSupport = true;
  nixpkgs.hostPlatform = lib.mkDefault "x86_64-linux";

  # ReadyNAS "Media" share.  Mounted on first access (noauto + x-systemd.automount),
  # never at boot, so an absent NAS cannot slow or fail boot (nofail + 30 s timeout);
  # it unmounts itself after 10 min idle.  NFSv3 because the NAS runs nfsd with
  # --no-nfs-version 4; nolock avoids needing rpc.statd.  Address by IP because
  # "readynas" resolves via DNS only (not /etc/hosts).
  fileSystems."/mnt/readynas-media" = {
    device = "172.16.99.6:/READYNAS/Media";
    fsType = "nfs";
    options = [
      "vers=3"
      "nolock"
      "proto=tcp"
      "hard"
      "timeo=600"
      "retrans=2"
      "noatime"
      "rw"
      "_netdev"
      "nofail"
      "noauto"
      "x-systemd.automount"
      "x-systemd.mount-timeout=30"
      "x-systemd.idle-timeout=10min"
    ];
  };

  # Virtualisation configuration
  # Unprivileged qemu (fixes libvirt's "tainted: running with undesirable
  # elevated privileges" warning); guest files must be owned by qemu-libvirtd.
  virtualisation.libvirtd.qemu.runAsRoot = false;
  # Search-only $HOME so qemu-libvirtd can reach the images in ~/images/omarchy-vm.
  users.users.javi.homeMode = "751";

  # Security configuration
  security = {
    rtkit.enable = true;
    wrappers = {
      btop = {
        enable = true;
        owner = "root";
        group = "root";
        source = "${unstable.btop-cuda}/bin/btop";
        capabilities = "cap_perfmon=ep";
      };
    };
  };

  # Desktop shell: DankMaterialShell is homepc-only. It was in common.nix until
  # 2026-10-18; moving it here keeps the dell on the bare hyprland stack
  # (waybar + dunst + hypridle + hyprlock) instead of having dms.service,
  # matugen theming and DMS's org.freedesktop.Notifications owner everywhere.
  programs = {
    dms-shell = {
      # quickshell-based desktop shell (bar, notifications, launcher, lock
      # screen, OSD) for the hyprland session. Trial config; the shell's own
      # settings live imperatively in ~/.config/quickshell/ii/ and ~/.config/hypr
      # (deployed by `dms setup`), only the package/service here.
      enable = true;

      # The nixos-26.05 channel build is 1.4.6, two majors behind upstream, and
      # the module's feature toggles track it. Take the shell and quickshell from
      # <nixpkgs-unstable> together so the QML API (1.6.2) and the `qs` binary
      # (0.3.1) agree - mixing 1.6.2 with the channel's quickshell 0.3.0 risks
      # QML calling into qs APIs that do not exist yet.
      package = unstable.dms-shell;
      quickshell.package = unstable.quickshell;

      # dms.service ships in the package (lib/systemd/user/dms.service) and the
      # module pulls it in through systemd.packages. uwsm brings up
      # graphical-session.target, which is what the unit is PartOf/Requisite of,
      # so the module default target is correct for the uwsm hyprland session.
      systemd = {
        enable = true;
        restartIfChanged = true;
      };

      enableSystemMonitoring = true; # dgop: CPU/RAM/net widgets + process list
      enableDynamicTheming = true; # matugen: wallpaper -> DMS/rofi/gtk palette
      enableCalendarEvents = true; # khal (calendar widget; needs ~/.config/khal)
      enableClipboardPaste = true; # wtype for Shift+Return in clipboard history

      # The VPN widget drives NetworkManager, which is inactive here (plain iwd).
      enableVPN = false;
      # enableAudioWavelength is deliberately left at its default (true -> the
      # module installs cava). It was pinned to false here until 2026-10-18,
      # which is the only reason `dms doctor` reported "cava: Missing" (the
      # doctor treats cava as an important dep and warns whenever it is off
      # PATH, whether or not the visualizer widget is used). Do not re-add it:
      # newer nixpkgs removes the option entirely (cava is unconditional in
      # programs.dms-shell's environment), so the assignment breaks the build
      # on the next channel bump. CavaService.qml still gates the process on
      # the widget actually asking for it, and DMS_DISABLE_CAVA=1 disables it.
    };

    # Hyprland 0.56+ for DMS compositor blur (ext-background-effect-v1).
    # The channel (nixos-26.05) ships 0.55.4, which predates
    # src/protocols/BackgroundEffect.cpp; 0.56.2 is the first release with the
    # global, so `dms doctor` "Background Blur: Unsupported" is unfixable by
    # config on 0.55 - DMS probes the Wayland registry for
    # ext_background_effect_manager_v1 (core/internal/blur/probe.go).
    # Same package/channel-mixing trick as programs.dms-shell above: take the
    # compositor and its portal from <nixpkgs-unstable> as a pair (0.56.2 +
    # xdg-desktop-portal-hyprland 1.4.1) while the *module* stays the channel's
    # (0.56.2 adds no breaking config changes, and the Lua hyprland.lua works).
    # Scoped to homepc: the dell keeps the bare channel stack. Note this also
    # moves the DMS greeter's compositor, because
    # services.displayManager.dms-greeter builds its session from
    # config.programs.hyprland.package - if 0.56 misbehaves at the login
    # screen, drop these two lines and rebuild to get 0.55.4 back.
    hyprland = {
      package = unstable.hyprland;
      portalPackage = unstable.xdg-desktop-portal-hyprland;
    };
  };

  # DMS draws its own bar, so drop the waybar module's WantedBy (programs.waybar
  # stays enabled in common.nix) - the package and ~/.config/waybar/homepc.jsonc
  # remain, and deleting this line brings the bar straight back on this host only.
  systemd.user.services.waybar.wantedBy = lib.mkForce [ ];

  # Services
  services = {
    # DMS greeter (greetd-backed) replaces SDDM on this machine. Scoped to homepc
    # while trialing: a broken greeter means no graphical login, so dell keeps
    # sddm until this is proven. To roll out, move this block into common.nix and
    # drop the sddm mkForce there instead.
    displayManager = {
      # sddm is enabled in common.nix; override per-machine.
      sddm.enable = lib.mkForce false;

      dms-greeter = {
        enable = true;
        # 1.6.x ships the greeter as its own package (bin/dms-greeter). The
        # module default would be programs.dms-shell's package, whose 1.6.x
        # build no longer contains the Greetd assets this module execs.
        package = unstable.dms-greeter;
        # The greeter runs inside hyprland (the module asserts
        # programs.hyprland.enable and uses programs.hyprland.package).
        compositor.name = "hyprland";
        # The greeter runs hyprland as the dms-greeter user, which has no config of
        # its own, so Hyprland would default to a US layout at the login screen.
        #
        # This has to be LUA (hl.*), not hyprlang. dms-greeter sniffs the -C file
        # (launcher.isHyprlandLuaConfig: ".lua" suffix or a `(^|[^[:alnum:]_])hl\.`
        # match) and writes the config it hands Hyprland as either
        # $TMPDIR/dms-greeter-*.lua or, in the hyprlang branch,
        # $TMPDIR/dms-greeter-1234567890 with no extension at all. Hyprland picks
        # the config manager by that extension (src/config/ConfigManager.cpp:
        # anything not ".lua" -> Legacy/hyprlang mgr), and the legacy manager paints
        # the on-screen "You are using the .conf config format, support for which
        # will be removed in Hyprland 0.57." notification - which is why the nag
        # only ever showed on the login screen, the session itself being driven by
        # ~/.config/hypr/hyprland.lua. Hyprland 0.57 drops hyprlang outright, so a
        # .conf greeter config would stop being read at all, warning or not.
        compositor.customConfig = ''
          -- Cursor theme must come from env here: the greeter's Hyprland loads no
          -- DMS fragment (dms/cursor.lua belongs to the session), and Hyprland 0.55
          -- has no cursor:theme option at all -- HYPRCURSOR_*/XCURSOR_* are the only
          -- mechanism. XCursor only: apple-cursor ships XCursor, not hyprcursor.
          -- Theme itself comes from environment.systemPackages (pkgs.apple-cursor),
          -- since this serviceAccount has no per-user profile.
          hl.env("XCURSOR_THEME", "macOS")
          hl.env("XCURSOR_SIZE", "24")
          hl.config({
              input = {
                  kb_layout  = "no",
                  kb_options = "altwin:swap_lalt_lwin",
              },
          })
        '';
        # Copies ~/.config/DankMaterialShell/settings.json,
        # ~/.local/state/DankMaterialShell/session.json and
        # ~/.cache/DankMaterialShell/dms-colors.json - plus the wallpapers they
        # reference - into /var/lib/dms-greeter at greetd preStart, so the
        # greeter shows your wallpaper/theme.
        configHome = "/home/javi";
      };

      # hyprland-uwsm, not hyprland: uwsm is what brings up
      # graphical-session.target, which dms.service is PartOf/Requisite of.
      # Plain hyprland.desktop would log in with no DMS bar.
      defaultSession = "hyprland-uwsm";
    };

    # The 26.05 dms-greeter module execs
    #   ${package}/share/quickshell/dms/Modules/Greetd/assets/dms-greeter
    # which only exists in dms-shell <= 1.4.x, so with 1.6.2 greetd loops on
    # "greeter exited without creating a session" until it hits start-limit-hit.
    # Replicate the newer (unstable) module's invocation: ${package}/bin/dms-greeter.
    # Delete this override once the system channel's module uses bin/dms-greeter.
    greetd.settings.default_session.command = lib.mkForce (
      lib.getExe (
        pkgs.writeShellScriptBin "dms-greeter-start" ''
          export PATH=$PATH:${
            lib.makeBinPath [
              unstable.quickshell
              config.programs.hyprland.package
              pkgs.glib # gdbus: fprintd probe + portal reads
            ]
          }
          ${lib.getExe unstable.dms-greeter} --cache-dir /var/lib/dms-greeter --command hyprland${
            lib.optionalString (
              config.services.displayManager.dms-greeter.compositor.customConfig != ""
            ) " -C ${pkgs.writeText "dmsgreeter-compositor-config.lua" config.services.displayManager.dms-greeter.compositor.customConfig}"
          }
        ''
      )
    );

    hardware.bolt.enable = true;
    lact = {
      enable = true;
      package = unstable.lact;
    };
    openssh.enable = true;
    pipewire = {
      enable = true;
      alsa.enable = true;
      alsa.support32Bit = true;
      pulse.enable = true;
    };
    thermald.enable = true;
    udev.extraRules = ''
      ACTION=="add|change", KERNEL=="nvme0n1", ATTR{queue/read_ahead_kb}="2048"
      SUBSYSTEM=="usb", ATTR{idVendor}=="0955", MODE="0664", GROUP="plugdev"
      # The BE200 MLD driver re-registers under a new wiphy index every time
      # the iwlwifi-reload system-sleep hook runs, which would otherwise make
      # the interfaces appear as wlan2, wlan3, ... Pin the two card MACs to
      # stable names. iwd follows the device by wiphy, so the (variable)
      # station interface name is not functionally important.
      SUBSYSTEM=="net", ACTION=="add", ATTR{address}=="e8:bf:b8:5a:41:55", NAME="wlan0"
      SUBSYSTEM=="net", ACTION=="add", ATTR{address}=="e8:bf:b8:5a:41:56", NAME="wlan1"
      # Belt and braces for the pci-stub claim above: only pci-stub may ever
      # match these two HDA functions, so a manual `echo 1 > /sys/bus/pci/rescan`
      # or a hot re-bind can't put snd_hda_intel back on the legacy IRQ 17.
      SUBSYSTEM=="pci", ATTR{vendor}=="0x10de", ATTR{device}=="0x22e9", ATTR{driver_override}="pci-stub"
      SUBSYSTEM=="pci", ATTR{vendor}=="0x10de", ATTR{device}=="0x1aef", ATTR{driver_override}="pci-stub"
    '';

    xserver = {
      videoDrivers = [
        "modesetting"
        "nvidia"
      ];
    };
  };

  # The Intel Wi-Fi 7 BE200 (iwlmld) firmware state gets corrupted by
  # suspend/resume: the link stays nominal (80MHz 2x2, no retries) but
  # throughput collapses (~25 up / ~320 down on a 600/600 line) until the
  # driver is fully reloaded. Unload the wifi stack before suspend and
  # reload it after resume so the firmware is re-initialized cleanly on
  # every cycle — equivalent to a reboot, without one. iwd reconnects
  # automatically after the module reloads.
  # 2026-09-24: DISABLED to test whether kernel 6.18.53 (LTS) fixes the
  # BE200 suspend/resume issue without the reload workaround. If throughput
  # collapses again after a suspend cycle, un-comment this block.
  # environment.etc."systemd/system-sleep/iwlwifi-reload" = {
  #   source = "${pkgs.writeShellScriptBin "iwlwifi-reload" ''
  #     export PATH=/run/current-system/sw/bin:/run/booted-system/sw/bin:/usr/sbin:/usr/bin:/sbin:/bin
  #     case "$1/$2" in
  #       pre/*)
  #         # The BE200 (MLD) driver registers multiple wlan* interfaces;
  #         # bring them all down so the modules unload cleanly.
  #         for i in /sys/class/net/wlan*; do
  #           ip link set "$(basename "$i")" down 2>/dev/null
  #         done
  #         modprobe -r iwlmld iwlwifi 2>/dev/null
  #         ;;
  #       # NOTE: systemd calls post hooks as "post <sleep-type>" (e.g.
  #       # "post suspend"), so match any post action here.
  #       post/*)
  #         # Reload; iwd re-creates the interfaces and reconnects on its
  #         # own (the station may come back as wlan0 or wlan1).
  #         modprobe iwlmld 2>/dev/null
  #         ;;
  #     esac
  #   ''}/bin/iwlwifi-reload";
  # };

  # llama-swap: one front door on :8080 that picks the engine by the requested
  # model name and swaps the container behind it (topology A: it owns every
  # `podman run`, so only one backend holds the two cards at a time). Verified
  # against llama-swap v249 (unstable).
  #   - `models` keys are model names, never engine names: handleListModels
  #     (internal/server/api.go) always emits a record for the key, and
  #     `unlisted: true` continues *before* the alias loop - it hides the aliases
  #     with it. There is no "hide the primary, keep the aliases" switch.
  #   - llama.cpp is not routed here any more (2026-10-20): its Qwen3.8-27B Q8_0,
  #     the DFlash draft and the ggml-org MTP GGUF were deleted from the HF cache,
  #     deleted from the HF cache, so the llama.cpp entry is parked commented-out
  #     below, and the SC117 abliterated entry was deleted outright (same engine as
  #     the live Strata entry, only its weights are gone). Strata's MTP
  #     draft is its own (strata-data /data/Strata-data/mtp/rt - the 0.2.x image
  #     moves /data/models, /data/packs and /data/mtp under /data/Strata-data on its
  #     first start, by rename - extracted from the BF16 Qwen
  #     checkpoint), so it never needed those files. The llamacpp/strata/maya fallback
  #     units are gone: llama-swap is the only thing that starts containers now, and a
  #     hand-run podman is the fallback if weights are re-downloaded.
  #   - `${MODEL_ID}` / `${PORT}` are llama-swap macros: inside a Nix indented
  #     string they must be written ''${...} or they reach the YAML doubled.
  services.llama-swap = {
    enable = true;
    # Must be unstable (249): `capabilities` needs llama-swap >= 225 and the
    # channel's pkgs.llama-swap is 224, which drops the unknown key silently -
    # the YAML carries the block but /v1/models never renders it.
    package = unstable.llama-swap;
    openFirewall = true;   # opens 8080; the backend ports (5800+) stay closed
    listenAddress = "0.0.0.0";       # LAN clients already use homepc:8080
    port = 8080;

    settings = {
      logLevel = "info";

      # Engine output into journald: llama-swap always captures upstream (the
      # `podman run` client, so the container's stdout/stderr) in its monitors
      # (/logs/stream/upstream) but only echoes it to stdout when asked, and
      # `podman run --replace` destroys the container on every swap - without
      # this the previous engine's log is simply gone. v249 accepts exactly one
      # of proxy | upstream | both | none; a comma list ("proxy,upstream") is a
      # newer spelling that fails the unit with "logToStdout must be one of:
      # proxy, upstream, both, none". "both" also emits one access line/request.
      logToStdout = "both";
      logTimeFormat = "rfc3339";

      # Strata binds its port only once the model is in memory, so this must
      # cover a cold load (Strata docs/LLAMA_SWAP.md: 80 s on a Tesla V100 with
      # the GGUFs on a SATA SSD, 105 s while a download used the disk).
      # It is global, not per-model (llama-swap v262's own embedded docs: "healthCheckTimeout is
      # global (not per-model)"), so Maya's cold load sets the floor here: Maya pins its 44 GiB
      # RAM tier, copies the starting expert profile into VRAM and warms its caches before the
      # port opens - minutes, not seconds. Raising it costs nothing on the fast backends: it is
      # an upper bound on the wait, not a delay.
      healthCheckTimeout = 900;

      # graceful stop of the `podman run` client and the container
      unloadTimeout = 40;

      # backends get 5800+; only 8080 stays open in the firewall
      startPort = 5800;

      # a client that waits through a swap sees "loading ..." in the reasoning
      # field instead of a silent stall
      sendLoadingState = true;

      # no aliases right now, but keep them visible if a backend gets them back
      includeAliasesInList = true;

      # nothing is evicted by a timer; the group swaps on demand
      globalTTL = 0;

      models = {
        # --network host, so the container needs the port llama-swap assigned
        # (docker/entrypoint.sh passes PORT to `strata launch --port`). The key doubles as
        # the podman name via ${MODEL_ID} - legal under podman's
        # [a-zA-Z0-9][a-zA-Z0-9_.-]* (a llama.cpp-style `org/name:quant` key would not).
        # The 0.2.x image reads MODEL_PATH, not HF_CACHE (the latter is unknown to it: no
        # warning, just a fresh ~62 GB download into the volume). The mounts:
        # strata-data:/data holds the pack, the MTP draft and /data/gguf/IQ3_S, and
        # ~/.config/strata:/data/install (XDG_CONFIG_HOME) keeps the run settings and the web
        # app's chat settings host-editable. Mount the directory, not the file: setup.py saves
        # via <name>.tmp + os.replace, and renaming over a bind-mounted file fails with EBUSY.
        # The three model files are bound onto their names as FILES (from the HF cache blobs).
        # They used to be symlinks inside the volume pointing at /hf-cache/... - a target that
        # only exists inside a container - and that silently cost the tuned setup on every
        # start: `strata launch` decides whether to reuse the installed run settings with
        # installed_serves_request (strata_cli/launch/runner.py), which resolves every .gguf in
        # the config and requires it inside MODEL_PATH. Resolving a link lands in /hf-cache, so
        # the answer was no: setup.py ran each start, failed to see the cards (the image has no
        # runnable nvidia-smi: the CDI one from this host is a Nix binary whose PT_INTERP is a
        # /nix/store path that is not in the image), and its adopt fallback rewrote
        # strata-iq3_s.json from defaults - dropping the layer split, the tuned options, the
        # vision section and any "user_args". Bind-mounting the blobs makes those paths real
        # files, the reuse check passes, setup never runs, and the settings are ours to keep.
        # If the model is ever re-downloaded the blob names change: relink these three lines
        # (a missing file makes podman create an empty mount point, and the entrypoint then
        # stops with "MODEL_PATH holds no .gguf files" - it refuses to download a second copy).
        # The whole hub is NOT mounted any more (nothing in the image reads /hf-cache, and an
        # HF cache path is not a variable this image knows): with no /hf-cache in the container,
        # links that point there dangle and the start fails loudly instead of quietly sending
        # the launcher back through setup, which is how the tuned settings were lost.
        # The cards and the layer split are deliberately NOT env here: GPUS/LAYER_SPLIT env is
        # ignored by this image or makes setup re-derive the split as "auto". They live in the
        # launch preset (/home/javi/.config/strata/strata/launch-presets/docker.json: "gpus":
        # [0, 1] plus "extra" carrying --layer-split 32, --trim-stage-weights, --vram-reserve-*
        # 1024, --pipeline-windows 2, --spec-min-p 0.70, --pcie-frac 0.00, --kv int8, which
        # derive_config re-applies to every launch), and the picture reader lives in
        # strata-iq3_s.json's "vision" section (see ~/.config/strata/strata-vision).
        "qwen3.8-flash-next-iq3_s" = {
          cmd = ''
            podman run --replace --name ''${MODEL_ID}
            --network host
            --device nvidia.com/gpu=all
            --ulimit memlock=-1
            --shm-size 2g
            --stop-timeout 120
            --pull newer
            -v strata-data:/data
            -v /home/javi/.config/strata:/data/install
            -v /home/javi/.cache/huggingface/hub/models--ISTA-DASLab--Qwen3.8-Flash-Next-GSQ-RCO-GGUF/blobs/4c1eb2ceb4915e1192f4f386021897bde56a97f40a0bb78bb86465e0f7d2aca3:/data/gguf/IQ3_S/Qwen3.8-Flash-Next-GSQ-RCO-IQ3_S-00001-of-00002.gguf:ro
            -v /home/javi/.cache/huggingface/hub/models--ISTA-DASLab--Qwen3.8-Flash-Next-GSQ-RCO-GGUF/blobs/316b46f3a2dbd68c900f43136ab9449f9dcc3725dfd8c794847c204bc161e113:/data/gguf/IQ3_S/Qwen3.8-Flash-Next-GSQ-RCO-IQ3_S-00002-of-00002.gguf:ro
            -v /home/javi/.cache/huggingface/hub/models--ISTA-DASLab--Qwen3.8-Flash-Next-GSQ-RCO-GGUF/blobs/b1a82259702816a5330d7bd7607cd9676b11780e79ff7348c21103ff3ce49bd0:/data/gguf/IQ3_S/mmproj-Qwen3.8-Flash-Next-BF16.gguf:ro
            -e XDG_CONFIG_HOME=/data/install
            -e MODEL_PATH=/data/gguf/IQ3_S
            -e MODEL=IQ3_S
            -e PORT=''${PORT}
            -e STRATA_PF_FUSED=1
            -e STRATA_ADAPT_LAG=2
            -e STRATA_EXCHANGE_ROTATE=1
            ghcr.io/niko1221/strata:latest-cuda13
          '';
          cmdStop = ''podman stop -t 120 ''${MODEL_ID}'';
          checkEndpoint = "/health";
          ttl = 0;
          # `tools` renders as capabilities.function_calling = true plus
          # supported_parameters ["tools","tool_choice"] (api.go
          # renderCapabilities); without it Strata under-reports itself to clients
          # doing capability discovery.
          capabilities = {
            context = 262144;
            "in" = [ "text" "image" ];
            out = [ "text" ];
            tools = true;
          };
          # No aliases: the key is the public name, and every alias is listed too
          # (includeAliasesInList) - so the old engine name "strata" is dropped.
        };

        # Project Maya: GLM-5.3-Flash (321 B MoE; the hottest experts in VRAM, the rest read
        # through the page cache - RAM where they fit, NVMe otherwise). Image from
        # ~/dev/personal/project-maya (`podman build -t maya .`).
        #   - maya-data:/data holds the pack and the *links* to the model files, not their bytes;
        #     /data/config is the host's ~/.config/maya. Unlike Strata, Maya keeps its state
        #     next to its code (ROOT.glob("maya-*.json") in maya.py's configs(), and
        #     write_config() writes ROOT/maya-<quant>.json), and /opt/maya is the image's own
        #     throwaway layer - so docker-entrypoint.sh keeps the config, its .log and its
        #     .shared-settings.json on the host bind and symlinks them into /opt/maya. Every
        #     write to those paths is a plain write_text (no tmp + os.replace), so it follows
        #     the link and lands in ~/.config/maya, where you can edit it.
        #   - the model bytes live in the HF hub cache, not in the volume (like the Strata entry):
        #     docker-seed-hf.py links peasantsmith/GLM-5.3-Flash-Maya-GGUF's files from /hf-cache
        #     into maya-data's models folder, where maya.py's step 5 sees them as a finished
        #     download; the cache is mounted :ro and never written to, and the pack plus the
        #     .maya-verified.json record go beside the links. Keep mounting it after the setup:
        #     the links in the volume only resolve while /hf-cache is mounted.
        #     Get the files into the cache once with your usual HF downloader, e.g. (hf's --include
        #     takes one pattern per flag; verified 5 files, 95.8 GB, sha256s matching maya.py's pins):
        #       hf download peasantsmith/GLM-5.3-Flash-Maya-GGUF --include "Maya-S24/*" --include "vision/*"
        #   - the model is NOT downloaded by llama-swap: if the cache has nothing usable and no
        #     config exists, the entry point prints how to prime the volume and exits 1 rather than
        #     pulling 95 GB inside a backend llama-swap is already timing out on.
        #   - RAM_GB=44: see the hugepages block in kernelParams. Maya would otherwise size
        #     the tier from MemAvailable (~15 GiB here, because the 47 GiB pool is already
        #     charged against it) and stream the rest of the model on every token.
        #   - no API key and HOST=0.0.0.0: :8080 is llama-swap, the backend port stays closed,
        #     and --network host only works if the server binds outside loopback. Maya prints
        #     its own "WARNING: no API key" line at start for the same reason; it is about
        #     direct access on the backend port, which the firewall keeps closed anyway.
        "glm-5.3-flash-maya-s24" = {
          cmd = ''
            podman run --replace --name ''${MODEL_ID}
            --network host
            --device nvidia.com/gpu=all
            --ulimit memlock=-1
            -v maya-data:/data
            -v /home/javi/.config/maya:/data/config
            -v /home/javi/.cache/huggingface/hub:/hf-cache:ro
            -e HF_CACHE=/hf-cache
            -e MODEL=Maya-S24
            -e HOST=0.0.0.0
            -e PORT=''${PORT}
            localhost/maya:latest
          '';
          # 35 s, inside unloadTimeout above: podman's SIGTERM reaches maya.py (PID 1), which
          # stops serve/server.py the way Ctrl+C does (stop_signals), and Maya's own stop waits
          # up to 150 s for the request in flight plus the engine's QUIT (STOP_WAIT_S). A stop
          # that outlives llama-swap's wait is untidy but survivable: the next cmd uses
          # --replace, which removes whatever container is left.
          cmdStop = ''podman stop -t 35 ''${MODEL_ID}'';
          checkEndpoint = "/health";
          ttl = 0;
          # Maya's own defaults: maya.py's DEFAULT_CONTEXT (65536) and CONTEXT= above; keep the
          # two in step, the pack and the config are written at setup time with it.
          capabilities = {
            context = 131072;
            "in" = [ "text" "image" ];   # the vision tower runs on GPU 0 beside the model
            out = [ "text" ];
            tools = true;                # OpenAI + Anthropic tool calls (README, "Plugs into your tools")
          };
        };

        # llama.cpp backend PARKED 2026-10-20 (commented, not deleted): its weights
        # are gone from the HF cache (bartowski Qwen3.8-27B Q8_0, the HermiHg DFlash2
        # draft, and the ggml-org MTP draft), and the matching [sections] were dropped
        # from ~/.config/llamacpp/llama-preset.ini. Strata is the only live backend.
        # To bring it back: re-download the weights, restore the preset sections
        # (from ~/.config/llamacpp/llama-preset.ini.bak-20261020-mtp-and-27b-removal),
        # uncomment this entry *and* its group member below - note the ISTA names in
        # `aliases` collide with the Strata entry's name space, so keep at most one of
        # them claiming "ISTA-DASLab/...Flash-Next...:IQ3_S".
        # "bartowski/Qwen3.8-27B-GGUF:Q8_0" = {
        #   cmd = ''
        #     podman run --replace --name llama-swap-llamacpp
        #     -p ''${PORT}:8080
        #     --device nvidia.com/gpu=all
        #     -e GGML_CUDA_ALLREDUCE=internal
        #     -e CUDA_VISIBLE_DEVICES=1,0
        #     -v /home/javi/.cache/huggingface:/root/.cache/huggingface
        #     -v /home/javi/.config/llamacpp/llama-preset.ini:/app/llama-preset.ini:ro
        #     localhost/llama-cuda:mtmd-fix
        #     --models-preset /app/llama-preset.ini
        #     --models-max 1
        #     -lv 4
        #     -t 8
        #     -tb 8
        #   '';
        #   cmdStop = ''podman stop -t 30 llama-swap-llamacpp'';
        #   checkEndpoint = "/health";
        #   ttl = 0;
        #   # Every name (the key included) must match a [section] in
        #   # ~/.config/llamacpp/llama-preset.ini and stay unique across llama-swap:
        #   # the Flash-Next IQ3_S name belongs to the Strata entry only.
        #   aliases = [
        #     "bartowski/Qwen3.8-27B-GGUF:MTP_1P_180K"
        #     "bartowski/Qwen_Qwen3.6-35B-A3B-GGUF:Q6_K_L"
        #     "ISTA-DASLab/Qwen3.8-Flash-Next-GSQ-RCO-GGUF:IQ3_S"
        #     "ISTA-DASLab/Qwen3.8-27B-GSQ-RCO-GGUF:IQ3_S"
        #   ];
        # };

      };

      routing.router = {
        use = "group";
        settings.groups = {
          # Strata wants both cards: gpu [0,1] with layer_split 32
          gpu = {
            swap = true;        # one at a time
            exclusive = true;   # and it evicts every other group
            members = [
              "qwen3.8-flash-next-iq3_s"
              "glm-5.3-flash-maya-s24"
              # "bartowski/Qwen3.8-27B-GGUF:Q8_0"   # parked with the llama.cpp entry above
            ];
          };
        };
      };

      # The Activity page and /api/metrics/activity record to sqlite instead of the
      # in-memory ring (metricsMaxInMemory then has no effect); text logs
      # (/logs, /logs/stream/*) stay in-memory ring buffers either way. The
      # directory comes from StateDirectory in the unit below: ProtectSystem=strict
      # leaves /var read-only apart from what systemd opens.
      store.path = "/var/lib/llama-swap/activity.sqlite";

      # keep today's behaviour: Strata is loaded at boot, not on first request.
      # Maya is deliberately not preloaded: its cold load is minutes and it pins 44 GiB,
      # so it swaps in on request (its first request pays for that, sendLoadingState says so).
      hooks.on_startup.preload = [ "qwen3.8-flash-next-iq3_s" ];
    };
  };


  # Systemd configuration
  systemd = {
    sleep.settings.Sleep = {
      AllowSuspend = true;
      AllowHibernation = false;
      AllowHybridSleep = false;
      AllowSuspendThenHibernate = false;
    };

    # shows wattage in btop for intel cpus
    tmpfiles.rules = [ "Z /sys/class/powercap/intel-rapl:0/energy_uj 0444 root root - -" ];

    services = {

      # The module hardens its unit for a self-contained Go server (DynamicUser,
      # PrivateUsers, ProtectHome, syscall deny list). llama-swap must exec the
      # podman client against javi's rootless socket, so it runs as javi with those
      # off. It starts every backend container itself (per-model cmd), so no separate
      # container units live here any more - the manual fallback is a hand-run podman.
      llama-swap = {
        after = [ "network-online.target" ];
        wants = [ "network-online.target" ];
        serviceConfig = {
          User = "javi";
          Group = "users";
          # /var/lib/llama-swap: created owned by javi, writable through
          # ProtectSystem=strict. Holds store.path's activity.sqlite.
          StateDirectory = "llama-swap";
          DynamicUser = lib.mkForce false;
          PrivateUsers = lib.mkForce false;
          ProtectHome = lib.mkForce false;
          NoNewPrivileges = lib.mkForce false;
          RestrictNamespaces = lib.mkForce false;
          SystemCallFilter = lib.mkForce [ "@system-service" ];
          Environment = [
            "PATH=/run/current-system/sw/bin"
            "CONTAINER_HOST=unix:///run/user/1000/podman/podman.sock"
          ];
          # Every bind here is a directory, and the host side must exist as one: an
          # absent path becomes an empty directory, and an empty /data/install sends the
          # strata entrypoint through a full setup pass with none of the tuned settings.
          # No single-file binds are left, so there is nothing to touch.
          ExecStartPre = [
            "/run/current-system/sw/bin/mkdir -p /home/javi/.config/strata"
            # Maya's config/log/dashboard-settings bind (the entrypoint symlinks into it)
            "/run/current-system/sw/bin/mkdir -p /home/javi/.config/maya"
          ];
        };
      };

      # Stops llama-swap (and whichever backend container it holds) before suspend
      # and restarts it after resume. llama-swap stops its upstream process on
      # SIGTERM, so stopping the unit is enough; the preloaded Strata returns with it.
      llamacpp-sleep-guard = {
        description = "Stop the running LLM container before NVIDIA suspend, restart after resume";
        unitConfig = {
          Before = [ "nvidia-suspend.service" "sleep.target" ];
          StopWhenUnneeded = true;
        };
        serviceConfig = {
          Type = "oneshot";
          RemainAfterExit = true;
          # Stop the *unit*, not just the container: Restart=on-failure would have
          # systemd bring llama-swap straight back mid-suspend. `systemctl stop`
          # takes it out of the active set, which the ExecStop bookkeeping keys on.
          Environment = [ "CONTAINER_HOST=unix:///run/user/1000/podman/podman.sock" ];
          # ExecStart is not run through a shell, so the "which units were active
          # before suspend" bookkeeping lives in a script.
          ExecStart = "-${pkgs.writeShellScript "llm-sleep-guard-pre" ''
            if ${config.systemd.package}/bin/systemctl is-active --quiet llama-swap.service; then
              echo llama-swap
            fi > /run/llm-sleep-guard.active
            ${config.systemd.package}/bin/systemctl stop llama-swap || true
          ''}";
          ExecStop = "-${pkgs.writeShellScript "llm-sleep-guard-post" ''
            if [ -s /run/llm-sleep-guard.active ]; then
              ${config.systemd.package}/bin/systemctl restart $(cat /run/llm-sleep-guard.active)
            fi
            rm -f /run/llm-sleep-guard.active
          ''}";
        };
        wantedBy = [ "sleep.target" ];
      };
    };
  };

  # Environment configuration
  environment.systemPackages = [
    # pkgs.apple-cursor used to live here — it now sits inline in common.nix's
    # systemPackages list (hostName-gated to homepc), because moving it between
    # module contributions re-hashes the system profile and drags a dbus restart
    # into an otherwise byte-identical switch. See the comment there.
    pkgs.jellyfin-media-player
    pkgs.level-zero
    pkgs.libmtp
    pkgs.nvidia_oc
    pkgs.nvtopPackages.nvidia
    unstable.btop-cuda
  ];
  environment.etc."lact/config.yaml".source =
    "${config.users.users.javi.home}/.config/lact/config.yaml";

  imports = [
    ../common.nix
    ./hardware-configuration.nix
    # ./openvino.nix
  ];
}
