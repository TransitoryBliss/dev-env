# A UTM VM on a Mac (Apple Virtualization). Install with `make vm/bootstrap0`
# (see README). For Parallels instead, use hosts/parallels.nix.
{
  networking.hostName = "vm";
  devEnv.platform = "utm";

  devEnv.user.home.devEnv.languages = {
    go.enable = true;
    node.enable = true;
    playwright.enable = true;
  };
}
