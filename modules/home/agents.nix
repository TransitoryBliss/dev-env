{ inputs }:
{ config, lib, pkgs, ... }:

let
  unstable = import inputs.nixpkgs-unstable {
    inherit (pkgs.stdenv.hostPlatform) system;
    config.allowUnfreePredicate = pkg: builtins.elem (lib.getName pkg) [ "claude-code" ];
  };
  master = inputs.nixpkgs-master.legacyPackages.${pkgs.stdenv.hostPlatform.system};

  # rtk's pi extension shipped after the rtk in nixpkgs, but it only shells out
  # to `rtk rewrite` (rtk >= 0.23), so the packaged binary works with it.
  rtkPiExtension = pkgs.fetchurl {
    url = "https://raw.githubusercontent.com/rtk-ai/rtk/v0.49.0/hooks/pi/rtk.ts";
    hash = "sha256-0VVeCvWHKjDtBAWUIzUL2zgwLyAKlkLFqbzFGclaIlc=";
  };
in
{
  home.packages = [
    master.pi-coding-agent
    unstable.claude-code
    pkgs.rtk
    inputs.herdr.packages.${pkgs.stdenv.hostPlatform.system}.default
    (pkgs.callPackage ../../pkgs/plannotator.nix { })
    # node-gyp needs Python to compile native deps of pi extensions
    # (node-pty has no linux-arm64 prebuild); gcc comes from editor.nix.
    pkgs.python3
  ];

  # Equivalent of `rtk init --global --agent pi`.
  home.file.".pi/agent/extensions/rtk.ts".source = rtkPiExtension;

  # Linked to the checkout (not the store) because herdr's settings UI writes to it.
  xdg.configFile."herdr/config.toml".source =
    config.lib.file.mkOutOfStoreSymlink "${config.devEnv.configDir}/herdr/config.toml";

  # No browser in the machine: serve plannotator's UI on a fixed port. Reach it via
  # `make vm/ssh` (Parallels) or directly at localhost (WSL forwards ports).
  home.sessionVariables = {
    PLANNOTATOR_REMOTE = "1";
    PLANNOTATOR_PORT = "19432";
  };
}
