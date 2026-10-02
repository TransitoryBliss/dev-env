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
  rtkPiHookVersion = "v0.49.0";
  rtkPiExtension = pkgs.fetchurl {
    url = "https://raw.githubusercontent.com/rtk-ai/rtk/${rtkPiHookVersion}/hooks/pi/rtk.ts";
    hash = "sha256-0VVeCvWHKjDtBAWUIzUL2zgwLyAKlkLFqbzFGclaIlc=";
  };

  herdr = inputs.herdr.packages.${pkgs.stdenv.hostPlatform.system}.default;
  plannotator = pkgs.callPackage ../../pkgs/plannotator.nix { };

  # `dev-env-updates`: what has a newer release (a report; changes nothing).
  # The versions pinned here, and the base's locked GitHub inputs, are baked in.
  flakeLock = builtins.fromJSON (builtins.readFile ../../flake.lock);
  lockedInputs = lib.filterAttrs (_: v: v != null) (lib.mapAttrs (_: key:
    let node = flakeLock.nodes.${key}; in
    if node.locked.type or "" != "github" then null else {
      inherit (node.original) owner repo;
      ref = node.original.ref or null;
      inherit (node.locked) rev lastModified;
    }) flakeLock.nodes.root.inputs);
  updatesInfo = pkgs.writeText "dev-env-updates.json" (builtins.toJSON {
    plannotator = plannotator.version;
    piSessionManager = (pkgs.callPackage ../../pkgs/pi-session-manager { }).version;
    herdr = herdr.version;
    rtkPiHook = rtkPiHookVersion;
    inputs = lockedInputs;
  });
  devEnvUpdates = pkgs.writeShellScriptBin "dev-env-updates" ''
    exec ${pkgs.python3}/bin/python3 ${./dev-env-updates.py} ${updatesInfo} "$@"
  '';

  plannotatorEnv = {
    PLANNOTATOR_REMOTE = "0";
    PLANNOTATOR_SKIP_BROWSER_OPEN = "1";
  };
in
{
  home.packages = [
    master.pi-coding-agent
    unstable.claude-code
    pkgs.rtk
    herdr
    plannotator
    devEnvUpdates
    # node-gyp needs Python to compile native deps of pi extensions
    # (node-pty has no linux-arm64 prebuild); gcc comes from editor.nix.
    pkgs.python3
  ];

  # Equivalent of `rtk init --global --agent pi`.
  home.file.".pi/agent/extensions/rtk.ts".source = rtkPiExtension;

  # Linked to the checkout (not the store) because herdr's settings UI writes to it.
  xdg.configFile."herdr/config.toml".source =
    config.lib.file.mkOutOfStoreSymlink "${config.devEnv.configDir}/herdr/config.toml";

  # No browser in the machine: plannotator serves its UI on loopback only, on a
  # random port. Remote mode (PLANNOTATOR_REMOTE=1) would bind 0.0.0.0, and it's
  # also what plannotator picks by itself inside SSH sessions, so local mode is
  # forced. devEnv.proxy's watcher finds each review page by its title and routes
  # it as http://plan.<branch or repo>.<machine>.localhost:<port>, with a herdr
  # notification carrying the link. The localhost:<port> URL plannotator prints
  # only works inside the machine.
  home.sessionVariables = plannotatorEnv;
  # Also in .zshenv, for herdr panes (see AGENTS.md).
  programs.zsh.envExtra = lib.concatStrings (lib.mapAttrsToList
    (k: v: "export ${k}=${lib.escapeShellArg v}\n") plannotatorEnv);
}
