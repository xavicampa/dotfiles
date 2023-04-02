{ config, pkgs, ... }:

let
  nodePackages = import ./node2nix/default.nix {
    inherit pkgs;
  };
in

{
  # Home Manager needs a bit of information about you and the
  # paths it should manage.
  home.username = "javi";
  home.homeDirectory = if builtins.pathExists "/Users/javi" then "/Users/javi" else "/home/javi";

  home.sessionVariables = {
    EDITOR = "nvim";
  };

  nixpkgs.overlays = [
    (self: super: {
      nerdfonts = super.nerdfonts.override {
        fonts = [ "JetBrainsMono" ];
      };
    })
  ];

  home.packages = [
    nodePackages."@aws-amplify/cli"
    nodePackages."aws-cdk"
    pkgs.awscli2
    pkgs.btop
    pkgs.figlet
    pkgs.kitty-themes
    pkgs.haskellPackages.patat
    pkgs.lxappearance
    pkgs.marksman
    pkgs.neofetch
    pkgs.nerdfonts
    pkgs.nodejs
    pkgs.nodePackages.node2nix
    pkgs.nodePackages.typescript
    pkgs.nodePackages.typescript-language-server
    pkgs.nodePackages.create-react-app
    pkgs.p7zip
    pkgs.python39
    pkgs.python39Packages.python-lsp-server
    pkgs.unzip
    /* pkgs.zig */
  ];

  # This value determines the Home Manager release that your
  # configuration is compatible with. This helps avoid breakage
  # when a new Home Manager release introduces backwards
  # incompatible changes.
  #
  # You can update Home Manager without changing this value. See
  # the Home Manager release notes for a list of state version
  # changes in each release.
  home.stateVersion = "22.11";

  fonts.fontconfig.enable = true;

  # Let Home Manager install and manage itself.
  programs.home-manager.enable = true;

  programs = {

    fzf.enable = true;
    jq.enable = true;
    lazygit.enable = true;

    direnv = {
      enable = true;

      nix-direnv = {
        enable = true;
      };
    };

    exa = {
      enable = true;
    };

    fish = {
      enable = true;

      interactiveShellInit = ''
        set -g SHELL ${pkgs.fish}/bin/fish
        fish_add_path /opt/homebrew/bin
        set fish_greeting
      '';
      plugins = [
        {
          name = "plugin-foreign-env";
          src = pkgs.fetchFromGitHub {
            owner = "oh-my-fish";
            repo = "plugin-foreign-env";
            rev = "dddd9213272a0ab848d474d0cbde12ad034e65bc";
            sha256 = "00xqlyl3lffc5l0viin1nyp819wf81fncqyz87jx8ljjdhilmgbs";
          };
        }
      ];
      shellAliases = {
        dotfiles = "git --git-dir=$HOME/.dotfiles/ --work-tree=$HOME";
        ls = "${pkgs.exa}/bin/exa --icons";
        ll = "${pkgs.exa}/bin/exa -l --icons";
        la = "${pkgs.exa}/bin/exa -a --icons";
        lt = "${pkgs.exa}/bin/exa --tree --icons";
        lla = "${pkgs.exa}/bin/exa -la --icons";
      };
      shellInit =
        if builtins.pathExists "/nix/var/nix/profiles/default" then ''
          fenv source '/nix/var/nix/profiles/default/etc/profile.d/nix-daemon.sh'
        '' else "";
    };

    kitty = {
      enable = true;
      font = {
        name = "JetBrainsMono Nerd Font";
        size = 14;
      };
      settings = {
        macos_quit_when_last_window_closed = "yes";
        remember_window_size = "no";
        initial_window_width = "80c";
        initial_window_height = "25c";
      };
      theme = "Gruvbox Dark";
    };

    neovim = {
      enable = true;
      extraPackages = [
        pkgs.fd
        pkgs.gcc
        pkgs.ripgrep
        pkgs.rnix-lsp
        pkgs.sumneko-lua-language-server
        pkgs.tree-sitter
      ];
      withNodeJs = true;
      withPython3 = true;
    };

    tmux = {
      enable = true;

      baseIndex = 1;
      escapeTime = 10;
      keyMode = "vi";
      plugins = with pkgs.tmuxPlugins; [
        gruvbox
        yank
      ];
      terminal = "xterm-kitty";

      extraConfig = ''
        set-option -g mouse on
      '';
    };

    starship = {
      enable = true;

      settings = {
        add_newline = false;
      };
    };
  };
}
