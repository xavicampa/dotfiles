{ pkgs, config, ... }:

let
  unstable = import <nixpkgs-unstable> { config.allowUnfree = true; };
in

{
  # imports =
  #   [
  #     # Include the results of the hardware scan.
  #     ./hardware-configuration.nix
  #     # ./sentinel.nix
  #   ];

  nixpkgs.config.allowUnfree = true;

  # Use the systemd-boot EFI boot loader.
  boot.loader.systemd-boot.enable = true;
  boot.loader.efi.canTouchEfiVariables = true;

  # Clean up
  nix.gc.automatic = true;
  nix.settings.auto-optimise-store = true;

  # Pick only one of the below networking options.
  # networking.wireless.enable = true;  # Enables wireless support via wpa_supplicant.
  networking.networkmanager.enable = true; # Easiest to use and most distros use this by default.
  # networking.firewall.trustedInterfaces = [ "docker0" ];

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
    environmentVariables = { OLLAMA_MAX_LOADED_MODELS = "5"; OLLAMA_KEEP_ALIVE = "1h"; };
    # package = stable.ollama;
  };

  # keyring
  services.gnome.gnome-keyring.enable = true;

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
  environment.etc."hypr/hypr.conf".source = "${config.users.users.javi.home}/.config/hypr/${config.networking.hostName}.conf";
  environment.etc."waybar/config.jsonc".source = "${config.users.users.javi.home}/.config/waybar/${config.networking.hostName}.jsonc";

  i18n = {
    defaultLocale = "nb_NO.UTF-8";
    extraLocaleSettings = {
      LC_ALL = "nb_NO.UTF-8";
      LANG = "en_US.UTF-8";
      LANGUAGE = "en_US.UTF-8";
    };
  };

  programs.regreet.enable = true;
  programs.hyprland = {
    enable = true;
    xwayland.enable = true;
    withUWSM = true;
  };

  programs.ssh = {
    enableAskPassword = false;
  };

  environment.sessionVariables = {
    NIXOS_OZONE_WL = "1";
    ELECTRON_OZONE_PLATFORM_HINT = "auto";
    GIT_ASKPASS = "";
  };

  services.libinput = {
    enable = true;
  };

  # virtualisation.docker.enable = true;
  virtualisation = {
    containers.enable = true;
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
  };

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

  programs._1password-gui = {
    enable = true;
    package = unstable._1password-gui;
  };

  programs.firefox = {
    enable = true;
    package = pkgs.firefox-bin;
  };

  programs.waybar.enable = true;

  users.users.javi = {
    shell = pkgs.zsh;
    isNormalUser = true;
    extraGroups = [ "wheel" "i2c" "input" "podman" "video" ]; # Enable ‘sudo’ for the user.
    packages = with pkgs; [
      # adwaita-qt
      apple-cursor
      autotiling
      blueman
      bruno
      busybox # killall
      ddcutil
      discord
      docker-compose
      egl-wayland
      feh
      unstable.file-roller
      # flameshot
      unstable.ghostty
      git
      google-chrome
      hypridle
      hyprpaper
      hyprshot
      nodejs_18
      pamixer
      pasystray
      pavucontrol
      # picom
      # postman
      rofi-wayland
      rofimoji
      slack
      spotify
      stow
      vscode
      wl-clipboard
      # wofi
      # wofi-emoji
      # wpaperd
      wtype
      xdg-user-dirs
      xdg-utils
      xfce.thunar
      # xorg.xinput
      # xorg.xmodmap
    ];
  };

  xdg.portal = {
    enable = true;
    extraPortals = [
      pkgs.xdg-desktop-portal-gtk
    ];
    wlr.enable = true;
  };

}
