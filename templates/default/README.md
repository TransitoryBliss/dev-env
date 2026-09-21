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

The first install renames NixOS-WSL's default user (`nixos`) to yours. NixOS-WSL requires
`nixos-rebuild boot` plus a restart for that, not `switch`.

1. Download `nixos.wsl` from the [NixOS-WSL releases](https://github.com/nix-community/NixOS-WSL/releases/latest)
   and install it from PowerShell: `wsl --install --from-file nixos.wsl`.
2. Open it (`wsl -d NixOS`). As the `nixos` user, fetch this repo with temporary tools:
   ```sh
   nix --extra-experimental-features "nix-command flakes" shell nixpkgs#git nixpkgs#gh
   gh auth login                                  # skip if this repo is public
   gh repo clone <you>/<this-repo> /tmp/dev-env
   ```
3. Build the new system for the next start (`wsl` is the host's name in `flake.nix`):
   ```sh
   cd /tmp/dev-env
   sudo env NIX_CONFIG="experimental-features = nix-command flakes" \
     nixos-rebuild boot --flake .#wsl
   ```
   Then close the NixOS window.
4. Restart the distro from PowerShell, so the new user is set up:
   ```powershell
   wsl -t NixOS
   wsl -d NixOS --user root exit
   wsl -t NixOS
   ```
5. Open NixOS again; you're now your own user. Create and register your SSH keys, then clone
   this repo to `~/dev-env` (the default `devEnv.configDir`) and switch from there:
   ```sh
   devenv-keys                  # add each printed key on GitHub, then: ssh -T git@github.com
   git clone git@github.com:<you>/<this-repo>.git ~/dev-env
   cd ~/dev-env && make switch
   ```
6. Continue with steps 2–4 of "Inside the machine" below.

After that, `make switch` inside WSL rebuilds; it picks the host from the hostname.

## Inside the machine

1. `devenv-keys` creates one SSH key per git account and prints where to register each one.
   Check them with `ssh -T git@github.com`.
2. Run `claude` and log in (open the link it prints in your browser). `make agents/setup` needs this first.
3. `make agents/setup` installs the agent add-ons that use their own installers
   (plannotator's pi extension, the Claude Code provider for pi, rtk's Claude Code hook,
   herdr-annotate). It starts a background herdr server if none is running.
4. Run `pi` and pick a model; with the Claude Code provider, it uses your `claude` login.

## Developing the base

To try changes to a local checkout of dev-env before publishing them:

```sh
make vm/bootstrap NIXADDR=<ip> DEV_ENV=../dev-env
```
