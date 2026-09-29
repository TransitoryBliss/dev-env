# UTM VM on Apple Silicon, with the Apple Virtualization backend (not QEMU).
# The disk is virtio (/dev/vda). The rest of the VM setup (boot, disks,
# network, SSH) is in vm.nix.
{ config, lib, ... }:

let
  cfg = config.devEnv.utm;
in
{
  options.devEnv.utm.rosetta = lib.mkOption {
    type = lib.types.bool;
    default = false;
    description = ''
      Run x86_64-linux binaries through Rosetta. Tick "Enable Rosetta" in the
      VM's UTM settings first: NixOS mounts UTM's "rosetta" share without
      `nofail`, so without it the VM doesn't finish booting.
    '';
  };

  config = lib.mkIf (config.devEnv.platform == "utm") {
    boot.initrd.availableKernelModules = [ "virtio_pci" "virtio_blk" "virtio_net" "xhci_pci" "usbhid" ];

    virtualisation.rosetta.enable = cfg.rosetta;
  };
}
