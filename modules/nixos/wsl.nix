# WSL2 on Windows, via NixOS-WSL. No bootloader, disks or SSH server: you open
# the distro from Windows Terminal. WSL forwards localhost ports to Windows, so
# plannotator's review UI opens in the Windows browser.
{ config, lib, ... }:

{
  config = lib.mkIf (config.devEnv.platform == "wsl") {
    wsl = {
      enable = true;
      defaultUser = config.devEnv.user.name;
    };
  };
}
