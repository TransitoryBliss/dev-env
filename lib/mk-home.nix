# lib.mkHome: a standalone home-manager config from the same user and host
# files lib.mkHost takes, for a machine that isn't NixOS (a Mac). Two steps:
#
# 1. The files are evaluated against only the devEnv options a home needs:
#    user.name, user.home, user.homeDirectory, configDir, unfreePackages. Any
#    other devEnv setting (timeZone, proxy, user.sshKeys, ...) is accepted and
#    ignored, so one users/<you>.nix serves a VM and a Mac. A NixOS option such
#    as networking.hostName fails with "option does not exist": a NixOS-only
#    host file was passed.
# 2. devEnv.user.home, with homeModules.default, becomes a home-manager
#    configuration on this flake's pinned nixpkgs.
{ inputs, self }:
{ system, modules }:

let
  inherit (inputs.nixpkgs) lib;
  inherit (lib) types mkOption;
  isDarwin = lib.hasSuffix "-darwin" system;

  # Unknown settings are kept (and unused) instead of being errors.
  freeform = types.attrsOf types.anything;

  devEnvOptions = {
    options.devEnv = mkOption {
      default = { };
      description = "A host's devEnv settings; mkHome uses the ones declared here.";
      type = types.submodule ({ config, ... }: {
        freeformType = freeform;
        options = {
          user = mkOption {
            default = { };
            type = types.submodule ({ config, ... }: {
              freeformType = freeform;
              options = {
                name = mkOption {
                  type = types.str;
                  description = "Login name.";
                };
                homeDirectory = mkOption {
                  type = types.str;
                  default = "${if isDarwin then "/Users" else "/home"}/${config.name}";
                  defaultText = "/Users/<name> on macOS, /home/<name> elsewhere";
                  description = "Home directory (mkHome only; NixOS derives it).";
                };
                home = mkOption {
                  type = types.deferredModule;
                  default = { };
                  description = "Home-manager config for the user.";
                };
              };
            });
          };
          configDir = mkOption {
            type = types.str;
            default = "${config.user.homeDirectory}/dev-env";
            description = "Checkout of the private config; nvim/ and herdr/ in it are linked into ~/.config.";
          };
          unfreePackages = mkOption {
            type = types.listOf types.str;
            default = [ ];
            description = "Unfree packages to allow, by name.";
          };
        };
      });
    };

    # For host files that take `pkgs`. Packages for the home belong in
    # devEnv.user.home, where home-manager's pkgs (with unfreePackages) apply.
    config._module.args.pkgs = inputs.nixpkgs.legacyPackages.${system};
  };

  dev = (lib.evalModules { modules = [ devEnvOptions ] ++ modules; }).config.devEnv;
in
inputs.home-manager.lib.homeManagerConfiguration {
  pkgs = import inputs.nixpkgs {
    inherit system;
    config.allowUnfreePredicate = pkg: builtins.elem (lib.getName pkg) dev.unfreePackages;
  };
  modules = [
    self.homeModules.default
    dev.user.home
    {
      home.username = dev.user.name;
      home.homeDirectory = dev.user.homeDirectory;
      devEnv.configDir = dev.configDir;
    }
  ];
}
