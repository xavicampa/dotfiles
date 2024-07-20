{ config, lib, pkgs, ... }:

{
  imports =
    [
      # Include the results of the hardware scan.
      ./hardware-configuration.nix
      # ./sentinel.nix
    ];

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

  # bluetooth
  services.blueman.enable = true;

  # List packages installed in system profile. To search, run:
  # $ nix search wget
  # environment.systemPackages = with pkgs; [
  #   linuxKernel.packages.linux_6_1.nvidia_x11_production
  # ];


  # List services that you want to enable:

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

  nixpkgs.config = {
    allowUnfree = true;
  };

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

  users.users.javi = {
    shell = pkgs.zsh;
    isNormalUser = true;
    extraGroups = [ "wheel" "i2c" "docker" ]; # Enable ‘sudo’ for the user.
    packages = with pkgs; [
      _1password
      _1password-gui
      autotiling
      blueman
      copyq
      ddcutil
      discord
      dunst
      egl-wayland
      feh
      file-roller
      firefox-esr
      flameshot
      git
      google-chrome
      nodejs_18
      # (ollama.override { acceleration = "cuda"; })
      pamixer
      pasystray
      pavucontrol
      picom
      postman
      rofi
      rofimoji
      slack
      spotify
      stow
      vscode
      wofi
      wofi-emoji
      xorg.xinput
      xorg.xmodmap
      xsel
      xfce.thunar
    ];
  };

}
