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
    # rofi themes = dell only. The dell's menus ARE rofi (hosts/dell.lua:113-117: SUPER+Space
    # drun, SUPER+Tab, SUPER+X powermenu.sh, SUPER+SHIFT+P displaymenu_dell.sh); homepc's are
    # DMS (dms/binds.lua: SUPER+space spotlight, ALT+space spotlight-bar, SUPER+X powermenu).
    # Nothing on either host actually reads this file — ~/.config/rofi/config.rasi is
    # self-contained (no @import, colors inlined) — it only feeds `rofi-theme-selector`.
    # The gate matters on its own: an environment.etc entry drags its `source` derivation into
    # the system closure, so gating only the user package would keep pkgs.rofi on homepc anyway.
    etc."rofi/themes" = lib.mkIf (config.networking.hostName == "dell") {
      source = "${pkgs.rofi}/share/rofi/themes";
    };
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
      pkgs.discord
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
    ] ++ lib.optionals (config.networking.hostName == "homepc") [
      # The dms-greeter's login-screen cursor — homepc only, but kept inline here
      # rather than moved to homepc/configuration.nix. A package changing *position*
      # in the merged environment.systemPackages order re-hashes the system-path
      # buildEnv (byte-identical contents, different derivation), and that path is
      # baked into /etc/dbus-1/{session,system}.conf plus the polkit and dbus-broker
      # X-Restart-Triggers — so relocating it would restart the system bus for
      # nothing. Same list, same slot, just absent on the dell.
      pkgs.apple-cursor
    ] ++ [
      pkgs.unrar
      # The `adw-gtk3`/`adw-gtk3-dark` pair DMS's own `scripts/gtk.sh` copies into
      # ~/.local/share/themes (with a .dms-copy src+sha256 marker) and what
      # Common/Theme.qml `refreshGtkTheme` then selects per mode as `gtk-theme` —
      # Chromium and GTK3 apps latch on that key. With no system copy of the theme
      # (both $XDG_DATA_DIRS share/themes roots empty) `gtk.sh patch` exits 2, i.e.
      # *nothing patched*, the select never runs, and those apps keep their own looks
      # however the shell's mode flips. Appended dead last, not reordered into the
      # main list: the system-path re-hash warning above.
      pkgs.adw-gtk3
    ];
  };

  hardware = {
    enableRedistributableFirmware = true;
  };

  networking = {
    # nameservers = [ "172.16.99.1" ];
    enableIPv6 = false;
    # mkDefault so a host that enables NetworkManager (homepc) can win: the NM module
    # assigns `useDHCP = false` at normal priority, and an explicit `true` here would
    # clash with it (homepc NOTES.md § network-manager).
    useDHCP = lib.mkDefault true;
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
    # DMS (DankMaterialShell) is deliberately NOT declared here. The shell takes
    # over the bar, notifications, lock screen and idle handling, so enabling it
    # for every host would clash with waybar/dunst/hypridle/hyprlock on the dell.
    # It lives in homepc/configuration.nix, next to the dms-greeter that replaced
    # sddm there.

    firefox = {
      enable = true;
      package = pkgs.firefox-bin;
    };
    hyprland = {
      enable = true;
      xwayland.enable = true;
      withUWSM = true;
    };
    # No screen locker in the shared config on purpose: homepc lets DMS own the
    # lock screen (Settings -> Power & Security -> Lock Screen; `dms ipc call lock
    # lock`, SUPER+ALT+L; it authenticates through a PAM stack DMS resolves into
    # ~/.local/state/DankMaterialShell/pam/dankshell, see `dms auth list-services`),
    # and the dell re-enables `programs.hyprlock.enable = true;` in its own file.
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

  # programs.waybar stays enabled for every host; homepc drops the unit's
  # WantedBy in its own file because DMS draws its own bar there.

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
    # No idle daemon in the shared config on purpose: homepc lets DMS's
    # IdleService (Quickshell IdleMonitor) do the job - AC/battery split
    # timeouts, idle-inhibitor tile, `loginctl lock-session` integration, with
    # the timeouts in ~/.config/DankMaterialShell/settings.json (acLockTimeout=300
    # + acPostLockMonitorTimeout=300) - and the dell re-enables
    # `services.hypridle.enable = true;` in its own file. Configs: ~/.config/hypr/hypridle.conf
    # and ~/.config/hypr/hyprlock.conf (shared dotfiles, never read on homepc because
    # neither binary is installed there). legacy/hypridle.conf came back with them.
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
        # nix-du
        pamixer
        # pasystray
        pavucontrol
        psmisc
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
      ] ++ lib.optionals (config.networking.hostName == "dell") [
        # hyprshot = dell only. Nothing on homepc calls it: its only keybinds are
        # SUPER+SHIFT+4/5 in ~/.config/hypr/hosts/dell.lua, and homepc screenshots
        # go through DMS (Print -> `dms screenshot`, its own wlr-screencopy in
        # core/internal/screenshot, hyprctl only for geometry). Worth dropping on
        # homepc because hyprshot depends on the *channel* hyprland for hyprctl, so
        # it kept hyprland-0.55.4 in a closure that now runs 0.56.2. Kept inline +
        # hostName-gated rather than moved to dell/configuration.nix (see the
        # apple-cursor note above for why position churn matters).
        hyprshot
        # rofi + rofimoji = dell only. Both were shared from the pre-DMS hyprlang days, when
        # rofi was the launcher on every box; homepc has had no rofi caller since the DMS
        # migration. Rofi: every caller lives in hosts/dell.lua (drun / window menu / powermenu
        # / display menu), and homepc's equivalents are DMS IPC — SUPER+space spotlight,
        # ALT+space spotlight-bar, SUPER+X powermenu, SUPER+CTRL+Space emojiPicker. The old
        # "matugen themes rofi" note at homepc/configuration.nix:298 never held: no .rasi
        # template exists in ~/.config/matugen/templates or in DMS's matugen templates. Rofimoji:
        # its only remaining caller is that file's SUPER+CTRL+Space, and the dell has no DMS to
        # replace it (homepc now runs DMS's own emojiPicker plugin — see the "Emoji picker — DMS
        # plugin, not rofimoji" section of ~/.config/hypr/keybinds.md). Closures are heavy for
        # two binaries nothing here launches: rofi-2.0.0 ~309 MiB, rofimoji-6.7.0 ~365 MiB
        # (wrapped python + emoji data). Only their bin symlinks were on PATH; the python3 on
        # PATH is from ~/.nix-profile, untouched. The ~/.config/rofi scripts + gruvbox .rasi
        # files stay in dotfiles — they are the dell's, and the repo is shared.
        rofi
        rofimoji
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
