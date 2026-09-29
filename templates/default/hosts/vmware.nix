# A VMware Fusion VM on a Mac, if you use Fusion rather than UTM. Install with
# `make vm/bootstrap0 NIXBLOCK=/dev/nvme0n1` (see README), and add it to flake.nix.
{
  networking.hostName = "vmware";
  devEnv.platform = "vmware";

  devEnv.user.home.devEnv.languages = {
    go.enable = true;
    node.enable = true;
    playwright.enable = true;
  };
}
