# devEnv.mcp: MCP servers for pi (its built-in MCP support), everywhere and per org.
#
#   devEnv.mcp = {
#     servers.context7.url = "https://mcp.context7.com/mcp";
#     scopes."github.com/some-org" = {
#       inheritGlobal = false;          # only this org's servers in its repos
#       servers.notion = { url = "https://mcp.notion.com/mcp"; oauth = true; };
#     };
#   };
#
# pi reads ~/.pi/agent/mcp.json and the cwd's .pi/mcp.json (trusted projects
# only), nothing per org. So the servers go in one generated file, and the
# mcp-pi.ts extension registers (pi.registerMcpServer) the ones that apply to
# the session's directory: the global servers, plus a scope's when the cwd is
# under <host/owner> in one of devEnv.scopeRoots (~/source, and the worktree
# root `wt` mirrors it into). With inheritGlobal = false only the scope's.
#
# ~/.pi/agent/mcp.json stays pi's own (`pi mcp add`, /mcp toggles), and a
# server defined there wins over a registered one of the same name. Registered
# servers don't show in the shell's `pi mcp list` (it loads no extensions);
# /mcp inside pi lists them, signs in and reconnects.
#
# OAuth: pi's callback listens on a random port unless the server has a fixed
# one. `oauth = true` sets callbackPort, which `make vm/ssh` forwards, so a
# browser on the host can finish the flow. Secrets: use "${VAR}" in env/headers
# with devEnv.secrets; pi expands them when it connects.
{ config, lib, pkgs, ... }:

let
  cfg = config.devEnv.mcp;
  jsonFormat = pkgs.formats.json { };

  serverType = lib.types.submodule {
    freeformType = jsonFormat.type;
    options.oauth = lib.mkOption {
      type = lib.types.either lib.types.bool (lib.types.attrsOf jsonFormat.type);
      default = false;
      description = ''
        Browser OAuth on the fixed callback port. `true`, or pi `oauth` settings
        (clientId, scope, clientName, ...) to merge over the callbackPort.
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
        description = "Whether devEnv.mcp.servers are also loaded here. false leaves them out in this scope.";
      };
    };
  };

  # An `mcpServers` entry as pi takes it.
  piServer = server:
    removeAttrs server [ "oauth" ]
    // lib.optionalAttrs (server.oauth != false) {
      oauth = { inherit (cfg) callbackPort; } // lib.optionalAttrs (lib.isAttrs server.oauth) server.oauth;
    };

  serversFile = jsonFormat.generate "dev-env-mcp.json" {
    roots = config.devEnv.scopeRoots;
    servers = lib.mapAttrs (_: piServer) cfg.servers;
    scopes = lib.mapAttrs (_: scope: {
      inherit (scope) inheritGlobal;
      servers = lib.mapAttrs (_: piServer) scope.servers;
    }) cfg.scopes;
  };

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
      description = "MCP servers loaded everywhere, as `mcpServers` entries plus `oauth`.";
    };
    scopes = lib.mkOption {
      type = lib.types.attrsOf scopeType;
      default = { };
      description = ''Servers for repos (and their `wt` worktrees) under a "host/owner" prefix in ~/source, e.g. "github.com/some-org".'';
    };
  };

  config = lib.mkIf enabled {
    # The extension reads its store path; the link is for people looking.
    xdg.configFile."dev-env/mcp.json".source = serversFile;
    home.file.".pi/agent/extensions/dev-env-mcp.ts".source =
      pkgs.replaceVars ./mcp-pi.ts { inherit serversFile; };
  };
}
