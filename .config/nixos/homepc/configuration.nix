# House rule: comments here are ONE LINE — what + why, ending with a `— NOTES.md § <topic>`
# pointer. Full rationale, incident history and gotchas belong in ./NOTES.md, not here.
# (Pre-existing multi-line blocks are commented-out code or older entries — don't treat them as the style.)
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

  # engine logs sit in the shared volume under a PRESET key, so the next launch truncates the dead run — NOTES.md § strata-logs
  strataLogDir = "/home/javi/.local/state/strata-logs";

  # copies live engine/server logs + a context snapshot; fingerprint (size:mtime) skips no-ops — NOTES.md § strata-logs
  strataLogArchive = pkgs.writeShellScriptBin "strata-log-archive" ''
    set -u
    VOL=/home/javi/.local/share/containers/storage/volumes/strata-data/_data
    ARC=${strataLogDir}
    TAG=$1
    if [ -z "$TAG" ]; then TAG=launch; fi
    LIVE=$VOL/state/strata/launch/docker.engine.log
    if [ ! -f "$LIVE" ]; then exit 0; fi
    FP=$(stat -c '%s:%Y' "$LIVE" $VOL/state/strata/runtime/launch-docker.server.log 2>/dev/null | paste -sd, -)
    if [ "$FP" = "$(cat $ARC/.fingerprint 2>/dev/null)" ]; then exit 0; fi
    D=$ARC/$(date -u +%Y-%m-%dT%H%M%SZ)-$TAG
    mkdir -p "$D"
    cp -f $VOL/state/strata/launch/*.engine.log "$D/" 2>/dev/null || true
    cp -f $VOL/state/strata/runtime/*.server.log "$D/" 2>/dev/null || true
    cp -f $VOL/state/strata/launch/*.choices.json "$D/" 2>/dev/null || true
    cp -f /home/javi/.config/strata/*/strata-*.log "$D/" 2>/dev/null || true
    { date -u
      echo tag=$TAG
      echo == strata containers ==
      /run/current-system/sw/bin/podman ps -a --format '{{.Names}} {{.Image}} {{.Status}}' 2>/dev/null | grep -iE "strata|maya" || true
      echo == gpus ==
      /run/current-system/sw/bin/nvidia-smi --query-gpu=index,memory.used,memory.free,utilization.gpu,clocks.sm,power.draw,temperature.gpu --format=csv,noheader 2>/dev/null || true
      echo == host load mem PSI ==
      cat /proc/loadavg
      free -m
      cat /proc/pressure/cpu /proc/pressure/memory /proc/pressure/io 2>/dev/null
      echo == kernel warn+ this boot ==
      /run/current-system/sw/bin/journalctl -k -b 0 -p 4 -n 40 --no-pager -o short-iso 2>/dev/null || true
      echo == wedged iGPU error state, lost on reboot ==
      cat /sys/class/drm/card*/error 2>/dev/null | head -20 || true
    } > "$D/context.txt" 2>/dev/null
    echo "$FP" > "$ARC/.fingerprint"
    echo "$(date -u +%FT%TZ) $TAG $D" >> "$ARC/index.txt"
    ls -1d $ARC/*/ 2>/dev/null | grep -v samples | head -n -25 | xargs -r rm -rf
    exit 0
  '';

  # no per-model hooks in v262: archive rides on cmdStop, before podman stop (unloadTimeout < stop wait) — NOTES.md § strata-logs
  strataLogStop = pkgs.writeShellScriptBin "strata-log-stop" ''
    set -u
    ${strataLogArchive}/bin/strata-log-archive "$1"
    /run/current-system/sw/bin/podman stop -t 120 "$1"
  '';

  # 10 s host/GPU/request samples — tells VRAM wall from GPU starvation from clock drops after the fact — NOTES.md § strata-logs
  strataTokSample = pkgs.writeShellScriptBin "strata-toksample" ''
    set -u
    ARC=${strataLogDir}
    mkdir -p "$ARC"
    F=$ARC/samples.csv
    HEAD=ts,load1,mem_avail_mib,swap_used_mib,psi_cpu,psi_mem,psi_io,g0_used_mib,g0_free_mib,g0_util_pct,g0_clk_mhz,g0_w,g1_used_mib,g1_free_mib,g1_util_pct,g1_clk_mhz,g1_w,igpu_card,igpu_rc6_ms,gt0_rc6_ms,gt0_cur_mhz,gt0_act_mhz,gt0_thr,gt1_rc6_ms,gt1_cur_mhz,gt1_act_mhz,gt1_thr,req_id,req_model,req_tps,req_prompt_tps,req_cached,req_draft,req_draft_acc,req_dur_ms,req_code
    if [ ! -f "$F" ] || [ "$(head -n 1 "$F")" != "$HEAD" ]; then
      mv -f "$F" "$ARC/samples-$(date -u +%Y%m%d).csv" 2>/dev/null || true
      echo "$HEAD" > "$F"
    fi
    psi() {
      ${pkgs.gawk}/bin/awk '/some/ { for (i = 1; i <= NF; i++) if (substr($i, 1, 6) == "avg10=") { sub("avg10=", "", $i); print $i; exit } }' /proc/pressure/$1
    }
    # iGPU RC6 residency, invisible to nvidia-smi — NOTES.md § strata-logs; `gt/` marks the i915 card
    rd() { cat "$1" 2>/dev/null | tr -d '\n'; }
    igpu() {
      GT=$(ls -d /sys/class/drm/card*/gt 2>/dev/null | head -1)
      [ -n "$GT" ] || { echo "na,na,na,na,na,na,na,na,na,na"; return; }
      C=$(basename "$(dirname "$GT")")
      for g in gt0 gt1; do
        if [ -d "$GT/$g" ]; then
          set -- "$(rd $GT/$g/rc6_residency_ms)" "$(rd $GT/$g/rps_cur_freq_mhz)" "$(rd $GT/$g/rps_act_freq_mhz)" "$(rd $GT/$g/throttle_reason_status)"
          eval "$g=\$1,$2,$3,$4"
        else
          eval "$g=na,na,na,na"
        fi
      done
      echo "$C,$(rd $(dirname $GT)/power/rc6_residency_ms),$gt0,$gt1"
    }
    while :; do
      if [ "$(stat -c %s "$F" 2>/dev/null || echo 0)" -gt 20000000 ]; then
        mv -f "$F" "$ARC/samples-$(date -u +%Y%m%d-%H%M%S).csv"
        echo "$HEAD" > "$F"
        ls -1 $ARC/samples-*.csv 2>/dev/null | head -n -20 | xargs -r rm -f
      fi
      G=$(/run/current-system/sw/bin/nvidia-smi --query-gpu=memory.used,memory.free,utilization.gpu,clocks.sm,power.draw --format=csv,noheader,nounits 2>/dev/null | paste -sd, - | tr -d ' ')
      A=$(${pkgs.gawk}/bin/awk '/MemAvailable/ { print int($2/1024) }' /proc/meminfo)
      S=$(${pkgs.gawk}/bin/awk '/SwapTotal/ { t = $2 } /SwapFree/ { f = $2 } END { print int((t-f)/1024) }' /proc/meminfo)
      L=$(cut -d' ' -f1 /proc/loadavg)
      R=$(/run/current-system/sw/bin/curl -sf -m 3 http://127.0.0.1:8080/api/metrics/activity 2>/dev/null | ${pkgs.jq}/bin/jq -r '.data[0] | [ (.id//""), (.model//""), (.tokens.tokens_per_second//""), (.tokens.prompt_per_second//""), (.tokens.cache_tokens//""), (.tokens.draft_tokens//""), (.tokens.draft_acc_tokens//""), (.duration_ms//""), (.resp_status_code//"") ] | join(",")' 2>/dev/null)
      [ -n "$R" ] || R=",,,,,,,,"   # keep the 9 req fields present when the engine is down
      I=$(igpu)
      echo "$(date -u +%FT%TZ),$L,$A,$S,$(psi cpu),$(psi memory),$(psi io),$G,$I,$R" >> "$F"
      sleep 10
    done
  '';
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
      # nvidia-smi rc=139 SIGSEGV was patchelf's broken ELF (nixpkgs#576412), fixed by the channel pin:
      # root's nixpkgs-unstable = rev d059931ba096 until dux-shell 2.0.0 builds — NOTES.md § hardware
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
  # Option namespace stays `dms-shell`: the NixOS *module* comes from the nixos-26.05 channel
  # (only packages come from <nixpkgs-unstable>), and 26.05 has no `programs.dux-shell`.
  programs = {
    dms-shell = {
      enable = true;

      # Dux Shell (renamed from dms-shell upstream at 2.0.0) + quickshell from unstable as a
      # pair; two local patches (previewPath, per-registry filter) — NOTES.md § dms-shell
      package = unstable.dux-shell.overrideAttrs (final: prev: {
        postPatch = (prev.postPatch or "") + ''
          # sourceRoot is core/; QML tree one up, fetched tree read-only
          root=..
          [ -f ../quickshell/Modules/Settings/ThemeBrowser.qml ] || root=.
          chmod -R u+w "$root"
          patch -p1 -d "$root" -N --batch < ${./patches/dux-preview-path.patch}
          patch -p1 -d "$root" -N --batch < ${./patches/dux-registry-filter.patch}
        '';
      });
      quickshell.package = unstable.quickshell;

      # dms.service ships in the package; uwsm provides graphical-session.target
      systemd = {
        enable = true;
        restartIfChanged = true;
      };

      enableSystemMonitoring = true; # dgop (26.05 channel pkg): CPU/RAM/net + process list
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
        package = unstable.dux-greeter; # renamed from dms-greeter at 2.0.0; option name is the 26.05 module's
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
          ${lib.getExe unstable.dux-greeter} --cache-dir /var/lib/dms-greeter --command hyprland${
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
    # >= 225 for `capabilities`; local LACT sensor-name patch — NOTES.md § llama-swap/lact-temps
    package = unstable.llama-swap.overrideAttrs (final: prev: {
      postPatch = (prev.postPatch or "") + ''
        chmod -R u+w .
        patch -p1 -N --batch --fuzz=0 < ${./patches/llama-swap-lact-temps.patch}
      '';
      # upstream test flake (v262): log-history vs live-stream race, fails on unpatched 262 too — NOTES.md § llama-swap/lact-temps
      checkFlags = [ "-skip=^TestServer_APILogEvents_NoHistory$" ];
    });
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
          cmdStop = ''${strataLogStop}/bin/strata-log-stop ''${MODEL_ID}'';
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

        # Strata - batch engine (only batched tree now; the 3slots fork was removed 2026-10-26 —
        # restore recipe in parallel/TUNING_NOTES.md § Removed: 3slots). Renamed 2026-10-27: tree
        # 5slot/ -> parallel/, key -parallel5 -> -parallel; the slot count is out of the name
        # because -e PARALLEL below is what sets it.
        # Serving knobs and where they live — NOTES.md § llama-swap/strata-parallel:
        # slots = -e PARALLEL below (env beats the preset and is written back into it); the
        # queue bound has no launch flag/env, so max_queue + queue_timeout sit as top-level
        # keys in ~/.config/strata/parallel/strata-iq3_s.json, which derive_config copies.
        # Context cap (98304 since 2026-10-27) is NOT an env knob here: the number the engine obeys is
        # --max-context in the preset extra + the run config, "context" below only carries the reuse test, and
        # capabilities.context below is what gets advertised - keep them and pi's contextWindow in step.
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
            -v /home/javi/.config/strata/parallel:/data/install
            -v /home/javi/.cache/huggingface/hub/models--ISTA-DASLab--Qwen3.8-Flash-Next-GSQ-RCO-GGUF/blobs/4c1eb2ceb4915e1192f4f386021897bde56a97f40a0bb78bb86465e0f7d2aca3:/data/gguf/IQ3_S/Qwen3.8-Flash-Next-GSQ-RCO-IQ3_S-00001-of-00002.gguf:ro
            -v /home/javi/.cache/huggingface/hub/models--ISTA-DASLab--Qwen3.8-Flash-Next-GSQ-RCO-GGUF/blobs/316b46f3a2dbd68c900f43136ab9449f9dcc3725dfd8c794847c204bc161e113:/data/gguf/IQ3_S/Qwen3.8-Flash-Next-GSQ-RCO-IQ3_S-00002-of-00002.gguf:ro
            -v /home/javi/.cache/huggingface/hub/models--ISTA-DASLab--Qwen3.8-Flash-Next-GSQ-RCO-GGUF/blobs/b1a82259702816a5330d7bd7607cd9676b11780e79ff7348c21103ff3ce49bd0:/data/gguf/IQ3_S/mmproj-Qwen3.8-Flash-Next-BF16.gguf:ro
            -e XDG_CONFIG_HOME=/data/install
            -e MODEL_PATH=/data/gguf/IQ3_S
            -e MODEL=IQ3_S
            -e PARALLEL=4
            -e PORT=''${PORT}
            -e STRATA_PF_FUSED=1
            -e STRATA_ADAPT_LAG=2
            -e STRATA_EXCHANGE_ROTATE=1
            -e STRATA_SPLIT_RING=384
            ghcr.io/niko1221/strata:latest-cuda13
          '';
          cmdStop = ''${strataLogStop}/bin/strata-log-stop ''${MODEL_ID}'';
          checkEndpoint = "/health";
          ttl = 0;
          # without this Strata under-reports to capability discovery
          capabilities = {
            # llama-swap advertises this as context_window / n_ctx to clients, so it must equal the engine's
            # --max-context in the parallel tree (98304 since 2026-10-27 ~15:10, and Pi's
            # modelOverrides[...].contextWindow in ~/.pi/agent/models.json). Cap rationale:
            # ~/.config/strata/parallel/TUNING_NOTES.md § the RAM wall.
            context = 98304;
            "in" = [ "text" "image" ];
            out = [ "text" ];
            tools = true;
          };
        };

        # Strata: Qwen3.8-Flash-Next Coder (expert-pruned), 3-slot batch on 5801 — NOTES.md § llama-swap/strata-coder
        # (kv k8v4 + 3 slots: coder/TUNING_NOTES.md § 4-slot load / KV tier)
        "qwen3.8-flash-next-coder-iq1_m-parallel" = {
          # FAMILY+MODEL are family+size, not a path; the blob mounts use fam["file"] verbatim;
          # the /nix/store mount gives the image's nvidia-smi its loader — NOTES.md § llama-swap/strata-coder.
          # Tuning (layer-split, kv-resident, conversation cache) lives in the mounted preset and
          # ~/.config/strata/coder/TUNING_NOTES.md, never here. Engine placement has no preset path either
          # (the run config carries args/user_args/vision only — no env layer), and STRATA_MTP_STAGE0=1 measured
          # inert under --batch: see coder/TUNING_NOTES.md § CUDA1 headroom, so nobody re-adds it.
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
            -v /nix/store:/nix/store:ro
            -v /home/javi/.config/strata/coder:/data/install
            -v /home/javi/.cache/huggingface/hub/models--ISTA-DASLab--Qwen3.8-Flash-Next-GSQ-RCO-Coder-GGUF/blobs/bfa3644db4adfff072fc946c20994f2909d2cf89879d83f80a4c811d4016c211:/data/gguf/coder-IQ1_M/Qwen3.8-Flash-Next-GSQ-RCO-IQ1_M-00001-of-00002.gguf:ro
            -v /home/javi/.cache/huggingface/hub/models--ISTA-DASLab--Qwen3.8-Flash-Next-GSQ-RCO-Coder-GGUF/blobs/316b46f3a2dbd68c900f43136ab9449f9dcc3725dfd8c794847c204bc161e113:/data/gguf/coder-IQ1_M/Qwen3.8-Flash-Next-GSQ-RCO-IQ1_M-00002-of-00002.gguf:ro
            -v /home/javi/.cache/huggingface/hub/models--ISTA-DASLab--Qwen3.8-Flash-Next-GSQ-RCO-Coder-GGUF/blobs/b1a82259702816a5330d7bd7607cd9676b11780e79ff7348c21103ff3ce49bd0:/data/gguf/coder-IQ1_M/mmproj-Qwen3.8-Flash-Next-BF16.gguf:ro
            -e XDG_CONFIG_HOME=/data/install
            -e MODEL_PATH=/data/gguf/coder-IQ1_M
            -e MODEL=IQ1_M
            -e FAMILY=coder
            -e PARALLEL=3
            -e PORT=''${PORT}
            -e STRATA_PF_FUSED=1
            -e STRATA_ADAPT_LAG=2
            -e STRATA_EXCHANGE_ROTATE=1
            -e STRATA_SPLIT_RING=384
            ghcr.io/niko1221/strata:latest-cuda13
          '';
          cmdStop = ''${strataLogStop}/bin/strata-log-stop ''${MODEL_ID}'';
          checkEndpoint = "/health";
          ttl = 0;
          # so clients that name the HF repo get this backend (includeAliasesInList is on)
          aliases = [ "ISTA-DASLab/Qwen3.8-Flash-Next-GSQ-RCO-Coder-GGUF:IQ1_M" ];
          capabilities = {
            # must equal the preset's --max-context (131072, not the parallel tree's 98304) + Pi contextWindow — NOTES.md § llama-swap/strata-coder
            context = 131072;
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
              "qwen3.8-flash-next-coder-iq1_m-parallel"
              "glm-5.3-flash-maya-s24"
              # "bartowski/Qwen3.8-27B-GGUF:Q8_0" # parked
            ];
          };
        };
      };

      # activity -> sqlite; dir from StateDirectory below
      store.path = "/var/lib/llama-swap/activity.sqlite";

      # preload = the boot default (no default_model key in v262); keep it on the model that serves — NOTES.md § llama-swap
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
          # 1st entry archives the previous engine run before the preload truncates it — NOTES.md § strata-logs
          ExecStartPre = [
            "-${strataLogArchive}/bin/strata-log-archive boot"
            "/run/current-system/sw/bin/mkdir -p /home/javi/.config/strata"
            "/run/current-system/sw/bin/mkdir -p /home/javi/.config/maya"
          ];
        };
      };

      # 10 s GPU/RAM/PSI + llama-swap samples, appended to strataLogDir/samples.csv — NOTES.md § strata-logs
      strata-toksample = {
        description = "Timestamped GPU/RAM/PSI + llama-swap samples for post-incident triage";
        after = [ "network-online.target" ];
        wants = [ "network-online.target" ];
        wantedBy = [ "multi-user.target" ];
        serviceConfig = {
          ExecStart = "${strataTokSample}/bin/strata-toksample";
          User = "javi";
          Group = "users";
          Restart = "always";
          RestartSec = 10;
          StandardOutput = "null"; # the loop is the point; keep it out of journald
          StandardError = "journal";
        };
      };

      # LACT writes the i915 clock files on every reload; detach the iGPU so it never can (per-start) — NOTES.md § lact
      lactd = {
        serviceConfig.ExecStartPost = pkgs.writeShellScript "lact-detach-igpu" ''
          sleep 3
          ${config.services.lact.package}/bin/lact cli --gpu-id=8086:7D67-1849:7D67-0000:00:02.0 detach || true
        '';
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
    # post-incident triage: activity.sqlite holds per-request tok/s/drafts (survives reboots)
    # and the sampler's CSV needs jq — NOTES.md § strata-logs
    pkgs.sqlite
    pkgs.jq
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
