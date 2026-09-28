# devEnv.mcp: MCP servers for pi (pi-mcp-adapter), everywhere and per org.
#
#   devEnv.mcp = {
#     servers.context7.url = "https://mcp.context7.com/mcp";
#     scopes."github.com/some-org" = {
#       inheritGlobal = false;          # only this org's servers in its repos
#       servers.notion = { url = "https://mcp.notion.com/mcp"; oauth = true; };
#     };
#   };
#
# `servers` go in ~/.config/mcp/mcp.json. A scope's servers go in
# <root>/<host/owner>/.mcp.json for each devEnv.scopeRoots (~/source and the
# worktree root `wt` mirrors it into). settings.ancestorConfigRoots is the home
# directory, so pi also reads .mcp.json files in the directories between ~ and
# the cwd, and loads a scope's file anywhere below it (repos included; a repo's
# own .mcp.json still wins). The root is ~ rather than each scope's directory
# because pi-mcp-adapter warns, several times per start, about every root that
# doesn't contain the cwd. Pi-only fields (oauth, and the `disabled` flags that
# hide global servers) go in the scope's .pi/mcp.json, so .mcp.json stays in
# the format other tools read.
#
# OAuth: pi-mcp-adapter's callback listens on a random port unless the server
# has a fixed redirectUri. `oauth = true` sets one on callbackPort, which
# `make vm/ssh` forwards, so a browser on the host can finish the flow.
#
# The files are read-only store links: add servers here, not with
# `/mcp setup` or `mcp install` into them. ~/.pi/agent/mcp.json is left alone
# for pi's own writes. Secrets: use "${VAR}" in env/headers with devEnv.secrets.
{ config, lib, pkgs, ... }:

let
  cfg = config.devEnv.mcp;
  jsonFormat = pkgs.formats.json { };
  redirectUri = "http://127.0.0.1:${toString cfg.callbackPort}/callback";

  serverType = lib.types.submodule {
    freeformType = jsonFormat.type;
    options.oauth = lib.mkOption {
      type = lib.types.either lib.types.bool (lib.types.attrsOf jsonFormat.type);
      default = false;
      description = ''
        Browser OAuth on the fixed callback port. `true`, or pi-mcp-adapter
        `oauth` settings (clientId, scope, ...) to merge over the redirectUri.
      '';
    };
  };

  scopeType = lib.types.submodule {
    options = {
      servers = lib.mkOption {
        type = lib.types.attrsOf serverType;
        default = { };
        description = "Servers for repos under this owner.";
      };
      inheritGlobal = lib.mkOption {
        type = lib.types.bool;
        default = true;
        description = "Whether devEnv.mcp.servers are also loaded here. false disables them in this scope.";
      };
    };
  };

  # The server as other MCP clients know it, and pi's additions to it.
  standard = server: removeAttrs server [ "oauth" ];
  piOverlay = server:
    if server.oauth == false then { }
    else { oauth = { inherit redirectUri; } // lib.optionalAttrs (lib.isAttrs server.oauth) server.oauth; };

  full = server: standard server // piOverlay server;

  scopePiServers = scope:
    lib.optionalAttrs (!scope.inheritGlobal) (lib.mapAttrs (_: _: { disabled = true; }) cfg.servers)
    // lib.filterAttrs (_: v: v != { }) (lib.mapAttrs (_: piOverlay) scope.servers);

  enabled = cfg.servers != { } || cfg.scopes != { };
in
{
  options.devEnv.mcp = {
    callbackPort = lib.mkOption {
      type = lib.types.port;
      default = 19876;
      description = "Localhost port for OAuth callbacks. `make vm/ssh` forwards it (MCP_OAUTH_PORT there).";
    };
    servers = lib.mkOption {
      type = lib.types.attrsOf serverType;
      default = { };
      description = "MCP servers loaded everywhere, as .mcp.json `mcpServers` entries plus `oauth`.";
    };
    scopes = lib.mkOption {
      type = lib.types.attrsOf scopeType;
      default = { };
      description = ''Servers for repos (and their `wt` worktrees) under a "host/owner" prefix in ~/source, e.g. "github.com/some-org".'';
    };
  };

  config = lib.mkIf enabled {
    xdg.configFile."mcp/mcp.json".source = jsonFormat.generate "mcp.json" {
      mcpServers = lib.mapAttrs (_: full) cfg.servers;
      # Absolute: the adapter accepts "~/..." but not a bare "~".
      settings.ancestorConfigRoots = lib.optionals (cfg.scopes != { }) [ config.home.homeDirectory ];
    };

    # Under every scope root: ~/source, and the worktree root `wt` mirrors it into.
    home.file = lib.concatMapAttrs (owner: scope: lib.mergeAttrsList (map (root:
      let dir = lib.removePrefix "${config.home.homeDirectory}/" "${root}/${owner}"; in {
        "${dir}/.mcp.json".source = jsonFormat.generate "mcp.json" {
          mcpServers = lib.mapAttrs (_: standard) scope.servers;
        };
        "${dir}/.pi/mcp.json".source = jsonFormat.generate "pi-mcp.json" {
          mcpServers = scopePiServers scope;
        };
      }) config.devEnv.scopeRoots)) cfg.scopes;

    # Used for servers with a pre-registered clientId; kept in step with callbackPort.
    home.sessionVariables.MCP_OAUTH_CALLBACK_PORT = toString cfg.callbackPort;
    programs.zsh.envExtra = ''
      export MCP_OAUTH_CALLBACK_PORT=${toString cfg.callbackPort}
    '';
  };
}
