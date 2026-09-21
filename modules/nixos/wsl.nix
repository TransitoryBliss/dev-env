# WSL2 on Windows, via NixOS-WSL. No bootloader, disks or SSH server: you open
# the distro from Windows Terminal. WSL forwards localhost ports to Windows, so
# plannotator's review UI opens in the Windows browser.
{ config, lib, pkgs, ... }:

{
  config = lib.mkIf (config.devEnv.platform == "wsl") {
    wsl = {
      enable = true;
      defaultUser = config.devEnv.user.name;
    };

    # Open URLs in the Windows default browser, so previews (`md`) and login
    # links (claude, gh) open by themselves. explorer.exe always exits 1.
    environment.systemPackages = [
      (pkgs.writeShellScriptBin "xdg-open" ''
        /mnt/c/Windows/explorer.exe "$1" || true
      '')
    ];
  };
}
