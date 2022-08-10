{ config, pkgs, ... }:

# let
#   dotfiles = pkgs.fetchFromGitHub {
#     owner = "xavicampa";
#     repo = "dotfiles";
#     rev = "7fe224fa9016a92dd3fd556b9f2951aa003ec2e0";
#     sha256 = "sha256-1D1V5KK3t8GEXSn9wQ0C8vVE150H54JALT98SevE4TU=";
#   };
# in
{
  imports =
    [
      # Include the results of the hardware scan.
      ./hardware-configuration.nix
      /home/javi/.config/nixos/homepc/javi.nix
      <home-manager/nixos>
    ];

  # Use the systemd-boot EFI boot loader.
  boot.loader.systemd-boot.enable = true;
  boot.loader.efi.canTouchEfiVariables = true;

  networking.hostName = "homepc"; # Define your hostname.
  # Pick only one of the below networking options.
  # networking.wireless.enable = true;  # Enables wireless support via wpa_supplicant.
  networking.networkmanager.enable = true; # Easiest to use and most distros use this by default.

  # Set your time zone.
  time.timeZone = "Europe/Oslo";

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
  environment.systemPackages = with pkgs; [
    vim # Do not forget to add an editor to edit configuration.nix! The Nano editor is also installed by default.
    wget
  ];

  # users.users.xavi2.isNormalUser = true;
  # home-manager.users.xavi2 = { pkgs, ... }: {
  #   home.file = {
  #     "dotfiles/".source = builtins.toPath "${dotfiles}/";
  #   };
  #   home.packages = [ pkgs.home-manager ];
  #   programs.home-manager.enable = true;
  # };

  # Some programs need SUID wrappers, can be configured further or are
  # started in user sessions.
  # programs.mtr.enable = true;
  # programs.gnupg.agent = {
  #   enable = true;
  #   enableSSHSupport = true;
  # };

  # List services that you want to enable:

  # Enable the OpenSSH daemon.
  # services.openssh.enable = true;

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
  system.stateVersion = "22.05"; # Did you read the comment?

}
