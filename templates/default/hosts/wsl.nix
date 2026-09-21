# WSL2 on Windows. Install NixOS-WSL, clone this repo inside it, then
# `sudo nixos-rebuild switch --flake .#wsl` (see README).
{
  networking.hostName = "wsl";
  devEnv.platform = "wsl";

  devEnv.user.home.devEnv.languages = {
    go.enable = true;
    node.enable = true;
  };
}
