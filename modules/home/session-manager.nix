# Pi Session Manager: a headless server with a web UI for browsing, searching
# and resuming agent sessions, plus its pi extension (psm-bridge). Off by
# default. The server listens on localhost only; reach it in a browser through
# devEnv.proxy (http://psm.localhost:<port>).
{ config, lib, pkgs, ... }:

let
  cfg = config.devEnv.sessionManager;
  psm = pkgs.callPackage ../../pkgs/pi-session-manager { };
  stateDir = "${config.home.homeDirectory}/.pi/pi-session-manager";

  # PSM rewrites its own config.json, so home-manager can't own it. Instead,
  # pin the settings that matter for safety before every start.
  prepare = pkgs.writeShellScript "pi-session-manager-prepare" ''
    set -eu
    mkdir -p ${stateDir}
    cfg=${stateDir}/config.json
    [ -s "$cfg" ] || echo '{}' > "$cfg"
    ${pkgs.jq}/bin/jq '.server = ((.server // {}) + {
      http_enabled: true, http_port: ${toString cfg.port},
      bind_addr: "127.0.0.1", auth_enabled: true })' "$cfg" > "$cfg.tmp"
    mv "$cfg.tmp" "$cfg"
    # Older releases created a fixed token, the same on every install.
    # Remove it so the server generates a random one.
    tokens=${stateDir}/auth_tokens.json
    if [ -f "$tokens" ] && ${pkgs.jq}/bin/jq -e 'any(.tokens[]; .token == "pi-session-manager")' "$tokens" >/dev/null; then
      rm "$tokens"
    fi
  '';
in
{
  options.devEnv.sessionManager = {
    enable = lib.mkEnableOption "Pi Session Manager (headless server, web UI and pi extension)";
    port = lib.mkOption {
      type = lib.types.port;
      default = 52131;
      description = "Localhost port of the server. The pi extension reads it from PSM's config.";
    };
  };

  config = lib.mkIf cfg.enable {
    home.packages = [ psm ];

    # pi loads a directory whose package.json declares pi.extensions.
    home.file.".pi/agent/extensions/psm-bridge".source =
      "${psm}/share/pi-session-manager/pi-session-bridge";

    systemd.user.services.pi-session-manager = {
      Unit.Description = "Pi Session Manager server";
      Service = {
        ExecStartPre = "${prepare}";
        ExecStart = "${psm}/bin/pi-session-cli";
        Restart = "on-failure";
      };
      Install.WantedBy = [ "default.target" ];
    };
  };
}
