# Evaluation tests for the Mac: lib.mkHome and homeModules.default on
# aarch64-darwin. flake.nix runs them as checks.<system>.mac on every system,
# so Linux CI catches macOS breakage too. Nothing for darwin is built, only
# evaluated. Returns lib.runTests' failures: an empty list when all pass.
{ self, lib }:

let
  mk = extra: self.lib.mkHome {
    system = "aarch64-darwin";
    modules = [ ../templates/default/users/me.nix ../templates/default/hosts/mac.nix ] ++ extra;
  };
  ex = self.homeConfigurations.example-mac.config;

  throws = x: !(builtins.tryEval (builtins.deepSeq x x)).success;
  drvPath = hm: builtins.unsafeDiscardStringContext hm.activationPackage.drvPath;

  # An unfree package, to check that devEnv.unfreePackages reaches the Mac's pkgs.
  unfree = { devEnv.user.home = { pkgs, ... }: { home.packages = [ pkgs._1password-cli ]; }; };
in
lib.runTests {
  testUsername = {
    expr = ex.home.username;
    expected = "me";
  };
  testHomeDirectory = {
    expr = ex.home.homeDirectory;
    expected = "/Users/me";
  };
  testConfigDir = {
    expr = ex.devEnv.configDir;
    expected = "/Users/me/dev-env";
  };
  testLinuxHome = {
    expr = (self.lib.mkHome {
      system = "aarch64-linux";
      modules = [ ../templates/default/users/me.nix ];
    }).config.home.homeDirectory;
    expected = "/home/me";
  };
  # NixOS-only devEnv settings in a shared user file are accepted and ignored.
  testIgnoresVmOptions = {
    expr = (mk [{
      devEnv = {
        timeZone = "Europe/Stockholm";
        proxy.enable = true;
        user.sshKeys = [ "ssh-ed25519 AAAA x" ];
      };
    }]).config.home.username;
    expected = "me";
  };
  # A NixOS option means a NixOS-only host file was passed.
  testRejectsNixos = {
    expr = throws (mk [{ networking.hostName = "x"; }]).config.home.username;
    expected = true;
  };
  testUserHome = {
    expr = (mk [{ devEnv.user.home.home.sessionVariables.DEVENV_TEST = "1"; }])
      .config.home.sessionVariables.DEVENV_TEST;
    expected = "1";
  };
  testNameOverride = {
    expr = (mk [ ({ lib, ... }: { devEnv.user.name = lib.mkForce "me.x"; }) ])
      .config.home.homeDirectory;
    expected = "/Users/me.x";
  };
  testUnfreeDenied = {
    expr = throws (drvPath (mk [ unfree ]));
    expected = true;
  };
  testUnfreeAllowed = {
    expr = throws (drvPath (mk [ unfree { devEnv.unfreePackages = [ "1password-cli" ]; } ]));
    expected = false;
  };
  testExampleEvaluates = {
    expr = lib.hasSuffix "home-manager-generation.drv" (drvPath self.homeConfigurations.example-mac);
    expected = true;
  };
}
