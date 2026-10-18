{ config, lib, pkgs, ... }:

let

  # nodePackages = import ./node2nix/default.nix {
  #   inherit pkgs;
  # };

  unstable = import <nixpkgs-unstable> { config.allowUnfree = true; };

  # Pinned nixpkgs master — the nixos-unstable channel lags and still ships the
  # broken opencode 1.18.30 (upstream regression #48645, fixed in 1.18.31).
  # Revert to unstable.opencode once the channel catches up.
  nixpkgsFixed = import (fetchTarball {
    url = "https://github.com/NixOS/nixpkgs/archive/0fd7ffadbdb893668eab870e085cacf4c94f5867.tar.gz";
    # Hash of the byte variant codeload serves to nix's fetcher (curl gets a
    # different gzip of identical content — 45043f4d…).
    sha256 = "13ackf67rhr84n9m3mk358kmngh35n58b40nz01qmvjnpmhv6x24";
  }) { config.allowUnfree = true; };

  pythonEnv = unstable.python3.withPackages (ppkgs: [
    ppkgs.python
    ppkgs.black
    ppkgs.cfn-lint
    ppkgs.greenlet
    ppkgs.huggingface-hub
    # ppkgs.litellm
    ppkgs.pynvim
  ]);

  # flag on macos
  macos = builtins.pathExists "/Users/javi";

  # Which NixOS box this is. home-manager is invoked standalone (no
  # home-manager.users.<name> in common.nix), so there is no
  # config.networking.hostName here - /etc/hostname is the same trick
  # ~/.config/hypr/hyprland.lua already uses, and it is safe because standalone
  # home-manager always evaluates on the machine it activates on. lib.fileContents
  # strips the trailing newline. Guarded by `macos` first so the macOS eval never
  # touches a path that does not exist there.
  hostName = if macos then "macbook" else lib.fileContents "/etc/hostname";

  # homepc runs DankMaterialShell (programs.dms-shell is declared in
  # ~/.config/nixos/homepc/configuration.nix); the dell stays on the bare
  # hyprland stack - waybar + dunst + hypridle + hyprlock.
  isHomepc = hostName == "homepc";

in {

  # Home Manager needs a bit of information about you and the
  # paths it should manage.
  home.username = "javi";
  home.homeDirectory = if macos then "/Users/javi" else "/home/javi";

  home.sessionVariables = {
    # EDITOR = "nvim";
    # SHELL = "${pkgs.zsh}/bin/zsh";
    # TERM = "xterm-256color";
    SSH_AUTH_SOCK = if macos then "${config.home.homeDirectory}/Library/Group\ Containers/2BUA8C4S2C.com.1password/t/agent.sock" else "${config.home.homeDirectory}/.1password/agent.sock";
    NIXPKGS_ALLOW_UNFREE = 1;
    ANTHROPIC_CONSOLE_KEY = "sk-1234";
    ANTHROPIC_BASE_URL = "http://localhost:8080";
  } // lib.optionalAttrs (!macos) {
    # VA-API driver: iHD = intel-media-driver, which is installed on both NixOS boxes
    # (homepc's Arrow Lake iGPU; the dell via hardware.graphics.extraPackages in its
    # own config). Linux-only - there is no VA-API in the macOS generation.
    # Was `env = LIBVA_DRIVER_NAME,iHD` in ~/.config/hypr/homepc.conf, which stopped
    # being sourced when hyprland.lua replaced hyprland.conf; moved here so it covers
    # the whole session (browsers, mpv, ffmpeg) instead of only Hyprland's children.
    # That file now lives in .config/hypr/legacy/.
    LIBVA_DRIVER_NAME = "iHD";
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
    pkgs.aws-sam-cli
    pkgs.cargo
    unstable.claude-code
    # unstable.crush
    pkgs.dwt1-shell-color-scripts
    # pkgs.aws-sam-cli
    pkgs.gh
    pkgs.ghostscript
    pkgs.go
    pkgs.graph-easy
    pkgs.graphviz
    pkgs.git-remote-codecommit
    pkgs.imagemagick
    # pkgs.inetutils
    pkgs.kitty-themes
    pkgs.marksman
    pkgs.fastfetch
    # unstable.gemini-cli
    # pkgs.kiro
    # pkgs.kiro-cli
    pkgs.nerd-fonts.jetbrains-mono
    pkgs.newman
    # pkgs.nix-du
    pkgs.nixfmt
    # pkgs.nodePackages.aws-cdk
    # pkgs.nodePackages.create-react-app
    pkgs.typescript
    pkgs.prettier
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
  ] ++ lib.optionals (!macos) [
    # Icon themes DMS resolves named icons from (only `hicolor` was installed, so
    # the shell logged `Cannot load icon "audio-volume-low" / "blueman-disabled"`).
    # Adwaita = freedesktop icon names for the bar/OSD; Material Symbols is the
    # icon font DMS's QML references by name. Linux-only: macOS apps use CoreText
    # and their own asset catalogs - neither XDG icon themes nor fontconfig apply.
    pkgs.adwaita-icon-theme
    pkgs.material-symbols
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

  # dunst is for the bare-hyprland hosts only. On homepc DMS's own unit is
  # Type=dbus with BusName=org.freedesktop.Notifications - it IS the notification
  # daemon, and it cannot start while dunst owns that name (busctl showed dunst
  # holding it). The dell has no DMS (programs.dms-shell is host-scoped), so it
  # needs its notification daemon back; macOS has no wayland session at all.
  services.dunst = { enable = !macos && !isHomepc; };

  # Same story for polkit: polkitd allows one agent per subject, and on homepc
  # DMS's built-in agent (since DMS 1.0, no option to turn it off short of
  # DMS_DISABLE_POLKIT=1) loses that registration race to this unit -
  # "An authentication agent already exists for the given subject" in
  # journalctl --user -u dms.service. The dell is bare hyprland (no DMS), so it
  # still needs an external agent; macOS has no polkitd at all.
  services.hyprpolkitagent = { enable = !macos && !isHomepc; };

  # Let Home Manager install and manage itself.
  programs.home-manager.enable = true;

  programs = {

    fd.enable = true;
    fzf.enable = true;
    mpv.enable = true;
    jq.enable = true;
    lazygit.enable = true;

    direnv = {
      enable = true;
      nix-direnv = { enable = true; };
      package = unstable.direnv;
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
      # themeFile = "Catppuccin-Mocha";
      # themeFile = "Dracula";
    };

    neovim = {
      defaultEditor = true;
      enable = true;
      initLua = ''
          vim.g.python3_host_prog='${pythonEnv}/bin/python3'
          vim.g.python_host_prog='${pythonEnv}/bin/python'
          require("config.options")
        	require("config.lazy")
          require("config.remap")
      '';
      package = unstable.neovim-unwrapped;
      extraPackages = [
        # pkgs.checkstyle
        pkgs.gcc
        pkgs.lemminx
        # pkgs.llm-ls
        pkgs.nixd
        pkgs.nixpkgs-fmt
        # pkgs.nodePackages.prettier
        pkgs.typescript-language-server
        pkgs.pyright
        # pkgs.rnix-lsp
        pkgs.lua-language-server
        pkgs.tree-sitter
      ];
      withPython3 = false;
      withRuby = false;
    };

    opencode = {
      enable = true;
      package = nixpkgsFixed.opencode;
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
          export GOOGLE_CLOUD_PROJECT=$(op read op://dev/GOOGLE_CLOUD_PROJECT/credential)
          export GEMINI_API_KEY=$(op read op://dev/GEMINI_API_KEY/credential)
          export GOOGLE_GENERATIVE_AI_API_KEY=$(op read op://dev/GEMINI_API_KEY/credential)
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

  # Nautilus (GTK4 / Files 50) reads its sidebar bookmarks from
  # ~/.config/gtk-3.0/bookmarks as "URI label" lines and monitors that file, so
  # appending is enough - no restart.  Appended idempotently instead of managed
  # as a symlink so Nautilus can still rewrite it (Ctrl+D stays usable).
  # The share itself is a systemd automount (NixOS fileSystems), so clicking the
  # bookmark is what mounts it.
  home.activation.readynasMediaBookmark = lib.mkIf (!macos)
    (lib.hm.dag.entryAfter [ "writeBoundary" ]
      ''
        _bm="${config.home.homeDirectory}/.config/gtk-3.0/bookmarks"
        mkdir -p "$(dirname "$_bm")"
        grep -qF "file:///mnt/readynas-media" "$_bm" 2>/dev/null ||
          printf 'file:///mnt/readynas-media ReadyNAS Media\n' >> "$_bm"
      '');

  # xdg.enable = true;
}
