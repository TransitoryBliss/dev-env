# Parallels Desktop VM (Apple Silicon or Intel). The disk layout matches the
# template's `make vm/bootstrap0`: filesystems labelled "nixos" and "boot".
{ config, lib, ... }:

{
  config = lib.mkIf (config.devEnv.platform == "parallels") {
    hardware.parallels.enable = true;
    devEnv.unfreePackages = [ "prl-tools" ];

    boot.initrd.availableKernelModules = [ "xhci_pci" "nvme" "usbhid" "sr_mod" ];
    boot.loader.systemd-boot.enable = true;
    boot.loader.efi.canTouchEfiVariables = true;

    fileSystems."/" = {
      device = "/dev/disk/by-label/nixos";
      fsType = "ext4";
    };

    fileSystems."/boot" = {
      device = "/dev/disk/by-label/boot";
      fsType = "vfat";
      options = [ "fmask=0077" "dmask=0077" ];
    };

    networking.networkmanager.enable = true;
    users.users.${config.devEnv.user.name}.extraGroups = [ "networkmanager" ];

    # You work in the VM over SSH from the host. Key-only; sudo needs no password
    # since the VM is only reachable from the host.
    services.openssh = {
      enable = true;
      settings = {
        PasswordAuthentication = false;
        PermitRootLogin = "no";
      };
    };
  };
}
