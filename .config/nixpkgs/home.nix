{ config, pkgs, ... }:

{
  # Home Manager needs a bit of information about you and the
  # paths it should manage.
  home.username = "javi";
  home.homeDirectory = if builtins.pathExists "/Users/javi" then "/Users/javi" else "/home/javi";

  home.sessionVariables = {
    EDITOR = "nvim";
  };

  home.packages = [
    pkgs.btop
    pkgs.fd
    pkgs.neofetch
    pkgs.ripgrep
    pkgs.zig
  ];

  # This value determines the Home Manager release that your
  # configuration is compatible with. This helps avoid breakage
  # when a new Home Manager release introduces backwards
  # incompatible changes.
  #
  # You can update Home Manager without changing this value. See
  # the Home Manager release notes for a list of state version
  # changes in each release.
  home.stateVersion = "22.05";

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
      shellInit = if builtins.pathExists "/nix/var/nix/profiles/default" then ''
        fenv source '/nix/var/nix/profiles/default/etc/profile.d/nix-daemon.sh'
      '' else "";
    };

    neovim = {
        enable = true;
        extraPackages = [
            pkgs.nodejs
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
      plugins = with pkgs.tmuxPlugins; [
        nord
      ];
      terminal = "screen-256color";

      extraConfig = ''
        set-option -g mouse on
        set-option -g default-command "fish"
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
