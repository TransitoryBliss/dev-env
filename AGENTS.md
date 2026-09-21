# AGENTS.md

Notes for coding agents working on this repo. The README is for users; this is how to change
it safely.

## What this repo is

A public NixOS flake with the **shared, generic** parts of a development environment:
`nixosModules.default`, `homeModules.default`, `lib.mkHost`, and a template
(`templates/default`) for the **private** config that holds a person's user, keys, git
identities and hosts. Consumers pin this repo as the `dev-env` flake input and update with
`nix flake update dev-env`.

The maintainer's own private config is `TransitoryBliss/dev-env-config`. Test changes against
it (see below).

## Rules

- **No personal data here.** No usernames, emails, keys, hostnames, employers or time zones.
  Anything personal becomes a `devEnv.*` option with a neutral default, set from the private
  config. The template uses placeholders (`me`, `your-github-login`).
- **Keep the template working.** `nixosConfigurations.example-vm` (aarch64) and
  `example-wsl` (x86_64) are built from `templates/default`. If an option changes, update the
  template and both READMEs (`README.md`, `templates/default/README.md`).
- Commit as `Robert Stenbom <7187639+TransitoryBliss@users.noreply.github.com>`.

## Layout and conventions

| Path | Notes |
|---|---|
| `flake.nix` | Inputs, exports, example hosts. Modules are imported as `import ./modules/x { inherit inputs; }` (they're functions of the flake inputs), so consumers don't need to pass inputs. |
| `modules/nixos/default.nix` | `devEnv.*` system options: user, platform, configDir, timeZone, unfreePackages. Wires home-manager for `devEnv.user.name`. |
| `modules/nixos/{parallels,wsl}.nix` | One per `devEnv.platform`. Always imported; everything under `config = lib.mkIf (platform == …)`. |
| `modules/home/*.nix` | Home-manager: `languages` (flags), `editor`, `git` (identities, ghq), `agents` (pi, Claude Code, rtk, herdr, plannotator). |
| `pkgs/plannotator.nix` | Prebuilt binary per architecture. |

- **Unfree packages:** add names to `devEnv.unfreePackages`. Don't set
  `nixpkgs.config.allowUnfreePredicate` anywhere else; two definitions of a function don't merge.
- **Per-user home config** comes in through `devEnv.user.home`, a deferred module forwarded
  to `home-manager.users.<name>`.
- Files the user edits in place, or that tools write to (nvim config, herdr config), are
  `mkOutOfStoreSymlink`s into `devEnv.configDir`, not store copies.

## Verifying changes

```sh
nix flake check                      # evaluates example-vm and example-wsl
nix eval --raw .#nixosConfigurations.example-wsl.config.system.build.toplevel.drvPath
```

To try a change on a real machine, in the private config checkout (`~/dev-env`):

```sh
make switch DEV_ENV=$HOME/source/github.com/TransitoryBliss/dev-env
```

After pushing here, update the consumer: `nix flake update dev-env`, then `make switch`, then
commit its `flake.lock`.

## Things that bit us (don't undo them)

- **plannotator** is a Bun single-file executable: `dontStrip` and `dontPatchELF` are
  required (patching corrupts it). It runs unpatched through `programs.nix-ld`. Updating means
  bumping `version` and **both** hashes (from the release's `.sha256` files).
- **nix-ld** stays on: herdr plugins, plannotator and npm native modules download prebuilt
  glibc binaries.
- **Mason can't be used** on NixOS (prebuilt binaries). Language servers and formatters come
  from Nix, via the `languages` flags and `editor.nix`.
- **home-manager 26.05 option names:** `programs.git.settings` (not `userName`/`extraConfig`),
  `programs.ssh.settings` with OpenSSH directive names (not `matchBlocks`), and
  `programs.zsh.initContent` (not `initExtra`).
- **Git identities** pick the SSH key by *URL*: an override's URLs are rewritten
  (`url.<alias>.insteadOf`) to a host alias like `github.com-<account>`, whose SSH block sets
  the key. Don't move key selection into `includeIf` + `core.sshCommand`: git doesn't document
  whether those includes apply during `git clone`, and the URL rewrite works for every tool.
  Name and email come from `includeIf "hasconfig:remote.*.url:…"` and `gitdir:` includes.
  Files included via `hasconfig` must not contain remote URLs.
- **pi** comes from `nixpkgs-master`, because pi-claude-code-provider needs pi ≥ 0.86.1. Move it
  back to `nixpkgs-unstable` (and drop the input) once unstable has it. **Claude Code** comes
  from `nixpkgs-unstable`, imported with its own `allowUnfreePredicate`: `legacyPackages`
  ignores the system's unfree setting.
- **rtk's pi extension** is fetched from an rtk release tag, because nixpkgs' rtk predates
  `rtk init --agent pi`. The extension only calls `rtk rewrite`, so the older binary works.
- **herdr:** plugin commands (`herdr plugin list/install`) need a running server; the
  template's `agents/setup` starts `herdr server` in the background. Known conflict:
  herdr-annotate's suggested `prefix+o` clashes with herdr's own default for notifications.
- **WSL:** renaming NixOS-WSL's default user requires `nixos-rebuild boot` plus a distro
  restart, not `switch` (see the template README). NixOS-WSL is imported on every host and
  inert unless `wsl.enable`. The `xdg-open` shim on WSL calls `explorer.exe`, which always
  exits 1.
- **Makefile:** `HOST` defaults to the hostname on NixOS, and is only overridable from the
  command line. zsh's `HOST` variable must not leak in.

## Open items

- The WSL platform is evaluated but only partly exercised on real hardware: `xdg-open` and
  `md` opening the Windows browser, and `agents/setup`'s herdr server start.
- The `prefix+o` herdr-annotate/herdr key conflict in the template's `herdr/config.toml`.
