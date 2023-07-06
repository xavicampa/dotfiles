{ config, lib, pkgs, ... }:

let
  nodePackages = import ./node2nix/default.nix {
    inherit pkgs;
  };
  pythonEnv = pkgs.python311.withPackages (ppkgs: [
    ppkgs.black
    ppkgs.cfn-lint
    ppkgs.greenlet
    ppkgs.pynvim
  ]);
in
{
  # Home Manager needs a bit of information about you and the
  # paths it should manage.
  home.username = "javi";
  home.homeDirectory = if builtins.pathExists "/Users/javi" then "/Users/javi" else "/home/javi";

  home.sessionVariables = {
    EDITOR = "nvim";
    SHELL = "${pkgs.zsh}/bin/zsh";
  };

  home.packages = [
    nodePackages."@aws-amplify/cli"
    nodePackages."aws-cdk"
    pkgs.awscli2
    pkgs.aws-sam-cli
    pkgs.btop
    pkgs.graph-easy
    pkgs.kitty-themes
    pkgs.marksman
    pkgs.neofetch
    (pkgs.nerdfonts.override { fonts = [ "JetBrainsMono" ]; })
    pkgs.newman
    pkgs.node2nix
    # pkgs.nodePackages.aws-cdk
    pkgs.nodePackages.create-react-app
    pkgs.nodePackages.typescript
    pkgs.p7zip
    pkgs.slides
    pkgs.unzip
    pythonEnv
  ];

  # This value determines the Home Manager release that your
  # configuration is compatible with. This helps avoid breakage
  # when a new Home Manager release introduces backwards
  # incompatible changes.
  #
  # You can update Home Manager without changing this value. See
  # the Home Manager release notes for a list of state version
  # changes in each release.
  home.stateVersion = "23.05";

  fonts.fontconfig.enable = lib.mkForce true;

  # Let Home Manager install and manage itself.
  programs.home-manager.enable = true;

  programs = {

    fzf.enable = true;
    jq.enable = true;
    lazygit.enable = true;

    /* direnv = { */
    /*   enable = true; */
    /*  */
    /*   nix-direnv = { */
    /*     enable = true; */
    /*   }; */
    /* }; */

    exa = {
      enable = true;
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
      /* theme = "Gruvbox Dark"; */
      # theme = "Catppuccin-Macchiato";
      theme = "Dracula";
    };

    neovim = {
      enable = true;
      extraPackages = [
        pkgs.fd
        pkgs.gcc
        pkgs.nodePackages.prettier
        pkgs.nodePackages.pyright
        pkgs.nodePackages.typescript-language-server
        pkgs.ripgrep
        pkgs.rnix-lsp
        pkgs.sumneko-lua-language-server
        pkgs.tree-sitter
      ];
      extraLuaConfig = ''
        vim.g.python3_host_prog='${pythonEnv}/bin/python3'
        vim.g.python_host_prog='${pythonEnv}/bin/python'
        require 'options'
        require 'plugins'
        require 'remap'
      '';
    };

    /* tmux = { */
    /*   enable = true; */
    /*  */
    /*   baseIndex = 1; */
    /*   escapeTime = 10; */
    /*   keyMode = "vi"; */
    /*   plugins = with pkgs.tmuxPlugins; [ */
    /*     gruvbox */
    /*     yank */
    /*   ]; */
    /*   terminal = "xterm-kitty"; */
    /*  */
    /*   extraConfig = '' */
    /*     set-option -g mouse on */
    /*   ''; */
    /* }; */

    starship = {
      enable = true;
      settings = {
        add_newline = false;
      };
    };

    zsh = {
      enable = true;
      enableAutosuggestions = true;
      enableCompletion = true;
      initExtra = ''
        export PATH=/opt/homebrew/opt/node@18/bin:/opt/homebrew/opt/openssl@1.1/bin:$HOME/.nix-profile/bin:/nix/var/nix/profiles/default/bin:$PATH
      '';
      shellAliases = {
        dotfiles = "git --git-dir=$HOME/.dotfiles/ --work-tree=$HOME";
        /* ls = "${pkgs.exa}/bin/exa --icons"; */
        ll = "${pkgs.exa}/bin/exa -l --icons";
        /* la = "${pkgs.exa}/bin/exa -a --icons"; */
        /* lt = "${pkgs.exa}/bin/exa --tree --icons"; */
        /* lla = "${pkgs.exa}/bin/exa -la --icons"; */
      };
      oh-my-zsh = {
        enable = true;
        plugins = [ "git" "brew" "docker" "npm" "pip" ];
        /* theme = "robbyrussell"; */
      };
    };
  };
}
