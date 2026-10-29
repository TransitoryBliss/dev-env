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

  # The same template user on NixOS, to check that macOS fixes stay macOS-only.
  vmHome = self.nixosConfigurations.example-vm.config.home-manager.users.me;
  lastLine = s: lib.last (lib.splitString "\n" (lib.trim s));
  # Whether a home module, enabled on macOS, has a failing assertion whose message
  # starts with `prefix`. The module is called directly: home-manager throws on a
  # failed assertion before its message can be read, and tryEval hides messages.
  # Its config must be `lib.mkIf cfg.enable { ... }`.
  failsOnMac = file: option: prefix:
    let
      module = import file {
        inherit lib;
        pkgs = self.inputs.nixpkgs.legacyPackages.aarch64-darwin;
        config = lib.recursiveUpdate (lib.setAttrByPath [ "devEnv" option "enable" ] true) {
          home.homeDirectory = "/Users/me";
        };
      };
    in
    lib.any (a: lib.hasPrefix prefix a.message && !a.assertion) (module.config.content.assertions or [ ]);
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

  # homeModules.default on macOS.
  testWtGcInterval = {
    expr = ex.launchd.agents.wt-gc.config.StartInterval or null;
    expected = 3600;
  };
  testWtGcArgs = {
    expr = lib.last (ex.launchd.agents.wt-gc.config.ProgramArguments or [ null ]);
    expected = "--auto";
  };
  # `wt done` detaches its cleanup with setsid. The wt function runs with the
  # user's PATH, which has no setsid on macOS, so wt.zsh gets util-linux's by path.
  testWtSetsidByPath = {
    expr = builtins.match ".*_WT_SETSID='?/nix/store/[^ ']*/bin/setsid.*"
      (lib.replaceStrings [ "\n" ] [ " " ] ex.programs.zsh.initContent) != null;
    expected = true;
  };
  testWtNoBareSetsid = {
    expr = lib.hasInfix " setsid -f" (builtins.readFile ../modules/home/wt.zsh);
    expected = false;
  };
  testMdNoXdgOpen = {
    expr = lib.hasInfix "xdg-open" ex.programs.zsh.initContent;
    expected = false;
  };
  testMdLinuxUnchanged = {
    expr = lib.hasInfix "xdg-open" vmHome.programs.zsh.initContent;
    expected = true;
  };
  testPathFixLast = {
    expr = lastLine ex.programs.zsh.initContent;
    expected = "typeset -U path";
  };
  # Also before Oh My Zsh: in nested shells its plugins (direnv, ...) look for
  # their tools while Nix isn't on PATH yet.
  testPathFixBeforeOhMyZsh = {
    expr =
      let
        s = ex.programs.zsh.initContent;
        idx = re: builtins.stringLength (builtins.head (builtins.split re s));
        omz = idx "oh-my-zsh[.]sh";
      in
      idx "/nix/var/nix/profiles/default/bin [$]path" < omz && omz < builtins.stringLength s;
    expected = true;
  };
  testPathFixDarwinOnly = {
    expr = lib.hasInfix "/nix/var/nix/profiles/default/bin \$path" vmHome.programs.zsh.initContent;
    expected = false;
  };
  testPsmLinuxOnly = {
    expr = failsOnMac ../modules/home/session-manager.nix "sessionManager" "devEnv.sessionManager is Linux-only";
    expected = true;
  };
  testBackupLinuxOnly = {
    expr = failsOnMac ../modules/home/backup.nix "backup" "devEnv.backup is Linux-only";
    expected = true;
  };
}
