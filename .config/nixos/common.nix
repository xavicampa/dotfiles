{ pkgs, config, ... }:

# let unstable = import <nixpkgs-unstable> { config.allowUnfree = true; };

# in {
  # imports =
  #   [
  #     # Include the results of the hardware scan.
  #     ./hardware-configuration.nix
  #     # ./sentinel.nix
  #   ];

{
  nixpkgs.config.allowUnfree = true;

  # Use the systemd-boot EFI boot loader.
  boot.loader.systemd-boot.enable = true;
  boot.loader.efi.canTouchEfiVariables = true;

  # Store optimize and garbage clean up
  nix.gc.automatic = true;
  nix.optimise.automatic = true;
  nix.settings = {
    auto-optimise-store = false;
    substituters = [ "https://nix-community.cachix.org" ];
    trusted-public-keys = [
      "nix-community.cachix.org-1:mB9FSh9qf2dCimDSUo8Zy7bkq5CX+/rkCWyvRCYg3Fs="
    ];
  };

  networking.networkmanager.enable = true; # Easiest to use and most distros use this by default.
  networking.enableIPv6 = false;

  # Set your time zone.
  time = {
    hardwareClockInLocalTime = true;
    timeZone = "Europe/Oslo";
  };

  # bluetooth
  services.blueman.enable = true;

  # nixpkgs.overlays =
  #   [
  #     (self: super:
  #       {
  #         ollama = super.ollama.overrideAttrs (old: {
  #           src = super.fetchFromGitHub {
  #             owner = "ollama";
  #             repo = "ollama";
  #             rev = "v0.3.1";
  #             hash = "sha256-ctz9xh1wisG0YUxglygKHIvU9bMgMLkGqDoknb8qSAU=";
  #             fetchSubmodules = true;
  #           };
  #         });
  #       })
  #   ];

  # ollama
  services.ollama = {
    enable = true;
    environmentVariables = {
      OLLAMA_DEBUG = "1";
      OLLAMA_FLASH_ATTENTION = "1";
      OLLAMA_KV_CACHE_TYPE = "q8_0";
    };
    host = "0.0.0.0";
    openFirewall = true;
    # package = unstable.ollama;
  };

  # keyring
  services.gnome.gnome-keyring.enable = true;

  # services.kmscon = {
  # enable = true;
  # };

  # Open ports in the firewall.
  # networking.firewall.allowedTCPPorts = [ ... ];
  # networking.firewall.allowedUDPPorts = [ ... ];
  # Or disable the firewall altogether.
  # networking.firewall.enable = false;

  # Copy the NixOS configuration file and link it from the resulting system
  # (/run/current-system/configuration.nix). This is useful in case you
  # accidentally delete configuration.nix.
  # system.copySystemConfiguration = true;

  # This value determines the NixOS release from which the default
  # settings for stateful data, like file locations and database versions
  # on your system were taken. It‘s perfectly fine and recommended to leave
  # this value at the release version of the first install of this system.
  # Before changing this value read the documentation for this option
  # (e.g. man configuration.nix or on https://nixos.org/nixos/options.html).
  system.stateVersion = "22.11"; # Did you read the comment?

  # Auto-upgrade (not sure how it works, disabling for now)
  # system.autoUpgrade = {
  #   enable = true;
  #   allowReboot = false;
  # };

  # environment.systemPackages = with pkgs; [
  #   hyprland
  #   swww # for wallpapers
  #   xdg-desktop-portal-gtk
  #   xdg-desktop-portal-hyprland
  #   xwayland
  # ];  

  # javi home section
  #
  environment.etc."rofi/themes".source = "${pkgs.rofi}/share/rofi/themes";
  environment.etc."hypr/hypr.conf".source =
    "${config.users.users.javi.home}/.config/hypr/${config.networking.hostName}.conf";
  environment.etc."waybar/config.jsonc".source =
    "${config.users.users.javi.home}/.config/waybar/${config.networking.hostName}.jsonc";

  i18n = {
    defaultLocale = "nb_NO.UTF-8";
    extraLocaleSettings = {
      LC_ALL = "nb_NO.UTF-8";
      LANG = "en_US.UTF-8";
      LANGUAGE = "en_US.UTF-8";
    };
  };

  # programs.regreet.enable = true;
  services.xserver = {
    # displayManager = { gdm.enable = true; };
    xkb.layout = "no";
  };

  programs.hyprland = {
    enable = true;
    xwayland.enable = true;
    withUWSM = true;
  };

  programs.hyprlock = { enable = true; };

  programs.ssh = { enableAskPassword = false; };

  environment.sessionVariables = {
    NIXOS_OZONE_WL = "1";
    ELECTRON_OZONE_PLATFORM_HINT = "auto";
    GIT_ASKPASS = "";
  };

  services.libinput = { enable = true; };

  # virtualisation.docker.enable = true;
  virtualisation = {
    containers.enable = true;
    podman = {
      defaultNetwork = { settings = { dns_enabled = true; }; };
      dockerCompat = true;
      dockerSocket = { enable = true; };
      enable = true;
    };
  };

  programs.zsh.enable = true;

  # This seems to make aws amplify work in nixos
  # programs.nix-ld.enable = true;
  programs.nix-ld = {
    enable = true;
    libraries = with pkgs; [ stdenv.cc.cc.lib ];
  };
  # environment.variables = {
  #   NIX_LD_LIBRARY_PATH = lib.makeLibraryPath [
  #     pkgs.stdenv.cc.cc
  #     pkgs.openssl
  #   ];
  #   NIX_LD = lib.fileContents "${pkgs.stdenv.cc}/nix-support/dynamic-linker";
  # };

  # programs.thunar.plugins = with pkgs.xfce; [
  # thunar-archive-plugin
  # ];

  programs.appgate-sdp = { enable = true; };

  programs._1password-gui = {
    enable = true;
    # package = unstable._1password-gui;
  };

  programs.firefox = {
    enable = true;
    package = pkgs.firefox-bin;
  };

  programs.waybar.enable = true;

  users.users.javi = {
    shell = pkgs.zsh;
    isNormalUser = true;
    extraGroups =
      [ "wheel" "i2c" "input" "podman" "video" ]; # Enable ‘sudo’ for the user.
    packages = with pkgs; [
      apple-cursor
      autotiling
      baobab  # windirstat equivalent
      blueman
      bruno
      busybox # killall
      # cachix
      ddcutil
      docker-compose
      egl-wayland
      feh
      # unstable.file-roller
      file-roller
      git
      google-chrome
      hypridle
      hyprpaper
      hyprshot
      # nodejs_18
      nix-du
      pamixer
      pasystray
      pavucontrol
      # rofi-wayland
      rofi
      rofimoji
      slack
      stow
      # vscode
      wl-clipboard
      wtype
      xdg-user-dirs
      xdg-utils
      xfce.thunar
      # waybar
    ];
  };

  xdg.portal = {
    enable = true;
    extraPortals = [ pkgs.xdg-desktop-portal-gtk ];
    wlr.enable = true;
  };

}
