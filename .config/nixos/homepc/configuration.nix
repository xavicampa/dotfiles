{ config, pkgs, ... }:

{
  imports =
    [
      # Include the results of the hardware scan.
      ./hardware-configuration.nix
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

  # hardware.nvidia.package = config.boot.kernelPackages.nvidiaPackages.legacy_470;
  boot.kernelPackages = pkgs.linuxPackages_latest;

  # Enable the X11 windowing system.
  services.xserver = {
    enable = true;
    displayManager = {
      defaultSession = "none+i3";
    };
    videoDrivers = [ "nvidia" ];
    libinput = {
      enable = true;
    };
  };

  # Enable sound.
  sound.enable = true;

  # bluetooth
  services.blueman.enable = true;

  # List packages installed in system profile. To search, run:
  # $ nix search wget
  # environment.systemPackages = with pkgs; [
  #   wget
  #   git
  # ];


  # List services that you want to enable:

  # Enable the OpenSSH daemon.
  services.openssh.enable = true;

  services.kmscon = {
    enable = true;
  };

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

  services.xserver = {
    dpi = 112;
    layout = "no";
    windowManager.i3 = {
      enable = true;
      package = pkgs.i3-gaps;
      extraPackages = with pkgs; [
        dmenu
        i3status
        i3lock
        i3blocks
      ];
    };
  };

  # fonts.fonts = with pkgs; [
  #   nerdfonts
  # ];

  nixpkgs.config = {
    allowUnfree = true;
  };

  virtualisation.docker.enable = true;

  programs.fish.enable = true;

  users.users.javi = {
    shell = pkgs.fish;
    isNormalUser = true;
    extraGroups = [ "wheel" "i2c" "docker" ]; # Enable ‘sudo’ for the user.
    packages = with pkgs; [
      _1password
      _1password-gui
      autotiling
      blueman
      ddcutil
      discord
      dunst
      feh
      firefox
      flameshot
      git
      google-chrome
      pamixer
      pasystray
      pavucontrol
      picom
      rofi
      rofimoji
      slack
      spotify
      vscode
      xorg.xinput
      xorg.xmodmap
      xclip
      xfce.thunar
    ];
  };

}
