{ config, lib, pkgs, ... }:

let

  # nodePackages = import ./node2nix/default.nix {
  #   inherit pkgs;
  # };

  unstable = import <nixpkgs-unstable> { config.allowUnfree = true; };

  pythonEnv = unstable.python3.withPackages (ppkgs: [
    ppkgs.python
    ppkgs.black
    ppkgs.cfn-lint
    ppkgs.greenlet
    # ppkgs.litellm
    ppkgs.pynvim
  ]);

  # flag on macos
  macos = builtins.pathExists "/Users/javi";

in {

  # Home Manager needs a bit of information about you and the
  # paths it should manage.
  home.username = "javi";
  home.homeDirectory = if macos then "/Users/javi" else "/home/javi";

  home.sessionVariables = {
    # EDITOR = "nvim";
    # SHELL = "${pkgs.zsh}/bin/zsh";
    # TERM = "xterm-256color";
    NIXPKGS_ALLOW_UNFREE = 1;
  };

  home.file = if macos then {
    "Library/Application Support/lazygit/".source =
      config.lib.file.mkOutOfStoreSymlink "/Users/javi/.config/lazygit/";
  } else
    { };

  nix.package = pkgs.nixVersions.stable;

  home.packages = [
    config.nix.package
    pkgs.nodejs
    # nodePackages."@aws-amplify/cli"
    # nodePackages."@angular/cli"
    pkgs.awscli2
    # pkgs.aws-sam-cli
    pkgs.cargo
    pkgs.dwt1-shell-color-scripts
    # pkgs.aws-sam-cli
    pkgs.ghostscript
    pkgs.go
    pkgs.graph-easy
    pkgs.graphviz
    pkgs.git-remote-codecommit
    pkgs.imagemagick
    pkgs.inetutils
    pkgs.kitty-themes
    pkgs.marksman
    pkgs.fastfetch
    # pkgs.kiro
    # pkgs.kiro-cli
    pkgs.nerd-fonts.jetbrains-mono
    pkgs.newman
    # pkgs.nix-du
    pkgs.nixfmt-classic
    pkgs.node2nix
    # pkgs.nodePackages.aws-cdk
    # pkgs.nodePackages.create-react-app
    pkgs.nodePackages.typescript
    pkgs.nodePackages.prettier
    pkgs.p7zip
    pkgs.ripgrep
    pkgs.nixd
    pkgs.shell-gpt
    pkgs.slides
    pkgs.starship
    pkgs.unzip
    pkgs.vscode-langservers-extracted
    pkgs.yaml-language-server
    pkgs.uv
    pkgs.wget
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

  services.dunst = { enable = if macos then false else true; };

  # Let Home Manager install and manage itself.
  programs.home-manager.enable = true;

  programs = {

    fd.enable = true;
    fzf.enable = true;
    jq.enable = true;
    lazygit.enable = true;

    direnv = {
      enable = true;
      nix-direnv = { enable = true; };
    };

    eza = { enable = true; };

    # ghostty = {
    #     enable = true;
    # };

    kitty = {
      enable = true;
      font = {
        name = if macos then
          "JetBrainsMono Nerd Font Mono"
        else
          "JetBrainsMono Nerd Font";
        size = if macos then 16 else 12;
      };
      keybindings = { "ctrl+shift+h" = "previous_window"; };
      settings = {
        macos_quit_when_last_window_closed = "yes";
        remember_window_size = "no";
        initial_window_width = "80c";
        initial_window_height = "25c";
        # background_opacity = "0.90";
        # background_blur = 24;
        tab_bar_style = "powerline";
        # tab_powerline_style = "slanted";
        tab_title_template =
          "{fmt.bold}{tab.active_wd.rsplit('/', 1)[-1]}{fmt.nobold} [{tab.active_exe}]";
        hide_window_decorations = if macos then "no" else "titlebar-only";
      };
      # theme = "Gruvbox Dark";
      # theme = "Catppuccin-Macchiato";
      themeFile = "Dracula";
    };

    neovim = {
      defaultEditor = true;
      enable = true;
      extraLuaConfig = ''
          vim.g.python3_host_prog='${pythonEnv}/bin/python3'
          vim.g.python_host_prog='${pythonEnv}/bin/python'
          require("config.options")
        	require("config.lazy")
          require("config.remap")
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
        pkgs.lua-language-server
        pkgs.tree-sitter
        pkgs.write-good
      ];
    };

    opencode = {
      enable = true;
      package = unstable.opencode;
    };

    zsh = {
      autosuggestion = { enable = true; };
      enable = true;
      enableCompletion = true;
      initContent = ''
        export PATH=/opt/homebrew/opt/node/bin:/opt/homebrew/opt/openssl/bin:$PATH
        export PATH=$HOME/.nix-profile/bin:/nix/var/nix/profiles/default/bin:$PATH

        npm set prefix ~/.npm-global
        export PATH=$HOME/.npm-global/bin:$PATH

        # kiro-cli
        # [[ "$TERM_PROGRAM" == "kiro" ]] && . "$(kiro --locate-shell-integration-path zsh)"

        # import shell secrets from 1password
        envop(){
          export BRAVE_API_KEY=$(op read op://dev/BRAVE_API_KEY/credential)
          export HF_TOKEN=$(op read op://dev/HF_TOKEN/credential)
        }
        autoload -Uz envop

        # only starship in kitty
        if [[ $TERM = *"kitty"* ]]; then
          eval "$(${pkgs.starship}/bin/starship init zsh)"
        fi
      '';
      shellAliases = {
        dotfiles = "git --git-dir=$HOME/.dotfiles/ --work-tree=$HOME";
        ll = "${pkgs.eza}/bin/eza -l --icons";
      };
      oh-my-zsh = {
        enable = true;
        plugins = [ "aws" "git" "brew" "podman" "npm" "pip" ];
        extraConfig = ''
          zstyle ':omz:update' mode disabled
          DISABLE_UPDATE_PROMPT=true
        '';
        # theme = "robbyrussell";
      };
    };
  };

  # xdg.enable = true;
}
