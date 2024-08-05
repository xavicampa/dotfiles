{ config, lib, pkgs, ... }:
let
  stable = import <nixpkgs-stable> { config.allowUnfree = true; };
in

{
  imports =
    [
      # Include the results of the hardware scan.
      ./hardware-configuration.nix
      # ./sentinel.nix
    ];

  nixpkgs.config.allowUnfree = true;

  # Use the systemd-boot EFI boot loader.
  boot.loader.systemd-boot.enable = true;
  boot.loader.efi.canTouchEfiVariables = true;

  # Clean up
  nix.gc.automatic = true;
  nix.settings.auto-optimise-store = true;

  networking.hostName = "homepc"; # Define your hostname.
  # Pick only one of the below networking options.
  # networking.wireless.enable = true;  # Enables wireless support via wpa_supplicant.
  networking.networkmanager.enable = true; # Easiest to use and most distros use this by default.

  # Set your time zone.
  time.timeZone = "Europe/Oslo";

  # List packages installed in system profile. To search, run:
  # $ nix search wget
  # environment.systemPackages = with pkgs; [
  #   linuxKernel.packages.linux_6_1.nvidia_x11_production
  # ];


  # List services that you want to enable:

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
    acceleration = "cuda";
    environmentVariables = { OLLAMA_MAX_LOADED_MODELS = "5"; };
    package = stable.ollama;
  };

  # Enable the OpenSSH daemon.
  # services.openssh.enable = true;

  /* services.kmscon = { */
  /*   enable = true; */
  /* }; */

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

  i18n = {
    defaultLocale = "nb_NO.UTF-8";
    extraLocaleSettings = {
      LC_ALL = "nb_NO.UTF-8";
      LANG = "en_US.UTF-8";
      LANGUAGE = "en_US.UTF-8";
    };
  };

  programs.hyprland = {
    enable = true;
    xwayland.enable = true;
  };

  programs.waybar = {
    enable = true;
  };

  environment.sessionVariables = {
    NIXOS_OZONE_WL = "1";
    ELECTRON_OZONE_PLATFORM_HINT = "auto";
  };

  # Enable the X11 windowing system.
  services.displayManager = {
    # defaultSession = "none+i3";
    defaultSession = "hyprland";
  };

  services.libinput = {
    enable = true;
  };

  services.xserver = {
    enable = true;
    # desktopManager = {
    #   gnome.enable = true;
    # };
    displayManager = {
      gdm.enable = true;
      #     # sessionCommands = ''
      #     #   if test -f ~/.Xmodmap; then
      #     #       ${pkgs.xorg.xmodmap}/bin/xmodmap ~/.Xmodmap
      #     #   fi
      #     # '';
    };
    xkb.layout = "no";
    videoDrivers = [ "nvidia" ];
    windowManager.i3 = {
      enable = true;
      extraPackages = with pkgs; [
        dmenu
        i3status
        i3lock
        i3blocks
      ];
      # package = pkgs.i3-gaps;
    };
  };

  # fonts.fonts = with pkgs; [
  #   nerdfonts
  # ];


  virtualisation.docker.enable = true;

  programs.zsh.enable = true;

  # This seems to make aws amplify work in nixos
  # programs.nix-ld.enable = true;
  programs.nix-ld = {
    enable = true;
  };
  # environment.variables = {
  #   NIX_LD_LIBRARY_PATH = lib.makeLibraryPath [
  #     pkgs.stdenv.cc.cc
  #     pkgs.openssl
  #   ];
  #   NIX_LD = lib.fileContents "${pkgs.stdenv.cc}/nix-support/dynamic-linker";
  # };

  /* programs.thunar.plugins = with pkgs.xfce; [ */
  /*   thunar-archive-plugin */
  /* ]; */

  programs.appgate-sdp = {
    enable = true;
  };

  programs._1password.enable = true;
  programs._1password-gui.enable = true;
  programs.firefox = {
    enable = true;
  };

  users.users.javi = {
    shell = pkgs.zsh;
    isNormalUser = true;
    extraGroups = [ "wheel" "i2c" "docker" "input" ]; # Enable ‘sudo’ for the user.
    packages = with pkgs; [
      autotiling
      blueman
      ddcutil
      discord
      dunst
      egl-wayland
      feh
      file-roller
      flameshot
      git
      google-chrome
      hyprpaper
      hyprshot
      nodejs_18
      pamixer
      pasystray
      pavucontrol
      picom
      postman
      rofi-wayland
      rofimoji
      slack
      spotify
      stow
      vscode
      wl-clipboard
      wofi
      wofi-emoji
      wpaperd
      wtype
      xdg-user-dirs
      xfce.thunar
      xorg.xinput
      xorg.xmodmap
    ];
  };

  xdg.portal = {
    enable = true;
    extraPortals = [
      pkgs.xdg-desktop-portal-gtk
    ];
  };

}
