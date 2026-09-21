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
    };

    programs.direnv = {
      enable = true;
      nix-direnv.enable = true;
    };

    programs.fzf.enable = true;
  };
}
