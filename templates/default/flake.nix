{
  description = "My dev-env: private config on top of the shared base";

  inputs.dev-env.url = "github:TransitoryBliss/dev-env";

  outputs = { dev-env, ... }: {
    # One entry per machine. Names are what you pass as HOST= to make.
    nixosConfigurations = {
      vm = dev-env.lib.mkHost {
        system = "aarch64-linux"; # Apple Silicon
        modules = [ ./users/me.nix ./hosts/vm.nix ];
      };
      # Parallels instead of UTM:
      # parallels = dev-env.lib.mkHost {
      #   system = "aarch64-linux";
      #   modules = [ ./users/me.nix ./hosts/parallels.nix ];
      # };
      wsl = dev-env.lib.mkHost {
        system = "x86_64-linux";
        modules = [ ./users/me.nix ./hosts/wsl.nix ];
      };
    };
  };
}
