# A Parallels VM on a Mac, if you use Parallels rather than UTM. Install with
# `make vm/bootstrap0 NIXBLOCK=/dev/sda` (see README), and add it to flake.nix.
{
  networking.hostName = "parallels";
  devEnv.platform = "parallels";

  devEnv.user.home.devEnv.languages = {
    go.enable = true;
    node.enable = true;
    playwright.enable = true;
  };
}
