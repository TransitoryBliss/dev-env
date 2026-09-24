# Local reverse proxy: one localhost port, one hostname per service
# (http://<name>.localhost:<port>). Reach it through an SSH tunnel for that one
# port (`make vm/ssh`), or directly from Windows on WSL. Browsers resolve
# *.localhost to 127.0.0.1 by themselves, so no DNS is needed.
#
# Besides routing, Caddy guards the backends: it only answers the hostnames it
# knows (no DNS rebinding), rejects requests whose Origin is another site
# (browser drive-by requests, including WebSocket upgrades), sets its own
# X-Forwarded-For, and strips CORS headers the backends send.
{ config, lib, ... }:

let
  cfg = config.devEnv.proxy;
  hm = config.home-manager.users.${config.devEnv.user.name};

  vhost = name: backendPort:
    let origin = "http://${name}.localhost:${toString cfg.port}";
    in {
      name = origin;
      value = {
        listenAddresses = [ "127.0.0.1" "::1" ];
        extraConfig = ''
          @foreign {
            header Origin *
            not header Origin ${origin}
          }
          respond @foreign "Forbidden origin" 403

          reverse_proxy 127.0.0.1:${toString backendPort} {
            header_down -Access-Control-Allow-Origin
          }
        '';
      };
    };
in
{
  options.devEnv.proxy = {
    enable = lib.mkEnableOption "the local reverse proxy (Caddy) for web UIs in the machine";
    port = lib.mkOption {
      type = lib.types.port;
      default = 8090;
      description = "Localhost port the proxy listens on. Forward this one port to reach every service.";
    };
    services = lib.mkOption {
      type = lib.types.attrsOf lib.types.port;
      default = { };
      example = { grafana = 3000; };
      description = "Services to route, as hostname prefix -> localhost port: `psm` becomes http://psm.localhost:<port>.";
    };
  };

  config = lib.mkIf cfg.enable {
    devEnv.proxy.services.psm =
      lib.mkIf hm.devEnv.sessionManager.enable hm.devEnv.sessionManager.port;

    services.caddy = {
      enable = true;
      # Plain HTTP only: *.localhost is already a secure context in browsers.
      globalConfig = ''
        auto_https off
      '';
      virtualHosts = lib.mapAttrs' vhost cfg.services;
    };
  };
}
