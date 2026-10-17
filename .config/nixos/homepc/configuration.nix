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
      # 2 MB hugepages for Strata's expert arena: it requests
      # MAP_HUGETLB|MAP_HUGE_2MB (src/core/pinned.cu) and falls back to 4 KB
      # pages with no pool, costing 12.2M first-touch faults + zeroing on the
      # 46.84 GiB load and letting expert pages be swapped. Arena =
      # 50,294,502,400 B = 23,983 pages; 24,064 (47 GiB) leaves ~15 GiB of the
      # 62 GiB for everything else. See the memlock block below.
      # GOTCHA: the count must be "hugepages=N" directly after its "hugepagesz="
      # - vm.nr_hugepages= on the cmdline is a sysctl name, silently ignored
      # (dmesg then reports "pre-allocated 0 pages").
      "default_hugepagesz=2M"
      "hugepagesz=2M"
      "hugepages=24064"
      # "pcie_aspm.policy=performance"
      # "pcie_aspm.policy=powersupersave"
      # "pci=assign-busses,hpbussize=0x33,realloc,hpmmiosize=128M,hpmmioprefsize=1G"
      # "pci=realloc"
      # "pcie_aspm=off"
      # "pcie_port_pm=off"
      # "nvidia.NVreg_PreserveVideoMemoryAllocations=1"
      # "nvidia-drm.modeset=1"
      # "nvidia-drm.fbdev=1"
    ];
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

  # RLIMIT_MEMLOCK for Strata: mlock() of the expert arena and MAP_HUGETLB both
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

  # Filesystems
  fileSystems."/mnt/scratch" = {
    device = "UUID=f35b18d6-2d87-43f3-a8be-6a5c91abb95c";
    fsType = "ext4";
  };

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
        compositor.customConfig = ''
          # Cursor theme must come from env here: the greeter's Hyprland loads no
          # DMS fragment (dms/cursor.lua belongs to the session), and Hyprland 0.55
          # has no cursor:theme option at all -- HYPRCURSOR_*/XCURSOR_* are the only
          # mechanism. XCursor only: apple-cursor ships XCursor, not hyprcursor.
          # Theme itself comes from environment.systemPackages (pkgs.apple-cursor),
          # since this serviceAccount has no per-user profile.
          env = XCURSOR_THEME,macOS
          env = XCURSOR_SIZE,24
          input {
              kb_layout = no
              kb_options = altwin:swap_lalt_lwin
          }
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
            ) " -C ${pkgs.writeText "dmsgreeter-compositor-config" config.services.displayManager.dms-greeter.compositor.customConfig}"
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
  #   - llama.cpp keeps its own router mode (--models-preset, --models-max 1): the
  #     preset names are aliases of the ONE entry and the requested name is
  #     forwarded untouched (filters.go rewrites `model` only when useModelName is
  #     set), so switching GGUF inside llama.cpp costs a weight reload while
  #     switching engine costs a container restart.
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
      healthCheckTimeout = 300;

      # graceful stop of the `podman run` client and the container
      unloadTimeout = 40;

      # backends get 5800+; only 8080 stays open in the firewall
      startPort = 5800;

      # a client that waits through a swap sees "loading ..." in the reasoning
      # field instead of a silent stall
      sendLoadingState = true;

      # the llama.cpp presets are aliases of one entry, so list them
      includeAliasesInList = true;

      # nothing is evicted by a timer; the group swaps on demand
      globalTTL = 0;

      models = {
        # --network host, so the container needs the port llama-swap assigned
        # (docker-entrypoint.sh passes PORT to serve/server.py). The key doubles as
        # the podman name via ${MODEL_ID} - legal under podman's
        # [a-zA-Z0-9][a-zA-Z0-9_.-]*, unlike the llama.cpp key below.
        "qwen3.8-flash-next-iq3_s" = {
          cmd = ''
            podman run --replace --name ''${MODEL_ID}
            --network host
            --device nvidia.com/gpu=all
            --ulimit memlock=-1
            -v strata-data:/data
            -v /home/javi/.config/strata:/data/config
            -v /home/javi/.config/strata/strata-iq3_s.shared-settings.json:/opt/strata/strata-iq3_s.shared-settings.json
            -v /home/javi/.cache/huggingface/hub:/hf-cache:ro
            -e HF_CACHE=/hf-cache
            -e MODEL=IQ3_S
            -e VISION=yes
            -e PORT=''${PORT}
            localhost/strata:latest
          '';
          cmdStop = ''podman stop -t 30 ''${MODEL_ID}'';
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

        # The same IQ3_S tier abliterated (SC117/Qwen3.8-Flash-Next-GSQ-RCO-abliterated-GGUF):
        # same engine, tuning and strata-data volume, but its own GGUFs, pack and
        # config. The pack cannot be shared - the transplant moved tensor offsets,
        # so the upstream pack fails with "ArenaExpertSource: the pack's
        # native_experts.txt does not match the model". --mtp stays /data/mtp/rt:
        # the draft layer comes from the stock Qwen checkpoint (no abliterated MTP
        # head is published), so both Strata models share it.
        # MODEL names only the tag: SC117-IQ3_S -> sc117-iq3_s, so the entrypoint
        # reads /data/config/strata-sc117-iq3_s.json (already written: no setup
        # pass, and an unknown --model fails loudly instead of re-downloading) and
        # serve/server.py keeps the Chat settings beside it - hence the
        # strata-sc117-iq3_s.shared-settings.json mount.
        # One-time prep already done in strata-data (2026-10-15): the GGUFs at
        # /data/gguf/sc117-iq3_s/{shard1,shard2,mmproj} are symlinked into the
        # read-only /hf-cache (same trick as seed_gguf_dir), and the pack was built
        # with tools/iq_pack.py --gguf /data/gguf/sc117-iq3_s/<shard1>
        #      --out /data/packs/sc117_iq3_s
        "qwen3.8-flash-next-abliterated-iq3_s" = {
          cmd = ''
            podman run --replace --name ''${MODEL_ID}
            --network host
            --device nvidia.com/gpu=all
            --ulimit memlock=-1
            -v strata-data:/data
            -v /home/javi/.config/strata:/data/config
            -v /home/javi/.config/strata/strata-sc117-iq3_s.shared-settings.json:/opt/strata/strata-sc117-iq3_s.shared-settings.json
            -v /home/javi/.cache/huggingface/hub:/hf-cache:ro
            -e HF_CACHE=/hf-cache
            -e MODEL=SC117-IQ3_S
            -e VISION=yes
            -e PORT=''${PORT}
            localhost/strata:latest
          '';
          cmdStop = ''podman stop -t 30 ''${MODEL_ID}'';
          checkEndpoint = "/health";
          ttl = 0;
          # distinct from the other Strata entry (qwen3.8-flash-next-iq3_s): the
          # two run the same architecture and the same quant, only the weights
          # differ
          capabilities = {
            context = 262144;
            "in" = [ "text" "image" ];
            out = [ "text" ];
            tools = true;
          };
          # no aliases, see the note on the other Strata entry
        };

        # One entry, five preset names: the key is itself a real preset section, so
        # the primary name resolves inside llama.cpp's router too and the other
        # four stay aliases. Container name is literal, not ${MODEL_ID}: podman
        # rejects `/` and `:` in names.
        "bartowski/Qwen3.8-27B-GGUF:Q8_0" = {
          cmd = ''
            podman run --replace --name llama-swap-llamacpp
            -p ''${PORT}:8080
            --device nvidia.com/gpu=all
            -e GGML_CUDA_ALLREDUCE=internal
            -e CUDA_VISIBLE_DEVICES=1,0
            -v /home/javi/.cache/huggingface:/root/.cache/huggingface
            -v /home/javi/.config/llamacpp/llama-preset.ini:/app/llama-preset.ini:ro
            localhost/llama-cuda:mtmd-fix
            --models-preset /app/llama-preset.ini
            --models-max 1
            -lv 4
            -t 8
            -tb 8
          '';
          cmdStop = ''podman stop -t 30 llama-swap-llamacpp'';
          checkEndpoint = "/health";
          ttl = 0;
          # Every name (the key included) must match a [section] in
          # ~/.config/llamacpp/llama-preset.ini and stay unique across llama-swap:
          # the Flash-Next IQ3_S name belongs to the Strata entry only.
          aliases = [
            "bartowski/Qwen3.8-27B-GGUF:MTP_1P_180K"
            "bartowski/Qwen_Qwen3.6-35B-A3B-GGUF:Q6_K_L"
            "ISTA-DASLab/Qwen3.8-Flash-Next-GSQ-RCO-GGUF:IQ3_S"
            "ISTA-DASLab/Qwen3.8-27B-GSQ-RCO-GGUF:IQ3_S"
          ];
        };
      };

      routing.router = {
        use = "group";
        settings.groups = {
          # both engines want both cards: llama.cpp tensor-splits 17,23 over the
          # 3090 Ti + 5070 Ti, Strata runs gpu [0,1] with layer_split 32
          gpu = {
            swap = true;        # one at a time
            exclusive = true;   # and it evicts every other group
            members = [
              "qwen3.8-flash-next-iq3_s"
              "qwen3.8-flash-next-abliterated-iq3_s"
              "bartowski/Qwen3.8-27B-GGUF:Q8_0"
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

      # keep today's behaviour: Strata is loaded at boot, not on first request
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
      # off - same shape as the llamacpp/strata units below.
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
          # same as the strata unit: an absent host side becomes an empty directory
          # (which sends the entrypoint through a full setup pass) or a directory
          ExecStartPre = [
            "/run/current-system/sw/bin/mkdir -p /home/javi/.config/strata"
            "/run/current-system/sw/bin/touch /home/javi/.config/strata/strata-iq3_s.shared-settings.json"
            "/run/current-system/sw/bin/touch /home/javi/.config/strata/strata-sc117-iq3_s.shared-settings.json"
          ];
        };
      };

      # llama.cpp server: on-demand only (no wantedBy) - llama-swap owns the
      # container now. Manual fallback: starting it while llama-swap runs steals the
      # container and both fight over :8080 and the cards (same :8080 as strata, so
      # the two are mutually exclusive).
      llamacpp = {
        description = "llama.cpp server container";
        serviceConfig = {
          Type = "simple";
          Restart = "on-failure";
          RestartSec = "5s";
          User = "javi";
          Group = "users";
          Environment = [
            "PATH=/run/current-system/sw/bin"
            "CONTAINER_HOST=unix:///run/user/1000/podman/podman.sock"
          ];
        };

        # script = ''
        #   podman run \
        #     --replace \
        #     --name llama-swap-llamacpp \
        #     --pull newer \
        #     --network host \
        #     --device nvidia.com/gpu=all \
        #     -v /home/javi/.cache/huggingface:/root/.cache/huggingface \
        #     -v /home/javi/.config/llamacpp/llama-preset.ini:/app/llama-preset.ini:ro \
        #     ghcr.io/ggml-org/llama.cpp:server-cuda \
        #     --models-preset /app/llama-preset.ini \
        #     --models-max 1 \
        #     -lv 5 \
        #     -t 8 \
        #     -tb 8
        # '';
        script = ''
          # Local build: branch local/mtp-qwen4exp = master @ 6e316de29
          # + patches/mtmd-dflash-mrope-fix.patch (fixes #27408: dflash + mtmd image
          # decoding 500s) + merge of ggml-org/llama.cpp#28243 (qwen4exp MTP draft
          # load + tensor borrow, needed for Qwen3.8-Flash-Next MTP heads).
          # Rebuild via ~/dev/personal/llama.cpp/build-patched.sh <tag>.
          podman run \
            --replace \
            --name llama-swap-llamacpp \
            -p 8080:8080 \
            --device nvidia.com/gpu=all \
            -e GGML_CUDA_ALLREDUCE=internal \
            -e CUDA_VISIBLE_DEVICES=1,0 \
            -v /home/javi/.cache/huggingface:/root/.cache/huggingface \
            -v /home/javi/.config/llamacpp/llama-preset.ini:/app/llama-preset.ini:ro \
            localhost/llama-cuda:mtmd-fix \
            --models-preset /app/llama-preset.ini \
            --models-max 1 \
            -lv 4 \
            -t 8 \
            -tb 8
        '';
      };

      # Strata: Qwen3.8-Flash-Next (125B) on the NVIDIA cards. On-demand only (no
      # wantedBy) - llama-swap preloads it and owns the container; kept as a manual
      # fallback, see the llamacpp unit above. Image from ~/dev/personal/Strata
      # (`docker build -t strata .`); model reused from ~/.cache/huggingface, pack
      # and MTP layer live in the strata-data volume.
      # --network host on purpose: pasta snapshots the namespace subnet from the
      # host routes at container start, so with wlan0 not yet routed it mirrors
      # libvirt's virbr0 192.168.122.0/24 with no default route - the container
      # cannot reply to LAN clients and requests hang until passt resets them
      # (~10 s). Host networking avoids the race; the firewall gates access.
      # The model config lives on the host (~/.config/strata/strata-iq3_s.json)
      # bind-mounted over the volume's /data/config: docker-entrypoint.sh builds
      # $STRATA_DATA/config/strata-<model>.json, so shadowing that one directory
      # keeps the config host-editable and image-independent while strata-data
      # still holds the pack, MTP layer and GGUF links. Mount the directory, not
      # the file: setup.py saves via <name>.tmp + os.replace, and renaming over a
      # bind-mounted file fails with EBUSY (checked with mount --bind).
      # The second mount is the web app's Chat settings: serve/server.py writes
      # them beside the --config path, which is the /opt/strata link rather than
      # the config, so they would land in the container's layer and die on replace.
      # That one is a plain write_text (no rename), but it must exist on the host
      # first or podman creates a directory at the mount point.
      strata = {
        description = "Strata (Qwen3.8-Flash-Next) container";
        unitConfig = {
          # The engine dies on its own sometimes (e.g. a mid-request CUDA OOM kills
          # serve, so `podman run` exits non-zero). Lift the default 5 starts/10 s
          # rate limit so a crash-loop keeps retrying instead of failing the unit.
          StartLimitIntervalSec = 0;
        };
        serviceConfig = {
          Type = "simple";
          # always, not on-failure: the engine also exits 0 after its own
          # watchdog gives up ("the engine stopped unexpectedly (exit code 0)"),
          # which on-failure would leave the service inactive.
          Restart = "always";
          RestartSec = "5s";
          User = "javi";
          Group = "users";
          # Both mounts need their host side to exist as the right kind: an absent
          # directory becomes an empty one (an empty /data/config sends the
          # entrypoint through a full setup pass), an absent file becomes a directory.
          ExecStartPre = [
            "/run/current-system/sw/bin/mkdir -p /home/javi/.config/strata"
            "/run/current-system/sw/bin/touch /home/javi/.config/strata/strata-iq3_s.shared-settings.json"
          ];
          Environment = [
            "PATH=/run/current-system/sw/bin"
            "CONTAINER_HOST=unix:///run/user/1000/podman/podman.sock"
          ];
        };

        script = ''
          podman run \
            --replace \
            --name qwen3.8-flash-next-iq3_s \
            --network host \
            --device nvidia.com/gpu=all \
            --ulimit memlock=-1 \
            -v strata-data:/data \
            -v /home/javi/.config/strata:/data/config \
            -v /home/javi/.config/strata/strata-iq3_s.shared-settings.json:/opt/strata/strata-iq3_s.shared-settings.json \
            -v /home/javi/.cache/huggingface/hub:/hf-cache:ro \
            -e HF_CACHE=/hf-cache \
            -e MODEL=IQ3_S \
            -e VISION=yes \
            localhost/strata:latest
        '';
      };

      # llamacpp-npu = {
      #   description = "llama.cpp server container on Intel NPU (OpenVINO backend)";
      #   wantedBy = [ "multi-user.target" ];
      #   serviceConfig = {
      #     Type = "simple";
      #     Restart = "on-failure";
      #     RestartSec = "5s";
      #     User = "javi";
      #     Group = "users";
      #     Environment = [
      #       "PATH=/run/current-system/sw/bin"
      #       "CONTAINER_HOST=unix:///run/user/1000/podman/podman.sock"
      #     ];
      #   };
      #
      #   script = ''
      #     # llama.cpp with OpenVINO backend (official image), NPU via /dev/accel
      #     # (render group = 303). OpenAI API on :8090 -> container :8080.
      #     podman run \
      #       --replace \
      #       --name llamacpp-npu \
      #       -p 8090:8080 \
      #       --device /dev/accel \
      #       -e GGML_OPENVINO_DEVICE=NPU \
      #       --group-add 303 \
      #       -v /home/javi/.cache/huggingface:/root/.cache/huggingface \
      #       -v /home/javi/.config/llamacpp-npu/llama-preset.ini:/app/llama-preset.ini:ro \
      #       ghcr.io/ggml-org/llama.cpp:server-openvino \
      #       --no-warmup \
      #       --models-preset /app/llama-preset.ini \
      #       --models-max 1 \
      #       -lv 5 \
      #       -t 8 \
      #       -tb 8
      #   '';
      # };

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

      # hermes = {
      #   description = "Hermes Agent container";
      #   wantedBy = [ "default.target" ];
      #   serviceConfig = {
      #     Type = "simple";
      #     Restart = "on-failure";
      #     RestartSec = "5s";
      #     User = "javi";
      #     Group = "users";
      #     Environment = "PATH=/run/current-system/sw/bin";
      #     ExecStartPost = "/bin/sh -c 'sleep 5 && ${config.virtualisation.podman.package}/bin/podman cp /home/javi/.config/hermes/config.yaml hermes:/opt/data/config.yaml && ${config.virtualisation.podman.package}/bin/podman exec hermes chown -R hermes:hermes /opt/data || true'";
      #   };

      #   script = ''
      #     podman run \
      #       --replace \
      #       --name hermes \
      #       -v /home/javi/.local/hermes:/opt/data \
      #       nousresearch/hermes-agent:latest \
      #       gateway run
      #   '';
      # };
    };
  };

  # Environment configuration
  environment.systemPackages = [
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
    # ./greencurve.nix
  ];
}
