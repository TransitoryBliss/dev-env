{
  description = "A NixOS development environment for AI-assisted coding, as reusable modules";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-26.05";
    # For fast-moving tools (pi, Claude Code) that lag behind in the stable release.
    nixpkgs-unstable.url = "github:NixOS/nixpkgs/nixos-unstable";
    # pi >= 0.86.1 (needed by pi-claude-code-provider) is only on master so far.
    # Once it reaches nixos-unstable, switch pi back and drop this input.
    nixpkgs-master.url = "github:NixOS/nixpkgs/master";

    home-manager = {
      url = "github:nix-community/home-manager/release-26.05";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    nixos-wsl = {
      url = "github:nix-community/NixOS-WSL/main";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    herdr.url = "github:herdrdev/herdr/v0.9.1";
  };

  outputs = inputs@{ self, nixpkgs, ... }: {
    # System-level module: user account, platform (parallels/wsl), and the
    # home-manager wiring that applies homeModules.default to devEnv.user.
    nixosModules.default = import ./modules/nixos { inherit inputs; };

    # Home-manager module: languages, editor, git identities, AI agents.
    homeModules.default = import ./modules/home { inherit inputs; };

    # Builds a host with this flake's pinned nixpkgs and modules.
    lib.mkHost = { system, modules }:
      nixpkgs.lib.nixosSystem {
        inherit system;
        modules = [ self.nixosModules.default ] ++ modules;
      };

    templates.default = {
      path = ./templates/default;
      description = "Private config for dev-env: your user and hosts";
    };

    # The template's hosts, built against this checkout; `nix flake check` evaluates them.
    nixosConfigurations = {
      example-vm = self.lib.mkHost {
        system = "aarch64-linux";
        modules = [ ./templates/default/users/me.nix ./templates/default/hosts/vm.nix ];
      };
      example-wsl = self.lib.mkHost {
        system = "x86_64-linux";
        modules = [ ./templates/default/users/me.nix ./templates/default/hosts/wsl.nix ];
      };
    };
  };
}
