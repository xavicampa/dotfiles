{ config, lib, pkgs, ... }:

let

  nodePackages = import ./node2nix/default.nix {
    inherit pkgs;
  };

  pythonEnv = pkgs.python3.withPackages (ppkgs: [
    ppkgs.python
    ppkgs.black
    ppkgs.cfn-lint
    ppkgs.greenlet
    ppkgs.litellm
    ppkgs.pynvim
    # (
    #   buildPythonPackage rec {
    #     pname = "aws-sam-translator";
    #     version = "1.73.0";
    #     src = fetchPypi {
    #       inherit pname version;
    #       sha256 = "sha256-v6fK06ePAC7e7F45/WG2Fs+E809hAQxdwvenaEX+egI=";
    #     };
    #     doCheck = false;
    #     propagatedBuildInputs = [
    #       # Specify dependencies
    #       ppkgs.boto3
    #       ppkgs.jsonschema
    #       ppkgs.typing-extensions
    #       ppkgs.pydantic
    #     ];
    #   }
    # )
  ]);

  # pythonEnvCustom = ps: with ps; [
  # (
  #   buildPythonPackage rec {
  #     pname = "cfn-lint";
  #     version = "0.79.7";
  #     src = fetchPypi {
  #       inherit pname version;
  #       sha256 = "sha256-/NwZWomBBIKvk6M1tXUA/JKBEZmNg4kIf4X9WRVfyQQ=";
  #     };
  #     doCheck = false;
  #     propagatedBuildInputs = [
  #       # Specify dependencies
  #       # pkgs.python3Packages.numpy
  #       # pkgs.python311Packages.aws-sam-translator
  #       pkgs.python311Packages.pyyaml
  #     ];
  #   }
  # )
  # ];

  # flag on macos
  macos = builtins.pathExists "/Users/javi";

in
{

  # Home Manager needs a bit of information about you and the
  # paths it should manage.
  home.username = "javi";
  home.homeDirectory = if macos then "/Users/javi" else "/home/javi";

  home.sessionVariables = {
    # EDITOR = "nvim";
    SHELL = "${pkgs.zsh}/bin/zsh";
  };

  nix.package = pkgs.nixVersions.latest;

  home.packages = [
    config.nix.package
    # pkgs.nodejs
    # nodePackages."@aws-amplify/cli"
    nodePackages."@angular/cli"
    pkgs.awscli2
    # pkgs.aws-sam-cli
    (
      if macos then
        pkgs.btop
      else
        pkgs.btop.overrideAttrs
          (oldAttrs: {
            nativeBuildInputs = (oldAttrs.nativeBuildInputs or [ ]) ++ [ pkgs.addDriverRunpath ];
            postFixup = ''
              addDriverRunpath $out/bin/btop
            '';
          })
    )
    pkgs.graph-easy
    pkgs.git-remote-codecommit
    pkgs.kitty-themes
    pkgs.marksman
    pkgs.fastfetch
    pkgs.nerd-fonts.jetbrains-mono
    pkgs.newman
    # pkgs.nix-du
    pkgs.node2nix
    pkgs.nodePackages.aws-cdk
    pkgs.nodePackages.create-react-app
    pkgs.nodePackages.typescript
    pkgs.nodePackages.prettier
    pkgs.p7zip
    pkgs.ripgrep
    pkgs.shell-gpt
    pkgs.slides
    pkgs.unzip
    pythonEnv
    # (pkgs.python311.withPackages pythonEnvCustom)
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

    fd.enable = true;
    fzf.enable = true;
    jq.enable = true;
    lazygit.enable = true;

    direnv = {
      enable = true;
      nix-direnv = {
        enable = true;
      };
    };

    eza = {
      enable = true;
    };

    kitty = {
      enable = true;
      font = {
        name = if macos then "JetBrainsMono Nerd Font Mono" else "JetBrainsMono Nerd Font";
        size = if macos then 16 else 14;
      };
      keybindings = {
        "ctrl+shift+h" = "previous_window";
      };
      settings = {
        macos_quit_when_last_window_closed = "yes";
        remember_window_size = "no";
        initial_window_width = "80c";
        initial_window_height = "25c";
        background_opacity = "0.90";
        background_blur = 24;
        tab_bar_style = "powerline";
        # tab_powerline_style = "slanted";
        tab_title_template = "{fmt.bold}{tab.active_wd.rsplit('/', 1)[-1]}{fmt.nobold} [{tab.active_exe}]";
        hide_window_decorations = "titlebar-only";
      };
      /* theme = "Gruvbox Dark"; */
      # theme = "Catppuccin-Macchiato";
      themeFile = "Dracula";
    };

    neovide = {
      enable = true;
      settings = {
        font = {
          normal = [ "JetBrainsMono Nerd Font" ];
          size = 13.0;
        };
      };
    };

    neovim = {
      defaultEditor = true;
      enable = true;
      extraLuaConfig = ''
        vim.g.python3_host_prog='${pythonEnv}/bin/python3'
        vim.g.python_host_prog='${pythonEnv}/bin/python'
        require 'options'
        require 'plugins'
        require 'remap'
      '';
      extraPackages = [
        pkgs.gcc
        pkgs.lemminx
        # pkgs.llm-ls
        pkgs.nixd
        pkgs.nixpkgs-fmt
        # pkgs.nodePackages.prettier
        pkgs.nodePackages.typescript-language-server
        pkgs.pyright
        # pkgs.rnix-lsp
        pkgs.sumneko-lua-language-server
        pkgs.tree-sitter
      ];
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
      autosuggestion = {
        enable = true;
      };
      enable = true;
      enableCompletion = true;
      initExtra = ''
        export PATH=/opt/homebrew/opt/node/bin:/opt/homebrew/opt/openssl/bin:$HOME/.nix-profile/bin:/nix/var/nix/profiles/default/bin:$PATH
        export JSII_SILENCE_WARNING_UNTESTED_NODE_VERSION=1
      '';
      shellAliases = {
        dotfiles = "git --git-dir=$HOME/.dotfiles/ --work-tree=$HOME";
        /* ls = "${pkgs.exa}/bin/exa --icons"; */
        ll = "${pkgs.eza}/bin/eza -l --icons";
        /* la = "${pkgs.exa}/bin/exa -a --icons"; */
        /* lt = "${pkgs.exa}/bin/exa --tree --icons"; */
        /* lla = "${pkgs.exa}/bin/exa -la --icons"; */
      };
      oh-my-zsh = {
        enable = true;
        plugins = [ "aws" "git" "brew" "docker" "npm" "pip" ];
        /* theme = "robbyrussell"; */
      };
    };
  };
}
