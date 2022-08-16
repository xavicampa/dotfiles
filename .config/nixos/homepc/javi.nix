{ config, pkgs, ... }:
{
  environment.variables.EDITOR = "nvim";

  nixpkgs.overlays = [
    (self: super: {
      neovim = super.neovim.override {
        viAlias = true;
        vimAlias = true;
      };
      weechat = super.weechat.override {
        configure = { availablePlugins, ... }: {
          scripts = with super.weechatScripts; [
            weechat-matrix
          ];
        };
      };
    })
  ];

  environment.etc."rofi/themes".source = "${pkgs.rofi}/share/rofi/themes";

  i18n.defaultLocale = "en_US.UTF-8";

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

  users.users.javi = {
    shell = pkgs.fish;
    isNormalUser = true;
    extraGroups = [ "wheel" "i2c" ]; # Enable ‘sudo’ for the user.
    packages = with pkgs; [
      fish
      google-chrome
      alacritty
      neovim
      git
      nerdfonts
      gcc
      rofi
      linuxPackages.nvidia_x11
      bottom
      btop
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
      tmux
      neofetch
      bottom
      exa
      ripgrep
      autotiling
      lazygit
      _1password
      _1password-gui
      tree-sitter
      nodejs
      fd
      xclip
      python3
      python39Packages.cfn-lint
      python39Packages.python-lsp-server
      xfce.thunar
      spotify
      sumneko-lua-language-server
      rnix-lsp
      nvtop
      pavucontrol
      slack
      nodePackages.typescript-language-server
      discord
      wezterm
      kitty
      starship
      weechat
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
