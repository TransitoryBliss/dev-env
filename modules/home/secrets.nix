# devEnv.secrets: environment variables from a sops-encrypted file in the
# private config (API keys for agent tools, e.g. LINEAR_API_KEY).
#
# The encrypted file is committed; each machine decrypts it with its own age
# key, which never leaves the machine. sops-nix decrypts on activation into
# $XDG_RUNTIME_DIR (tmpfs) and links each secret under ~/.config/sops-nix.
{ inputs }:
{ config, lib, pkgs, ... }:

let
  cfg = config.devEnv.secrets;
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
      type = lib.types.attrsOf lib.types.str;
      default = { };
      example = { LINEAR_API_KEY = "linear_api_key"; };
      description = "Environment variables to export, as variable name -> key in sopsFile.";
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
        secrets = lib.genAttrs (lib.unique (lib.attrValues cfg.env)) (_: { });
      };

      # In .zshenv rather than home.sessionVariables, so herdr panes see them
      # (see AGENTS.md). Read at shell start, not at build time: the values
      # never reach the store. A secret that failed to decrypt is skipped.
      programs.zsh.envExtra = lib.concatStrings (lib.mapAttrsToList (var: key:
        let path = lib.escapeShellArg config.sops.secrets.${key}.path; in ''
          [[ -r ${path} ]] && export ${var}="$(<${path})"
        '') cfg.env);
    })
  ];
}
