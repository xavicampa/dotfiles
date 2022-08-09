{ config, pkgs, ... }:

{
  environment.variables.EDITOR = "nvim";
  nixpkgs.overlays = [
    (self: super: {
      neovim = super.neovim.override {
        viAlias = true;
        vimAlias = true;
      };
    })
  ];

  environment.etc."rofi/themes".source = "${pkgs.rofi}/share/rofi/themes";

  i18n.defaultLocale = "nb_NO.UTF-8";

  services.xserver = {
    windowManager.i3 = {
      enable = true;
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

  nixpkgs.config.allowUnfree = true;

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
    ];
  };
}
