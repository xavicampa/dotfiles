{ config, pkgs, ... }:
{
  nixpkgs.overlays = [
    (self: super: {
      neovim = super.neovim.override {
        viAlias = true;
        vimAlias = true;
      };
    })
  ];

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
    layout = "no";
  };

  fonts.fonts = with pkgs; [
    nerdfonts
  ];

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
      # fish
      google-chrome
      # unstable.neovim
      # git
      # nerdfonts
      # gcc
      rofi
      linuxPackages.nvidia_x11_legacy470
      # bottom
      # btop
      xorg.xmodmap
      xorg.xinput
      pamixer
      blueman
      pasystray
      dunst
      picom
      feh
      ddcutil
      rofimoji
      flameshot
      # tmux
      # neofetch
      # exa
      autotiling
      # lazygit
      _1password
      _1password-gui
      # tree-sitter
      xclip
      xfce.thunar
      spotify
      # sumneko-lua-language-server
      # rnix-lsp
      pavucontrol
      slack
      discord
      kitty
      # starship
      vscode
      # zip
      # unzip
      # fishPlugins.fzf-fish
      # fd
      # fzf
      # ripgrep
      # jq
      # unstable.nodePackages.graphql-language-service-cli
      # unstable.nodePackages.graphql
      # unstable.nodePackages.typescript
    ];
  };

  # hardware.pulseaudio.configFile = pkgs.writeText "default.pa" ''
  #   load-module module-alsa-sink device=hw:1,3 sink_name=HDMI-0
  #   load-module module-alsa-sink device=hw:1,7 sink_name=DP-0
  #   load-module module-combined-sink sink_name=Combined
  #   set-default-sink Combined
  # '';

}
