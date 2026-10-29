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
      # VMware Fusion instead of UTM:
      # vmware = dev-env.lib.mkHost {
      #   system = "aarch64-linux";
      #   modules = [ ./users/me.nix ./hosts/vmware.nix ];
      # };
      wsl = dev-env.lib.mkHost {
        system = "x86_64-linux";
        modules = [ ./users/me.nix ./hosts/wsl.nix ];
      };
    };

    # The Mac itself, without a VM (home directory only). The name is MAC_HOST in the Makefile.
    homeConfigurations = {
      mac = dev-env.lib.mkHome {
        system = "aarch64-darwin"; # Apple Silicon
        modules = [ ./users/me.nix ./hosts/mac.nix ];
      };
    };
  };
}
