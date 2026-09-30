# Local reverse proxy: one localhost port, one name per web UI in the machine.
#
#   http://<machine>.localhost:<port>          index of everything running
#   http://<name>.<machine>.localhost:<port>   one service
#
# Reach it through an SSH tunnel for that one port (`make vm/ssh`), or directly from
# Windows on WSL. Browsers resolve *.localhost to 127.0.0.1 by themselves.
#
# Caddy runs as a systemd user service (`devproxy`), so routes change without root.
# `devproxy-watch` (devproxy.py) finds services by itself and names them after where
# they run; `services` below adds fixed names. Caddy guards every backend: it only
# answers the names it knows (no DNS rebinding), rejects requests whose Origin is
# another site (browser drive-by requests, including WebSocket upgrades), sets its
# own X-Forwarded-For, and strips CORS headers the backends send. Its admin API is
# a Unix socket in $XDG_RUNTIME_DIR, not TCP port 2019.
{ config, lib, pkgs, ... }:

let
  cfg = config.devEnv.proxy;
  user = config.devEnv.user.name;
  hm = config.home-manager.users.${user};

  settings = pkgs.writeText "devproxy.json" (builtins.toJSON {
    machine = cfg.machineName;
    inherit (cfg) port services;
    scopeRoots = hm.devEnv.scopeRoots;
    # Never routed: pi's MCP OAuth callback, Chrome DevTools, the Node inspector.
    excludePorts = [ hm.devEnv.mcp.callbackPort 9222 9229 ];
  });

  devproxy = pkgs.writeScriptBin "devproxy" ''
    #!${pkgs.python3}/bin/python3
    DEFAULT_CONFIG = "${settings}"
    ${builtins.readFile ./devproxy.py}
  '';
in
{
  options.devEnv.proxy = {
    enable = lib.mkEnableOption "the local reverse proxy (Caddy) for web UIs in the machine";
    port = lib.mkOption {
      type = lib.types.port;
      default = 8090;
      description = "Localhost port the proxy listens on. Forward this one port to reach every service.";
    };
    machineName = lib.mkOption {
      type = lib.types.strMatching "[a-z0-9]([a-z0-9-]*[a-z0-9])?";
      default = lib.toLower config.networking.hostName;
      defaultText = lib.literalExpression "lib.toLower config.networking.hostName";
      description = "Middle part of every name: http://<name>.<machineName>.localhost:<port>.";
    };
    services = lib.mkOption {
      type = lib.types.attrsOf lib.types.port;
      default = { };
      example = { grafana = 3000; };
      description = ''
        Fixed names, as name -> localhost port: `psm` becomes
        http://psm.<machineName>.localhost:<port>. Everything else is found and named
        by devproxy-watch.
      '';
    };
  };

  config = lib.mkIf cfg.enable {
    devEnv.proxy.services = {
      psm = lib.mkIf hm.devEnv.sessionManager.enable hm.devEnv.sessionManager.port;
      # Fixed port set in modules/home/editor.nix.
      md = lib.mkDefault 6419;
    };

    home-manager.users.${user} = {
      home.packages = [ devproxy ];

      systemd.user.services.devproxy = {
        Unit.Description = "Local reverse proxy for web UIs (Caddy)";
        Service = {
          ExecStartPre = "${devproxy}/bin/devproxy config %t/devproxy/caddy.json";
          ExecStart = "${pkgs.caddy}/bin/caddy run --config %t/devproxy/caddy.json";
          Restart = "on-failure";
          RestartSec = 2;
          RuntimeDirectory = "devproxy";
          RuntimeDirectoryPreserve = "yes";
        };
        Install.WantedBy = [ "default.target" ];
      };

      systemd.user.services.devproxy-watch = {
        Unit = {
          Description = "Name and route the web UIs running in this machine";
          BindsTo = [ "devproxy.service" ];
          After = [ "devproxy.service" ];
        };
        Service = {
          ExecStart = "${devproxy}/bin/devproxy watch";
          Restart = "always";
          RestartSec = 2;
          # git to name things after repos and branches; herdr for notifications.
          Environment = "PATH=${lib.makeBinPath [ pkgs.git ]}:/etc/profiles/per-user/${user}/bin";
        };
        Install.WantedBy = [ "default.target" ];
      };
    };
  };
}
