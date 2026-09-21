# A Parallels VM on a Mac. Install with `make vm/bootstrap0` (see README).
{
  networking.hostName = "vm";
  devEnv.platform = "parallels";

  devEnv.user.home.devEnv.languages = {
    go.enable = true;
    node.enable = true;
    playwright.enable = true;
  };
}
