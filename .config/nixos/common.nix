{ pkgs, config, lib, ... }:

let unstable = import <nixpkgs-unstable> { config.allowUnfree = true; };
in {
  # {

  boot = {
    loader.systemd-boot.enable = true;
    loader.efi.canTouchEfiVariables = true;
    plymouth.enable = true;
  };

  console.keyMap = "no";

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
    systemPackages = [ pkgs.spice-gtk ];
  };

  hardware = { enableRedistributableFirmware = true; };

  networking = {
    nameservers = ["172.16.99.4"];
    networkmanager = {
      enable = true; # Easiest to use and most distros use this by default.
      dns = "none";
    };
    enableIPv6 = false;
  };

  nix = {
    gc.automatic = true;
    settings = {
      auto-optimise-store = true;
      experimental-features = [ "nix-command" "flakes" ];
      substituters =
        [ "https://nix-community.cachix.org" "https://cache.nixos.org" ];
      trusted-public-keys = [
        "nix-community.cachix.org-1:mB9FSh9qf2dCimDSUo8Zy7bkq5CX+/rkCWyvRCYg3Fs="
      ];
    };
  };

  nixpkgs.config.allowUnfree = true;
  nixpkgs.config.nvidia.acceptLicense = true;

  programs = {
    _1password = { enable = true; };
    _1password-gui = {
      enable = true;
      polkitPolicyOwners = [ "javi" ];
      package = unstable._1password-gui;
    };
    appgate-sdp = { enable = true; };
    appimage = {
      enable = true;
      binfmt = true;
    };
    firefox = {
      enable = true;
      package = unstable.firefox-bin;
    };
    hyprland = {
      enable = true;
      xwayland.enable = true;
      withUWSM = true;
    };
    hyprlock = { enable = true; };
    nix-ld = {
      enable = true;
      libraries = with pkgs; [ stdenv.cc.cc.lib ];
    };
    ssh = { enableAskPassword = false; };
    uwsm = {
      enable = true;
    };
    virt-manager = { enable = true; };
    waybar.enable = true;
    zsh.enable = true;
  };

  security = {
    polkit = {
      enable = true;
      # extraConfig = ''
      #   polkit.addRule(function(action, subject) {
      #     if (
      #       subject.isInGroup("users")
      #         && (
      #           action.id == "org.freedesktop.systemd1.manage-units"
      #         )
      #       )
      #     {
      #       return polkit.Result.YES;
      #     }
      #   });
      # '';
    };
    wrappers = {
      btop = {
        enable = true;
        owner = "root";
        group = "root";
        source = "${pkgs.btop}/bin/btop";
        capabilities = "cap_perfmon=ep";
      };
    };
  };

  services = {
    blueman.enable = true;
    fstrim = { enable = true; };
    gnome.gnome-keyring.enable = true;
    libinput = { enable = true; };
    resolved.enable = false;
  };

  system.stateVersion = "22.11";

  time = {
    hardwareClockInLocalTime = true;
    timeZone = "Europe/Oslo";
  };

  users = {
    users.javi = {
      shell = pkgs.zsh;
      isNormalUser = true;
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
      ];
      packages = with pkgs; [
        apple-cursor
        atop
        autotiling
        baobab # windirstat equivalent
        blueman
        bruno
        btop
        busybox # killall
        ddcutil
        docker-compose
        egl-wayland
        feh
        file-roller
        git
        google-chrome
        hypridle
        hyprpaper
        hyprpolkitagent
        hyprshot
        # nix-du
        pamixer
        pasystray
        pavucontrol
        rofi
        rofimoji
        transmission_4-qt
        unstable.kiro-cli
        unstable.rpi-imager
        slack
        stow
        wl-clipboard
        wtype
        xdg-user-dirs
        xdg-utils
        xfce.thunar
      ];
    };
  };

  virtualisation = {
    containers.enable = true;
    libvirtd = {
      enable = true;
    };
    podman = {
      defaultNetwork = { settings = { dns_enabled = true; }; };
      dockerCompat = true;
      dockerSocket = { enable = true; };
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
