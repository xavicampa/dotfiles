# Full rationale lives in ./NOTES.md; the § refs below point into it.
{
  config,
  lib,
  pkgs,
  # modulesPath,
  unstable,
  ...
}:

let
  # Disabled BE200 firmware test (force c102 by hiding c103/c106) — NOTES.md § wifi-firmware
  # linuxFirmwareNoC102Newer = pkgs.runCommand "linux-firmware-no-iwlwifi-c103-c106"
  #   { src = pkgs.linux-firmware; } ''
  #   cp -r $src/. $out
  #   chmod -R u+w $out
  #   rm -f $out/lib/firmware/iwlwifi-gl-c0-fm-c0-c106.ucode
  #   rm -f $out/lib/firmware/iwlwifi-gl-c0-fm-c0-c103.ucode
  # '';
in
{
  # Hardware — NOTES.md § hardware
  hardware = {
    bluetooth.enable = true;

    # disabled firmware test, needs the let-binding above — NOTES.md § wifi-firmware
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
      # modesetting.enable = true;

      # VRAM save/restore on suspend, fixes corruption after wake — NOTES.md § hardware
      powerManagement.enable = true;
      powerManagement.finegrained = false; # per-GPU off; Turing+ only
      open = true; # open kernel module (Turing+), not nouveau
      nvidiaSettings = true;

      # kernel + driver must be the same linuxPackages set; CUDA 13 needs unstable — NOTES.md § hardware
      package = unstable.linuxPackages_6_18.nvidiaPackages.latest;
      # package = config.boot.kernelPackages.nvidiaPackages.beta;
      # package = config.boot.kernelPackages.nvidiaPackages.mkDriver {
      #   version = "570.124.04";
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

  # Boot — NOTES.md § boot
  boot = {
    # pci-stub claims the headless NVIDIA HDMI-audio funcs: IRQ 17 storm — NOTES.md § boot
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
      "pci-stub.ids=10de:22e9,10de:1aef" # ids pci-stub claims, initrd + root
    ];
    consoleLogLevel = 3; # hides BIOS AML errors from console — NOTES.md § boot
    kernelPackages = unstable.linuxPackages_6_18; # must match hardware.nvidia.package
    blacklistedKernelModules = [ "spd5118" ];
    # extraModprobeConfig = ''
    #   options nvidia NVreg_PreserveVideoMemoryAllocations=0
    # '';
    kernel.sysctl = {
      "vm.blockdev.readahead" = "2048";
    };
  };

  # memlock for Strata/Maya arenas — NOTES.md § memlock
  security.pam.loginLimits = [
    { domain = "javi"; type = "-"; item = "memlock"; value = "unlimited"; }
  ];
  systemd.user.extraConfig = ''
    DefaultLimitMEMLOCK=infinity
  '';

  # Network — :8080 = llama-swap, backends 5800+ closed — NOTES.md § network
  networking = {
    hostName = "homepc";
    useDHCP = lib.mkDefault true;
    # interfaces.enp3s0.mtu = 9000;
    # wireless.enable = lib.mkForce false;
  };

  nixpkgs.config.cudaSupport = true;
  nixpkgs.hostPlatform = lib.mkDefault "x86_64-linux";

  # ReadyNAS "Media": automount on access, NFSv3 (NAS has no v4) — NOTES.md § readynas
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

  # Unprivileged qemu; searchable $HOME for its images — NOTES.md § libvirt
  virtualisation.libvirtd.qemu.runAsRoot = false;
  users.users.javi.homeMode = "751";

  # cap_perfmon wrapper for btop — NOTES.md § packages
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

  # Desktop shell — homepc-only, unstable pairing — NOTES.md § dms-shell
  programs = {
    dms-shell = {
      enable = true;

      # DMS + quickshell from unstable as a pair; local previewPath patch — NOTES.md § dms-shell
      package = unstable.dms-shell.overrideAttrs (final: prev: {
        postPatch = (prev.postPatch or "") + ''
          # sourceRoot is core/; QML tree one up, fetched tree read-only
          root=..
          [ -f ../quickshell/Modules/Settings/ThemeBrowser.qml ] || root=.
          chmod -R u+w "$root"
          patch -p1 -d "$root" -N --batch < ${./patches/dms-preview-path.patch}
        '';
      });
      quickshell.package = unstable.quickshell;

      # dms.service ships in the package; uwsm provides graphical-session.target
      systemd = {
        enable = true;
        restartIfChanged = true;
      };

      enableSystemMonitoring = true; # dgop: CPU/RAM/net + process list
      enableDynamicTheming = true; # matugen: wallpaper -> DMS/rofi/gtk palette
      enableCalendarEvents = true; # khal widget
      enableClipboardPaste = true; # wtype for Shift+Return
      enableVPN = false; # NetworkManager is inactive here (iwd)
      # enableAudioWavelength: leave at default (true) — NOTES.md § dms-shell
    };

    # 0.56.2 for DMS blur; compositor + portal from unstable as a pair — NOTES.md § hyprland
    hyprland = {
      package = unstable.hyprland;
      portalPackage = unstable.xdg-desktop-portal-hyprland;
    };
  };

  # DMS draws its own bar — NOTES.md § waybar
  systemd.user.services.waybar.wantedBy = lib.mkForce [ ];

  # Services
  services = {
    # DMS greeter replaces sddm here; homepc-only while trialing — NOTES.md § greeter
    displayManager = {
      sddm.enable = lib.mkForce false;

      dms-greeter = {
        enable = true;
        package = unstable.dms-greeter; # 1.6.x ships it separately
        compositor.name = "hyprland";

        # must be LUA (hl.*), hyprlang would stop working in Hyprland 0.57 — NOTES.md § greeter
        compositor.customConfig = ''
          -- cursor from env here: no DMS fragment, no cursor:theme in 0.55; theme from systemPackages
          hl.env("XCURSOR_THEME", "macOS")
          hl.env("XCURSOR_SIZE", "24")
          hl.config({
              input = {
                  kb_layout  = "no",
                  kb_options = "altwin:swap_lalt_lwin",
              },
          })
        '';
        configHome = "/home/javi"; # greeter copies DMS settings/session/colors + wallpapers
      };

      # hyprland-uwsm brings up graphical-session.target that dms.service needs
      defaultSession = "hyprland-uwsm";
    };

    # channel greetd command points at a dms-shell <= 1.4.x path; use bin/dms-greeter — NOTES.md § greeter
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
      # pin wlan0/wlan1 to the card MACs — NOTES.md § udev
      SUBSYSTEM=="net", ACTION=="add", ATTR{address}=="e8:bf:b8:5a:41:55", NAME="wlan0"
      SUBSYSTEM=="net", ACTION=="add", ATTR{address}=="e8:bf:b8:5a:41:56", NAME="wlan1"
      # only pci-stub may ever bind these two HDA functions — NOTES.md § boot
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

  # Disabled 2026-09-24: BE200 throughput collapse after suspend; un-comment if it returns — NOTES.md § wifi-suspend
  # environment.etc."systemd/system-sleep/iwlwifi-reload" = {
  #   source = "${pkgs.writeShellScriptBin "iwlwifi-reload" ''
  #     export PATH=/run/current-system/sw/bin:/run/booted-system/sw/bin:/usr/sbin:/usr/bin:/sbin:/bin
  #     case "$1/$2" in
  #       pre/*)
  #         # BE200 (MLD) registers several wlan* interfaces; down them all
  #         for i in /sys/class/net/wlan*; do
  #           ip link set "$(basename "$i")" down 2>/dev/null
  #         done
  #         modprobe -r iwlmld iwlwifi 2>/dev/null
  #         ;;
  #       post/*) # systemd calls post hooks as "post <sleep-type>"
  #         modprobe iwlmld 2>/dev/null
  #         ;;
  #     esac
  #   ''}/bin/iwlwifi-reload";
  # };

  # llama-swap: :8080 front door, swaps one podman backend per model — NOTES.md § llama-swap
  services.llama-swap = {
    enable = true;
    package = unstable.llama-swap; # >= 225 for `capabilities`
    openFirewall = true; # opens 8080; backends (5800+) stay closed
    listenAddress = "0.0.0.0"; # LAN clients already use homepc:8080
    port = 8080;

    settings = {
      logLevel = "info";
      logToStdout = "both"; # keep engine logs in journald across --replace — NOTES.md § llama-swap
      logTimeFormat = "rfc3339";

      # global (not per-model); must cover Maya's cold load — NOTES.md § llama-swap
      healthCheckTimeout = 900;

      unloadTimeout = 40; # graceful stop of podman run + container
      startPort = 5800; # backends get 5800+
      sendLoadingState = true; # "loading ..." while a swap runs
      includeAliasesInList = true;
      globalTTL = 0; # no timer eviction; the group swaps on demand

      models = {
        # Strata: MODEL_PATH (not HF_CACHE), files bound from HF blobs — NOTES.md § llama-swap/strata
        "qwen3.8-flash-next-iq3_s" = {
          # swap.max=0 keeps the anon arena resident; no comments inside cmd — NOTES.md § llama-swap/strata
          cmd = ''
            podman run --replace --name ''${MODEL_ID}
            --network host
            --device nvidia.com/gpu=all
            --ulimit memlock=-1
            --cgroup-conf memory.swap.max=0
            --shm-size 2g
            --stop-timeout 120
            --pull newer
            -v strata-data:/data
            -v /home/javi/.config/strata/1slot:/data/install
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
            -e STRATA_SPLIT_RING=384
            ghcr.io/niko1221/strata:latest-cuda13
          '';
          cmdStop = ''podman stop -t 120 ''${MODEL_ID}'';
          checkEndpoint = "/health";
          ttl = 0;
          # without this Strata under-reports to capability discovery
          capabilities = {
            context = 262144;
            "in" = [ "text" "image" ];
            out = [ "text" ];
            tools = true;
          };
        };

        # Strata - 3 slots
        "qwen3.8-flash-next-iq3_s-parallel" = {
          # swap.max=0 keeps the anon arena resident; no comments inside cmd — NOTES.md § llama-swap/strata
          cmd = ''
            podman run --replace --name ''${MODEL_ID}
            --network host
            --device nvidia.com/gpu=all
            --ulimit memlock=-1
            --cgroup-conf memory.swap.max=0
            --shm-size 2g
            --stop-timeout 120
            --pull newer
            -v strata-data:/data
            -v /home/javi/.config/strata/3slots:/data/install
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
          # without this Strata under-reports to capability discovery
          capabilities = {
            context = 131072; # the cap here is --max-context 131072 in the 3slots tree, not 256k
            "in" = [ "text" "image" ];
            out = [ "text" ];
            tools = true;
          };
        };

        # Maya: GLM-5.3-Flash MoE, images built locally; model bytes stay in /hf-cache — NOTES.md § llama-swap/maya
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
          cmdStop = ''podman stop -t 35 ''${MODEL_ID}''; # inside unloadTimeout — NOTES.md § llama-swap/maya
          checkEndpoint = "/health";
          ttl = 0;
          # keep context in step with maya.py DEFAULT_CONTEXT / CONTEXT
          capabilities = {
            context = 131072;
            "in" = [ "text" "image" ]; # vision tower on GPU 0
            out = [ "text" ];
            tools = true;
          };
        };

        # llama.cpp PARKED 2026-10-20 (weights gone) — NOTES.md § llama-swap/llamacpp
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
        #   # every name must match a [section] in llama-preset.ini and stay unique
        #   aliases = [
        #     "bartowski/Qwen3.8-27B-GGUF:MTP_1P_180K"
        #     "bartowski/Qwen_Qwen3.6-35B-A3B-GGUF:Q6_K_L"
        #     "ISTA-DASLab/Qwen3.8-Flash-Next-GSQ-RCO-GGUF:IQ3_S"
        #     "ISTA-DASLab/Qwen3.8-27B-GSQ-RCO-GGUF:IQ3_S"
        #   ];
        # };

      };

      # one exclusive group; Strata wants both cards (gpus [0,1], layer_split 32)
      routing.router = {
        use = "group";
        settings.groups = {
          gpu = {
            swap = true; # one at a time
            exclusive = true; # evicts every other group
            members = [
              "qwen3.8-flash-next-iq3_s"
              "qwen3.8-flash-next-iq3_s-parallel"
              "glm-5.3-flash-maya-s24"
              # "bartowski/Qwen3.8-27B-GGUF:Q8_0" # parked
            ];
          };
        };
      };

      # activity -> sqlite; dir from StateDirectory below
      store.path = "/var/lib/llama-swap/activity.sqlite";

      # preload Strata at boot; Maya swaps in on request — NOTES.md § llama-swap
      hooks.on_startup.preload = [ "qwen3.8-flash-next-iq3_s" ];
    };
  };

  # Suspend only; btop wattage; llama-swap unit + sleep guard — NOTES.md § systemd
  systemd = {
    sleep.settings.Sleep = {
      AllowSuspend = true;
      AllowHibernation = false;
      AllowHybridSleep = false;
      AllowSuspendThenHibernate = false;
    };

    tmpfiles.rules = [ "Z /sys/class/powercap/intel-rapl:0/energy_uj 0444 root root - -" ];

    services = {

      # module hardening off: llama-swap must reach javi's rootless podman socket — NOTES.md § systemd
      llama-swap = {
        after = [ "network-online.target" ];
        wants = [ "network-online.target" ];
        serviceConfig = {
          User = "javi";
          Group = "users";
          StateDirectory = "llama-swap"; # holds store.path's activity.sqlite
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
          # host binds must exist as directories, not empty ones — NOTES.md § systemd
          ExecStartPre = [
            "/run/current-system/sw/bin/mkdir -p /home/javi/.config/strata"
            "/run/current-system/sw/bin/mkdir -p /home/javi/.config/maya"
          ];
        };
      };

      # stops llama-swap before NVIDIA suspend, restarts after resume — NOTES.md § systemd
      llamacpp-sleep-guard = {
        description = "Stop the running LLM container before NVIDIA suspend, restart after resume";
        unitConfig = {
          Before = [ "nvidia-suspend.service" "sleep.target" ];
          StopWhenUnneeded = true;
        };
        serviceConfig = {
          Type = "oneshot";
          RemainAfterExit = true;
          Environment = [ "CONTAINER_HOST=unix:///run/user/1000/podman/podman.sock" ];
          # stop the unit, not just the container; bookkeeping needs a script
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

  # apple-cursor moved to common.nix (profile re-hash/dbus restart) — NOTES.md § packages
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
  ];
}
