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

  pcfg = config.devEnv.plannotator;
  lastPort = pcfg.firstPort + pcfg.portCount - 1;
  plannotatorEnv = {
    PLANNOTATOR_REMOTE = "0";
    PLANNOTATOR_PORT = if pcfg.portCount == 1 then toString pcfg.firstPort
      else "${toString pcfg.firstPort}-${toString lastPort}";
    PLANNOTATOR_SKIP_BROWSER_OPEN = "1";
  };
in
{
  # A range, not one port: each plan or review waiting for a decision holds a port,
  # and parallel plan sessions (`wt --plan`) can have several waiting at once.
  options.devEnv.plannotator = {
    firstPort = lib.mkOption {
      type = lib.types.port;
      default = 19432;
      description = "First port of plannotator's UI; devEnv.proxy serves it at plannotator.localhost.";
    };
    portCount = lib.mkOption {
      type = lib.types.ints.between 1 100;
      default = 8;
      description = ''
        How many ports from firstPort plannotator may use, one per plan or review
        waiting for a decision. devEnv.proxy serves each at plannotator-<port>.localhost.
      '';
    };
  };

  config = {
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

  # No browser in the machine: serve plannotator's UI on fixed ports, on
  # loopback only. Remote mode (PLANNOTATOR_REMOTE=1) would bind 0.0.0.0, and
  # it's also what plannotator picks by itself inside SSH sessions, so local
  # mode is forced. Reach it through devEnv.proxy: the first port at
  # http://plannotator.localhost:8090, and every port at
  # http://plannotator-<port>.localhost:8090. The URL plannotator prints says
  # localhost:<port>: in local mode it ignores PLANNOTATOR_URL_HOST, which
  # can't carry a port anyway.
  home.sessionVariables = plannotatorEnv;
  # Also in .zshenv, for herdr panes (see AGENTS.md).
  programs.zsh.envExtra = lib.concatStrings (lib.mapAttrsToList
    (k: v: "export ${k}=${lib.escapeShellArg v}\n") plannotatorEnv);
  };
}
