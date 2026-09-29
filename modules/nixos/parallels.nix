# Parallels Desktop VM (Apple Silicon or Intel). The rest of the VM setup
# (boot, disks, network, SSH) is in vm.nix.
{ config, lib, ... }:

{
  config = lib.mkIf (config.devEnv.platform == "parallels") {
    hardware.parallels.enable = true;
    devEnv.unfreePackages = [ "prl-tools" ];

    boot.initrd.availableKernelModules = [ "xhci_pci" "nvme" "usbhid" "sr_mod" ];
  };
}
