# The Mac itself, without a VM: a standalone home-manager config (the base's
# lib.mkHome), applied with `make switch` on the Mac. Only devEnv.user.* and
# devEnv.configDir matter here; NixOS-only settings in users/me.nix (timeZone,
# proxy, sshKeys) are ignored. Not available on macOS: sessionManager, backup.
{ lib, ... }:
{
  # Your macOS login (`whoami`), if it differs from the name in users/me.nix.
  # devEnv.user.name = lib.mkForce "me.surname";

  # /Users/<name> by default.
  # devEnv.user.homeDirectory = "/Users/me";
}
