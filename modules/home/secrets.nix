# devEnv.secrets: environment variables from a sops-encrypted file in the
# private config (API keys for agent tools, e.g. LINEAR_API_KEY), everywhere
# and per org.
#
#   devEnv.secrets = {
#     sopsFile = ../secrets.yaml;
#     env.LINEAR_API_KEY = "linear_api_key";
#     scopes."github.com/some-org".env.LINEAR_API_KEY = "some_org_linear_api_key";
#   };
#
# The encrypted file is committed; each machine decrypts it with its own age
# key, which never leaves the machine. sops-nix decrypts on activation into
# $XDG_RUNTIME_DIR (tmpfs) and links each secret under ~/.config/sops-nix.
#
# A scope applies under <host/owner> in every devEnv.scopeRoots (~/source, and
# the worktree root `wt` mirrors it into), like git.overrides and mcp.scopes:
# its variables replace the global ones there. The check runs at
# every shell start (.zshenv) and on every `cd` in an interactive shell, so a
# program gets the keys of the directory it was started in.
{ inputs }:
{ config, lib, pkgs, ... }:

let
  cfg = config.devEnv.secrets;

  envType = lib.types.attrsOf lib.types.str;

  scopeType = lib.types.submodule {
    options.env = lib.mkOption {
      type = envType;
      default = { };
      description = "Variables to export under this owner, replacing the global ones: variable name -> key in sopsFile.";
    };
  };

  allEnvs = [ cfg.env ] ++ lib.mapAttrsToList (_: scope: scope.env) cfg.scopes;
  allVars = lib.unique (lib.concatMap lib.attrNames allEnvs);
  allKeys = lib.unique (lib.concatMap lib.attrValues allEnvs);

  # A secret that failed to decrypt leaves its variable unset, rather than
  # falling back to another scope's value.
  exports = env: lib.concatStrings (lib.mapAttrsToList (var: key:
    let path = lib.escapeShellArg config.sops.secrets.${key}.path; in ''
      [[ -r ${path} ]] && export ${var}="$(<${path})"
    '') env);

  # Longest prefix first: `case` takes the first match.
  scopeOrder = lib.sort (a: b: lib.stringLength a > lib.stringLength b) (lib.attrNames cfg.scopes);

  scopeCase = owner:
    let env = cfg.scopes.${owner}.env; in ''
      ${lib.concatMapStringsSep "|" (root: "${lib.escapeShellArg "${root}/${owner}"}/*") config.devEnv.scopeRoots})
        unset ${lib.concatStringsSep " " (lib.attrNames env)}
      ${exports env}  ;;
    '';
in
{
  imports = [ inputs.sops-nix.homeManagerModules.sops ];

  options.devEnv.secrets = {
    sopsFile = lib.mkOption {
      type = lib.types.nullOr lib.types.path;
      default = null;
      example = lib.literalExpression "../secrets.yaml";
      description = "sops-encrypted YAML file in the private config. Nothing is decrypted while this is null.";
    };

    ageKeyFile = lib.mkOption {
      type = lib.types.str;
      default = "${config.xdg.configHome}/sops/age/keys.txt";
      description = "This machine's age private key. Outside the store and outside git; also where the sops CLI looks by default.";
    };

    env = lib.mkOption {
      type = envType;
      default = { };
      example = { LINEAR_API_KEY = "linear_api_key"; };
      description = "Environment variables to export, as variable name -> key in sopsFile.";
    };

    scopes = lib.mkOption {
      type = lib.types.attrsOf scopeType;
      default = { };
      example = lib.literalExpression ''{ "github.com/some-org".env.LINEAR_API_KEY = "some_org_linear_api_key"; }'';
      description = ''Variables for directories under a "host/owner" prefix in ~/source, e.g. "github.com/some-org".'';
    };
  };

  config = lib.mkMerge [
    # Always installed, so a machine can create its key and edit the file
    # before any secret is declared.
    { home.packages = [ pkgs.sops pkgs.age ]; }

    (lib.mkIf (cfg.sopsFile != null) {
      sops = {
        defaultSopsFile = cfg.sopsFile;
        age.keyFile = cfg.ageKeyFile;
        secrets = lib.genAttrs allKeys (_: { });
      };

      # In .zshenv rather than home.sessionVariables, so herdr panes see them
      # (see AGENTS.md). Read at shell start, not at build time: the values
      # never reach the store.
      programs.zsh.envExtra = ''
        _dev_env_secrets() {
          unset ${lib.concatStringsSep " " allVars}
        ${exports cfg.env}${lib.optionalString (cfg.scopes != { }) ''
          case "$PWD/" in
          ${lib.concatMapStrings scopeCase scopeOrder}esac
        ''}}
        _dev_env_secrets
      '';

      # Switch keys on `cd`.
      programs.zsh.initContent = lib.mkIf (cfg.scopes != { }) ''
        autoload -Uz add-zsh-hook
        add-zsh-hook chpwd _dev_env_secrets
      '';
    })
  ];
}
