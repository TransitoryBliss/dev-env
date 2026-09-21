# System module. Everything personal comes in through devEnv.* options, set
# from a private config (see templates/default).
{ inputs }:
{ config, lib, pkgs, ... }:

let
  cfg = config.devEnv;
  user = cfg.user;
in
{
  imports = [
    inputs.home-manager.nixosModules.home-manager
    inputs.nixos-wsl.nixosModules.default
    ./parallels.nix
    ./wsl.nix
  ];

  options.devEnv = {
    platform = lib.mkOption {
      type = lib.types.enum [ "parallels" "wsl" ];
      description = "Where this host runs: a Parallels VM, or WSL2 on Windows.";
    };

    user = {
      name = lib.mkOption {
        type = lib.types.str;
        description = "Login name of the (single) user.";
      };
      sshKeys = lib.mkOption {
        type = lib.types.listOf lib.types.str;
        default = [ ];
        description = "Public keys allowed to SSH in as the user (VM platforms).";
      };
      home = lib.mkOption {
        type = lib.types.deferredModule;
        default = { };
        description = "Home-manager config for the user, e.g. devEnv.git and devEnv.languages.";
      };
    };

    configDir = lib.mkOption {
      type = lib.types.str;
      default = "/home/${user.name}/dev-env";
      description = ''
        Checkout of the private config inside the machine. nvim/ and
        herdr/config.toml in it are linked into ~/.config, editable in place.
      '';
    };

    timeZone = lib.mkOption {
      type = lib.types.str;
      default = "UTC";
    };

    unfreePackages = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [ ];
      description = "Unfree packages to allow, by name. Merged from all modules.";
    };
  };

  config = {
    nix.settings = {
      experimental-features = [ "nix-command" "flakes" ];
      trusted-users = [ "root" user.name ];
    };

    nixpkgs.config.allowUnfreePredicate = pkg: builtins.elem (lib.getName pkg) cfg.unfreePackages;

    time.timeZone = cfg.timeZone;
    i18n.defaultLocale = lib.mkDefault "en_US.UTF-8";

    users.users.${user.name} = {
      isNormalUser = true;
      uid = 1000;
      extraGroups = [ "wheel" "docker" ];
      shell = pkgs.zsh;
      openssh.authorizedKeys.keys = user.sshKeys;
    };
    security.sudo.wheelNeedsPassword = false;

    programs.zsh.enable = true;

    # Lets prebuilt Linux binaries (plannotator, herdr plugins, npm natives) run unpatched.
    programs.nix-ld.enable = true;

    virtualisation.docker.enable = true;

    # Ghostty terminfo so SSH sessions from Ghostty render correctly.
    environment.systemPackages = with pkgs; [ git gnumake vim curl ghostty.terminfo ];

    # Skip the host-key prompt on first clone.
    programs.ssh.knownHosts."github.com".publicKey =
      "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIOMqqnkVzrm0SdG6UOoqKLsabgH5C9okWi0dh2l9GKJl";

    home-manager = {
      useGlobalPkgs = true;
      useUserPackages = true;
      users.${user.name} = {
        imports = [ (import ../home { inherit inputs; }) user.home ];
        devEnv.configDir = cfg.configDir;
      };
    };

    system.stateVersion = lib.mkDefault "26.05";
  };
}
