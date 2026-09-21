# Home-manager module for the dev-env user.
{ inputs }:
{ lib, pkgs, ... }:

{
  imports = [
    (import ./agents.nix { inherit inputs; })
    ./editor.nix
    ./git.nix
    ./languages.nix
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

      # Up/Down search history for what's already typed ("n" then Up cycles
      # only commands starting with "n") and keep the cursor in place; on a
      # multi-line buffer they still move between lines first.
      #
      # zsh selects the vi keymap on its own because EDITOR is nvim (it looks
      # for "vi" in $EDITOR), so bind in viins/vicmd as well as emacs. Both
      # the normal and application-mode escape sequences are bound, plus
      # whatever terminfo reports, since terminals send either.
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

    programs.direnv = {
      enable = true;
      nix-direnv.enable = true;
    };

    programs.fzf.enable = true;
  };
}
