# My dev-env

Private config for [dev-env](https://github.com/TransitoryBliss/dev-env). The shared modules live
there; this repo holds only what's specific to me and my machines.

| Path                | What                                                         |
| ------------------- | ------------------------------------------------------------ |
| `flake.nix`         | One `nixosConfigurations` entry per machine                  |
| `users/me.nix`      | Username, SSH login keys, git identities, time zone          |
| `hosts/*.nix`       | Per-machine: platform, hostname, language flags              |
| `nvim/`             | Neovim config (lazy.nvim, LSP, treesitter), linked to `~/.config/nvim` |
| `herdr/config.toml` | herdr config, linked to `~/.config/herdr/config.toml`        |
| `Makefile`          | Your values (`NIXUSER`, `VM_HOST`), then `include dev-env.mk` |
| `dev-env.mk`        | Install and rebuild helpers: a copy of the base's, don't edit (see [Updating the base](#updating-the-base)) |
| `Makefile.local`    | Optional, not included: your additions, e.g. `PI_PACKAGES += some-pi-package@1.2.3` |

## First steps

1. Fill in `users/me.nix`. Rename it if you like, and update the imports in `flake.nix`.
2. Set `NIXUSER ?=` in the `Makefile` to your username, and `VM_HOST ?=` to the
   `nixosConfigurations` entry `make` builds from the Mac by default.
3. Keep the hosts you need in `hosts/` and `flake.nix`.

## UTM VM on a Mac

[UTM](https://mac.getutm.app) is free and uses Apple's own hypervisor (Apple Virtualization).
The template's `vm` host is set up for it (`devEnv.platform = "utm"`).

1. Install UTM, and download the NixOS **minimal ISO** for aarch64 from <https://nixos.org/download>.
2. In UTM: **Create a New Virtual Machine → Virtualize → Linux**, and tick **Use Apple
   Virtualization**. Boot ISO image: the NixOS ISO. Give it 4+ CPUs, 8+ GB memory and a 64+ GB
   disk, and leave the network on Shared. Leave "Enable Rosetta" off unless you also set
   `devEnv.utm.rosetta = true` (and if you set that, tick it: the VM won't finish booting
   without it).
3. Start the VM. In its console, run `sudo passwd root` (a temporary password for the
   installer), then `ip addr` to get the IP (usually `192.168.64.x`) and `lsblk` to see the disk
   (`vda`).
4. From the Mac, in this repo (**this wipes the VM disk**):
   ```sh
   make vm/bootstrap0 NIXADDR=<ip> HOST=vm NIXBLOCK=/dev/vda
   ```
5. After the reboot, shut the VM down, **remove the ISO** (in the VM's settings, select the
   drive and clear it), and start it again. Check the IP with `ip addr` in the console: UTM's
   shared network can hand out a different address after a reboot.
6. `make vm/bootstrap NIXADDR=<ip>`, then connect with `make vm/ssh NIXADDR=<ip>` and continue
   with "Inside the machine" below.

After changes: `make vm/bootstrap NIXADDR=<ip>`. Updates: `make vm/update NIXADDR=<ip>`.

**Web UIs from the Mac:** run `make mac/router` once. After that, `make vm/ssh` opens a
background tunnel for the VM, and everything in it is at
`http://<name>.<machine>.localhost:8090` (`<machine>` is the VM's hostname); `http://localhost:8090`
lists the connected VMs. `make vm/untunnel` closes a VM's tunnel.

**Two VMs at once** (say, one for work and one personal): with the router they share the
proxy port. The MCP OAuth callback is a plain forwarded port, so the second VM needs its own:
set `devEnv.mcp.callbackPort` in its host file (e.g. 19877) and the same value as
`MCP_OAUTH_PORT ?=` in that repo's `Makefile.local`.

## Parallels VM on a Mac

Use `hosts/parallels.nix` and uncomment the `parallels` entry in `flake.nix`.


1. Download the NixOS **minimal ISO** for your Mac's architecture from <https://nixos.org/download>.
2. In Parallels, create a VM from the ISO (e.g. 4+ CPUs, 8+ GB RAM, 64+ GB disk).
3. In the VM console, run `sudo passwd root` (a temporary password for the installer), then
   `ip addr` to get the IP and `lsblk` to see the disk (`sda` or `nvme0n1`).
4. From the Mac, in this repo (**this wipes the VM disk**):
   ```sh
   make vm/bootstrap0 NIXADDR=<ip> HOST=parallels NIXBLOCK=/dev/sda
   ```
5. After the reboot: `make vm/bootstrap NIXADDR=<ip> HOST=parallels`.
6. Connect with `make vm/ssh NIXADDR=<ip>`, then continue with "Inside the machine" below.

After changes: `make vm/bootstrap NIXADDR=<ip> HOST=parallels`. Updates:
`make vm/update NIXADDR=<ip> HOST=parallels`.

## VMware Fusion VM on a Mac

Use `hosts/vmware.nix` and uncomment the `vmware` entry in `flake.nix`. Fusion is free, but
the download needs a Broadcom account. Its NAT network runs through VMware's own helper, so it
can work where UTM's Shared network doesn't (e.g. behind a firewall enforced by device management).

1. Download the NixOS **minimal ISO** for aarch64 from <https://nixos.org/download>.
2. In Fusion, create a VM from the ISO (**Other Linux 6.x kernel 64-bit Arm**; 4+ CPUs, 8+ GB
   RAM, 64+ GB disk). Leave the network on **Share with my Mac** (NAT).
3. In the VM console, run `sudo passwd root` (a temporary password for the installer), then
   `ip addr` to get the IP and `lsblk` to see the disk (`nvme0n1`).
4. From the Mac, in this repo (**this wipes the VM disk**):
   ```sh
   make vm/bootstrap0 NIXADDR=<ip> HOST=vmware NIXBLOCK=/dev/nvme0n1
   ```
5. After the reboot, remove the ISO (VM settings → CD/DVD → uncheck Connect). The installed
   system has no password, so get the IP from Fusion rather than the console: open-vm-tools
   reports it, and `vmrun getGuestIPAddress <path-to.vmx>` prints it.
6. `make vm/bootstrap NIXADDR=<ip> HOST=vmware`, then connect with `make vm/ssh NIXADDR=<ip>`.

After changes: `make vm/bootstrap NIXADDR=<ip> HOST=vmware`. Updates:
`make vm/update NIXADDR=<ip> HOST=vmware`.

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
   (plannotator's pi extension, pi-claude-bridge (Claude through your `claude` login),
   pi-subagents, rpiv-ask-user-question, pi-playwright, pi-web-access, rtk's Claude Code hook,
   herdr-annotate, herdr-ohmyzsh). It starts a background herdr server if none is running.
   Until it has run, each new shell prints `[oh-my-zsh] plugin 'herdr' not found`.
4. Run `pi` and pick a model with `/model`, e.g. `claude-bridge/claude-opus-5-5`; the bridge uses
   your `claude` login. On a Max plan, set `CLAUDE_PLAN = max` in `Makefile.local` first.
5. Start `nvim` once. lazy.nvim bootstraps itself, installs the plugins and compiles the
   treesitter parsers listed in `nvim/lua/plugins/treesitter.lua` (the first run takes a
   minute or two). It writes `nvim/lazy-lock.json` with the exact plugin commits — **commit
   that file**, it is what pins the plugins on every other machine. After pulling someone
   else's `lazy-lock.json`, run `nvim --headless "+Lazy! restore" +qa` to match it.

## Colours

One setting in `users/me.nix` colours the terminal, herdr, nvim and pi:

```nix
home.devEnv.theme.name = "tokyonight-storm";   # names in the base's themes/palettes.json
home.devEnv.theme.background = "#211535";      # optional, e.g. per host to tell VMs apart
```

A host file can override it (e.g. a light theme on one VM, with `lib.mkForce` or by
setting it only per host). After changing it: `make switch`, detach and reattach herdr
(`make vm/ssh`), restart nvim. Commit `herdr/config.toml` afterwards: `make switch` keeps a
marked colour block at its end. What the private config needs, all already in this
template:

- `SSH_CMD ?= herdr-attach` in `dev-env.mk` (writes the palette to your terminal).
- `[theme] name = "terminal"` in `herdr/config.toml`.
- `nvim/lua/plugins/colors.lua` loading the base's plugin, lualine on `theme = "auto"`, and
  no `vim.cmd.colorscheme(...)` anywhere else in the nvim config.

## Secrets

API keys for agent tools (e.g. `LINEAR_API_KEY` for Linear's MCP server) live in `secrets.yaml`,
encrypted with [sops](https://github.com/getsops/sops) and committed here. Each machine has
its own [age](https://age-encryption.org) key, which never leaves it; `make switch` decrypts
the file into `$XDG_RUNTIME_DIR` and every new zsh exports the variables you list.

1. On each machine, create its key and note the public key it prints:
   `mkdir -p ~/.config/sops/age && age-keygen -o ~/.config/sops/age/keys.txt`
2. List every machine's public key in `.sops.yaml` here:

   ```yaml
   keys:
     - &vm age1...
     - &wsl age1...
   creation_rules:
     - path_regex: secrets\.yaml$
       key_groups:
         - age: [*vm, *wsl]
   ```

3. `sops secrets.yaml` opens an editor; add `linear_api_key: lin_api_...` and save.
4. `git add .sops.yaml secrets.yaml`, uncomment `home.devEnv.secrets` in `users/<you>.nix`,
   and `make switch`. New shells have `LINEAR_API_KEY`.

Different keys per org (say, a second Linear workspace) go in a scope, like `git.overrides`:

```nix
home.devEnv.secrets.scopes."github.com/some-org".env.LINEAR_API_KEY = "some_org_linear_api_key";
```

Under `~/source/github.com/some-org` that key replaces the global one; `cd` switches back and
forth. A running program (pi) keeps the keys of the directory it was started in. Add the key to
`secrets.yaml` first: `make switch` fails on a key the file doesn't have.

After adding a machine to `.sops.yaml`, run `sops updatekeys secrets.yaml` on one that can
already decrypt it. Anything an agent can see in its environment it can print, so prefer
narrowly scoped keys (a read-only Linear key, if that is enough).

## Backups

`home.devEnv.backup.enable = true` backs up agent sessions (pi's `~/.pi/agent/sessions`,
Claude Code's `~/.claude/projects`) every hour with [restic](https://restic.net), encrypted
before upload. Off by default. Sessions are chosen by the directory each was started in:
everything under `~`, minus `exclude` and `excludeScopes` (e.g. an employer's org, which then
never leaves the machine). `agent-sessions-select` prints what would be uploaded. Enabling it
also stops Claude Code deleting transcripts after 30 days.

1. Create a bucket, e.g. on Backblaze B2 (the first 10 GB are free), and an application key
   limited to it.
2. `sops secrets.yaml`, and add:

   ```yaml
   restic_repository: s3:https://s3.<region>.backblazeb2.com/<bucket>/agent-sessions
   restic_password: <long random string>
   restic_env: |
     AWS_ACCESS_KEY_ID=<keyID>
     AWS_SECRET_ACCESS_KEY=<applicationKey>
   ```

   **Keep `restic_password` in a password manager too.** It's the only way into the backup if
   the machine that can decrypt `secrets.yaml` is gone.
3. Enable it and `make switch`. Run it once by hand and check it:
   `systemctl --user start restic-backups-agent-sessions`, then
   `restic-agent-sessions snapshots` and `restic-agent-sessions ls latest`.

To restore on a new machine (same username: pi's folder names contain the home path), before
starting pi there. Restore into `/tmp`, not `/`, which would also restore the metadata of
`/home` and your home directory; name the old machine, since snapshots are per host:

```sh
systemctl --user stop restic-backups-agent-sessions.timer
restic-agent-sessions restore latest --host <old-host> --target /tmp/sessions-restore
rsync -a /tmp/sessions-restore/home/<you>/ ~/ && rm -rf /tmp/sessions-restore
systemctl --user start restic-backups-agent-sessions.timer
```

## Notes

`home.devEnv.notes.repo = "github.com/<you>/notes"` keeps ideas and todos as markdown files
in a git repo, and gives you and your agents one command for them. Create the repo first
(private is fine), with `ideas/` and `todos/` directories; an `AGENTS.md` describing the
format helps agents that edit files by hand. Then:

```sh
idea "Try a smaller model for commit messages"
todo "Renew the certificate" -m "Expires in October." --tag infra
note ls              # open items; -a for all, -H for the repo you're in
note done renew
```

Every change is pulled, committed and pushed, so each machine sees the same list. Agents
learn the command from the `notes` skill (pi and Claude Code); ask one to "note this idea"
or "what's on my todo list". Different machines can point at different repos, e.g. a work
machine at a work account's notes.

## Updating the base

`make vm/update NIXADDR=<ip> INPUT=dev-env` (from the Mac) moves the `dev-env` input to its
latest commit, and copies back both `flake.lock` and `dev-env.mk`: the make targets live in the
base, and the copy here is replaced by the one in the input you just locked. Commit both.
Inside a machine, the same is `nix flake update dev-env && make base/sync`.

`dev-env.mk` is a plain file in this repo, not read from the flake input, because `make vm/*`
runs on the Mac, which has no Nix. Don't edit it: `make base/check` (also run by `make check`)
fails when it differs from the locked input's copy. Your own variables and targets go in the
`Makefile` (before the `include`) or in `Makefile.local` (`PI_PACKAGES +=`, `CLAUDE_PLAN`,
`PROXY_PORT`, `MCP_OAUTH_PORT`, `SSH_CMD`, extra targets).

**Configs from before `dev-env.mk`** had the whole thing in `Makefile`. To switch: update the
input (`make vm/update NIXADDR=<ip> INPUT=dev-env` still works with the old Makefile), then,
inside the machine, replace `Makefile` with the short one from the template (keep your
`NIXUSER`, and set `VM_HOST` to what `HOST` defaulted to), run `make base/sync`, and commit
`Makefile` and `dev-env.mk`. Move anything else you had changed in the old Makefile to
`Makefile.local`.

## Developing the base

To try changes to a local checkout of dev-env before publishing them:

```sh
make vm/bootstrap NIXADDR=<ip> DEV_ENV=../dev-env
```
