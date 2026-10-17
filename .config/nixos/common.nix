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
    firefox = {
      enable = true;
      package = pkgs.firefox-bin;
    };
    hyprland = {
      enable = true;
      xwayland.enable = true;
      withUWSM = true;
    };
    hyprlock = {
      enable = true;
    };
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

  security.polkit.enable = true;

  services = {
    blueman.enable = true;
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
    hypridle = {
      enable = true;
    };
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
        blueman
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
        pasystray
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
