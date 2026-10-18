{
  pkgs,
  config,
  lib,
  ...
}:

let
  unstable = import <nixpkgs-unstable> {
    config.allowUnfree = true;
    # overlays = import /home/javi/.config/nixpkgs/overlays_unstable.nix;
  };
in
{
  _module.args = { inherit unstable; };

  boot = {
    loader.systemd-boot.enable = true;
    loader.efi.canTouchEfiVariables = true;
    plymouth.enable = true;
  };

  # TTY keymap derives from services.xserver.xkb below (layout + options), so the
  # Alt<->Win swap applies on the console too. console.keyMap would be ignored
  # once useXkbConfig is on, hence it is gone rather than left as a decoy.
  console.useXkbConfig = true;

  # Norwegian formats/collation, English app messages (LC_MESSAGES override is the
  # documented NixOS pattern for keeping UI strings in English).
  i18n = {
    defaultLocale = "nb_NO.UTF-8";
    extraLocaleSettings.LC_MESSAGES = "en_US.UTF-8";
  };

  environment = {
    etc."rofi/themes".source = "${pkgs.rofi}/share/rofi/themes";
    etc."hypr/hypr.conf".source =
      "${config.users.users.javi.home}/.config/hypr/${config.networking.hostName}.conf";
    etc."waybar/config.jsonc".source =
      "${config.users.users.javi.home}/.config/waybar/${config.networking.hostName}.jsonc";
    sessionVariables = {
      NIXOS_OZONE_WL = "1";
      ELECTRON_OZONE_PLATFORM_HINT = "auto";
      GIT_ASKPASS = "";
    };
    systemPackages = [
      pkgs.dig
      pkgs.efibootmgr
      pkgs.gedit
      pkgs.gftp
      pkgs.spice-gtk
      pkgs.librepods
      pkgs.lsof
      pkgs.nautilus
      (pkgs.catppuccin-sddm.override {
        flavor = "mocha";
        accent = "mauve";
      })
      # Login-screen cursor. The dms-greeter serviceAccount has no per-user
      # profile (/etc/profiles/per-user/ only contains javi), and apple-cursor is
      # otherwise only in users.users.javi.packages, so the greeter's Hyprland
      # cannot resolve the theme at all. In the system profile it lands in
      # /run/current-system/sw/share/icons/macOS, which every XCURSOR_PATH
      # includes. Keep in sync with users.users.javi.packages (apple-cursor),
      # DMS's cursorSettings (macOS/24) and the greeter's customConfig env.
      pkgs.apple-cursor
      pkgs.unrar
    ];
  };

  hardware = {
    enableRedistributableFirmware = true;
  };

  networking = {
    # nameservers = [ "172.16.99.1" ];
    enableIPv6 = false;
    useDHCP = true;
    wireless = {
      enable = false;
      iwd = {
        enable = true;
      };
    };
    resolvconf = {
      useLocalResolver = false;
    };
  };

  nix = {
    gc.automatic = true;
    settings = {
      auto-optimise-store = true;
      experimental-features = [
        "nix-command"
        "flakes"
      ];
      substituters = [
        "https://nix-community.cachix.org"
        "https://cache.nixos.org"
      ];
      trusted-public-keys = [
        "nix-community.cachix.org-1:mB9FSh9qf2dCimDSUo8Zy7bkq5CX+/rkCWyvRCYg3Fs="
      ];
    };
  };

  nixpkgs.config.allowUnfree = true;
  nixpkgs.config.nvidia.acceptLicense = true;

  programs = {
    _1password = {
      enable = true;
      package = unstable._1password-cli;
    };
    _1password-gui = {
      enable = true;
      polkitPolicyOwners = [ "javi" ];
      package = unstable._1password-gui;
    };
    appgate-sdp = {
      enable = true;
    };
    appimage = {
      enable = true;
      binfmt = true;
    };
    dconf = {
      enable = true;
      profiles = {
        user.databases = [
          {
            settings = {
              "org/gnome/desktop/interface" = {
                gtk-enable-primary-paste = true;
                color-scheme = "prefer-dark";
              };
            };
          }
        ];
      };
    };
    dms-shell = {
      # DankMaterialShell - quickshell-based desktop shell (bar, notifications,
      # launcher, lock screen, OSD) for the hyprland session. Trial config; the
      # shell's own settings live imperatively in ~/.config/quickshell/ii/ and
      # ~/.config/hypr (deployed by `dms setup`), only the package/service here.
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
      # cava spectrum widget - flip to true if you want the visualizer.
      enableAudioWavelength = false;
    };

    firefox = {
      enable = true;
      package = pkgs.firefox-bin;
    };
    hyprland = {
      enable = true;
      xwayland.enable = true;
      withUWSM = true;
    };
    # hyprlock dropped: DMS owns the lock screen (Settings -> Power & Security
    # -> Lock Screen; `dms ipc call lock lock`, SUPER+ALT+L). It authenticates
    # through PAM - on NixOS DMS resolves a sanitized password-only stack into
    # ~/.local/state/DankMaterialShell/pam/dankshell (see `dms auth list-services`).
    # Re-add `programs.hyprlock.enable = true;` to go back.
    nix-ld = {
      enable = true;
      libraries = with pkgs; [ stdenv.cc.cc.lib ];
    };
    quark-goldleaf.enable = true;
    ssh = {
      enableAskPassword = false;
    };
    virt-manager = {
      enable = true;
    };
    uwsm.enable = true;
    waybar = {
      enable = true;
    };
    zsh.enable = true;
  };

  # DMS draws its own bar, so drop the waybar module's WantedBy instead of
  # disabling programs.waybar - the package and ~/.config/waybar/${host}.jsonc
  # stay, and deleting this line brings the bar straight back.
  systemd.user.services.waybar.wantedBy = lib.mkForce [ ];

  security.polkit.enable = true;

  services = {
    displayManager = {
      sddm = {
        enable = true;
        theme = "catppuccin-mocha-mauve";
        wayland.enable = true;
      };
    };
    # Writes /etc/X11/xorg.conf.d/00-keyboard.conf, which systemd-localed reads -
    # this is what DMS's "system" keyboard setting reports. Hyprland does NOT read
    # it; that needs input:kb_layout/kb_options in ~/.config/hypr/hyprland.lua.
    xserver.xkb = {
      layout = "no";
      # Left Alt <-> Left Win, so DMS's SUPER binds fire on the physical Alt key and
      # app Alt+Tab / Alt+PgDn move to the physical Win key.
      options = "terminate:ctrl_alt_bksp,altwin:swap_lalt_lwin";
    };
    fstrim = {
      enable = true;
    };
    gnome.gnome-keyring.enable = true;
    gvfs.enable = true;
    libinput = {
      enable = true;
    };
    # hypridle dropped: DMS's IdleService (Quickshell IdleMonitor) does the same
    # job with AC/battery split timeouts, honours the idle-inhibitor tile, and
    # reacts to `loginctl lock-session` (loginctlLockIntegration). Timeouts live
    # imperatively in ~/.config/DankMaterialShell/settings.json - this box runs
    # acLockTimeout=300 + acPostLockMonitorTimeout=300, monitor/suspend off.
    # Re-add `services.hypridle.enable = true;` (plus ~/.config/hypr/legacy/
    # hypridle.conf, where the Lua migration parked it) to go back.
    udisks2.enable = true;
  };

  system.stateVersion = "22.11";

  time = {
    timeZone = "Europe/Oslo";
  };

  users = {
    groups.plugdev = { };

    users.javi = {
      shell = pkgs.zsh;
      isNormalUser = true;
      linger = true;
      extraGroups = [
        "wheel"
        "i2c"
        "input"
        "podman"
        "video"
        "networkmanager"
        "render"
        "seat"
        "audio"
        "users"
        "disk"
        "libvirtd"
        "plugdev"
      ];
      packages = with pkgs; [
        apple-cursor
        atop
        autotiling
        baobab # windirstat equivalent
        bashmount
        bruno
        unstable.btop-cuda
        ddcutil
        docker-compose
        egl-wayland
        feh
        file-roller
        git
        google-chrome
        hyprpaper
        hyprshot
        # nix-du
        pamixer
        # pasystray
        pavucontrol
        psmisc
        rofi
        rofimoji
        transmission_4-gtk
        unstable.kiro-cli
        unstable.rpi-imager
        unstable.telegram-desktop
        slack
        stow
        wl-clipboard
        wtype
        xdg-user-dirs
        xdg-utils
        # pkgs.thunar
      ];
    };
  };

  virtualisation = {
    containers.enable = true;
    libvirtd = {
      enable = true;
    };
    podman = {
      defaultNetwork = {
        settings = {
          dns_enabled = true;
        };
      };
      dockerCompat = true;
      dockerSocket = {
        enable = true;
      };
      enable = true;
    };
    spiceUSBRedirection.enable = true;
  };

  xdg.portal = {
    enable = true;
    extraPortals = [ pkgs.xdg-desktop-portal-gtk ];
    wlr.enable = true;
  };
}
