# My dev-env

Private config for [dev-env](https://github.com/TransitoryBliss/dev-env). The shared modules live
there; this repo holds only what's specific to me and my machines.

| Path                | What                                                         |
| ------------------- | ------------------------------------------------------------ |
| `flake.nix`         | One `nixosConfigurations` entry per machine                  |
| `users/me.nix`      | Username, SSH login keys, git identities, time zone          |
| `hosts/*.nix`       | Per-machine: platform, hostname, language flags              |
| `nvim/`             | Neovim config, linked to `~/.config/nvim`                    |
| `herdr/config.toml` | herdr config, linked to `~/.config/herdr/config.toml`        |
| `Makefile`          | Install and rebuild helpers                                  |

## First steps

1. Fill in `users/me.nix`. Rename it if you like, and update the imports in `flake.nix`.
2. Set `NIXUSER ?=` in the `Makefile` to your username.
3. Keep the hosts you need in `hosts/` and `flake.nix`.

## Parallels VM on a Mac

1. Download the NixOS **minimal ISO** for your Mac's architecture from <https://nixos.org/download>.
2. In Parallels, create a VM from the ISO (e.g. 4+ CPUs, 8+ GB RAM, 64+ GB disk).
3. In the VM console, run `sudo passwd root` (a temporary password for the installer), then
   `ip addr` to get the IP and `lsblk` to see the disk (`sda` or `nvme0n1`).
4. From the Mac, in this repo (**this wipes the VM disk**):
   ```sh
   make vm/bootstrap0 NIXADDR=<ip> NIXBLOCK=/dev/sda
   ```
5. After the reboot: `make vm/bootstrap NIXADDR=<ip>`.
6. Connect with `make vm/ssh NIXADDR=<ip>`, then continue with "Inside the machine" below.

After changes: `make vm/bootstrap NIXADDR=<ip>`. Updates: `make vm/update NIXADDR=<ip>`.

## WSL2 on Windows

1. Install [NixOS-WSL](https://github.com/nix-community/NixOS-WSL) and open it from Windows Terminal.
2. Get this repo into the distro at `~/dev-env` (the default `devEnv.configDir`). For example,
   clone it over HTTPS, or copy it from Windows (`/mnt/c/...`).
3. `cd ~/dev-env && sudo nixos-rebuild switch --flake .#wsl`, then close and reopen the terminal.

After changes: `make switch HOST=wsl`. Updates: `nix flake update`, then `make switch HOST=wsl`.

## Inside the machine

1. `devenv-keys` creates one SSH key per git account and prints where to register each one.
2. `make agents/setup` installs the agent add-ons that use their own installers
   (plannotator's pi extension, the Claude Code provider for pi, rtk's Claude Code hook,
   herdr-annotate).
3. Log in to `pi` and/or `claude`.

## Developing the base

To try changes to a local checkout of dev-env before publishing them:

```sh
make vm/bootstrap NIXADDR=<ip> DEV_ENV=../dev-env
```
