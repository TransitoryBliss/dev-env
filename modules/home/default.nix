# Home-manager module for the dev-env user.
{ inputs }:
{ config, lib, pkgs, ... }:

let
  # Oh My Zsh's default $ZSH/custom is inside the read-only store, so point
  # ZSH_CUSTOM at a writable directory instead: `herdr plugin install`
  # symlinks the herdr plugin into $ZSH_CUSTOM/plugins (see `agents/setup`).
  zshCustom = "${config.xdg.dataHome}/oh-my-zsh-custom";
in
{
  imports = [
    (import ./agents.nix { inherit inputs; })
    ./editor.nix
    ./git.nix
    (import ./languages.nix { inherit inputs; })
    ./terminal.nix
  ];

  options.devEnv.configDir = lib.mkOption {
    type = lib.types.str;
    description = "Checkout of the private config; nvim/ and herdr/ in it are linked into ~/.config.";
  };

  config = {
    home.stateVersion = lib.mkDefault "26.05";

    home.packages = with pkgs; [
      ripgrep
      fd
      jq
      htop
      tree
    ];

    programs.zsh = {
      enable = true;
      autosuggestion.enable = true;
      syntaxHighlighting.enable = true;

      # zsh would pick the vi keymap on its own, because it looks for "vi" in
      # $EDITOR and ours is nvim. Oh My Zsh's key-bindings.zsh then forces
      # emacs with `bindkey -e` anyway; say so here so the keymap is a
      # decision rather than a side effect of load order.
      defaultKeymap = "emacs";

      oh-my-zsh = {
        enable = true;
        theme = "robbyrussell";
        custom = zshCustom;
        # zsh-autosuggestions and zsh-syntax-highlighting come from the
        # options above, not from Oh My Zsh, so they are not listed.
        # direnv is redundant with programs.direnv's own hook below (both
        # refuse to register _direnv_hook twice, and the last definition,
        # home-manager's, wins) but keeps the list honest about what loads.
        # herdr is installed by `make agents/setup`; until then Oh My Zsh
        # prints "plugin 'herdr' not found" on each new shell.
        plugins = [
          "git"
          "direnv"
          "herdr"
        ];
      };

      # Up/Down search history for what's already typed ("n" then Up cycles
      # only commands starting with "n") and keep the cursor in place; on a
      # multi-line buffer they still move between lines first.
      #
      # Oh My Zsh binds these too, identically. This block is kept so the
      # behaviour survives turning Oh My Zsh off, and because it runs at
      # order 1000, after Oh My Zsh at 800, it also wins. Both the normal and
      # application-mode escape sequences are bound, plus whatever terminfo
      # reports, since terminals send either.
      initContent = ''
        autoload -U up-line-or-beginning-search down-line-or-beginning-search
        zle -N up-line-or-beginning-search
        zle -N down-line-or-beginning-search
        zmodload zsh/terminfo

        () {
          local map key
          for map in emacs viins vicmd; do
            for key in '^[[A' '^[OA' "$terminfo[kcuu1]"; do
              if [[ -n $key ]]; then
                bindkey -M $map "$key" up-line-or-beginning-search
              fi
            done
            for key in '^[[B' '^[OB' "$terminfo[kcud1]"; do
              if [[ -n $key ]]; then
                bindkey -M $map "$key" down-line-or-beginning-search
              fi
            done
          done
          # Same for k/j in vi command mode.
          bindkey -M vicmd k up-line-or-beginning-search
          bindkey -M vicmd j down-line-or-beginning-search
        }
      '';
    };

    # Oh My Zsh reads ZSH_CUSTOM from .zshrc, which only interactive shells
    # source. herdr runs the plugin's install step as a non-interactive
    # `zsh bin/install-zsh-plugin`, which sees .zshenv only, so export it
    # there as well. ($ZSH itself is already written to .zshenv.)
    #
    # This goes in envExtra rather than home.sessionVariables: the latter ends
    # up in hm-session-vars.sh, which returns early when __HM_SESS_VARS_SOURCED
    # is already set, and a long-lived herdr server inherits that from the
    # shell that started it. .zshenv is read unconditionally.
    programs.zsh.envExtra = ''
      export ZSH_CUSTOM=${lib.escapeShellArg zshCustom}
    '';

    # Create $ZSH_CUSTOM/plugins as a real, writable directory. home-manager
    # links individual files and creates their parent directories, so the
    # marker leaves the directory itself writable for `herdr plugin install`.
    xdg.dataFile."oh-my-zsh-custom/plugins/.keep".text = "";

    programs.direnv = {
      enable = true;
      nix-direnv.enable = true;
    };

    programs.fzf.enable = true;
  };
}
