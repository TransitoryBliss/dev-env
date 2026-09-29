# VMware Fusion VM on Apple Silicon. Fusion gives ARM Linux guests an NVMe
# disk (/dev/nvme0n1) and a vmxnet3 network card. The rest of the VM setup
# (boot, disks, network, SSH) is in vm.nix.
{ config, lib, ... }:

{
  config = lib.mkIf (config.devEnv.platform == "vmware") {
    # open-vm-tools: reports the guest's IP to Fusion, clean shutdown from the UI.
    virtualisation.vmware.guest.enable = true;

    boot.initrd.availableKernelModules = [ "nvme" "ahci" "xhci_pci" "usbhid" "sr_mod" ];

    # Fusion's EFI console can't switch modes; systemd-boot otherwise prints
    # "error switching console mode" at every boot.
    boot.loader.systemd-boot.consoleMode = "0";
  };
}
