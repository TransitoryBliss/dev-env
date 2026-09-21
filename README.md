# dev-env

A NixOS development environment for AI-assisted coding, packaged as reusable modules.
It runs as a Parallels VM on a Mac or under WSL2 on Windows, and gives you:

- **Agents:** [pi](https://github.com/earendil-works/pi) and [Claude Code](https://claude.com/claude-code),
  with [rtk](https://github.com/rtk-ai/rtk) cutting the tokens command output costs, and
  [plannotator](https://plannotator.ai) for reviewing plans and diffs.
- **Sessions:** [herdr](https://herdr.dev) instead of tmux, so agents keep running after you disconnect.
- **Editor:** Neovim with language servers from Nix, plus toolchains switched on per machine.
- **Git:** one identity and SSH key per account, chosen by the repo's owner; repos laid out
  as `~/source/<host>/<owner>/<repo>`.

## How it's organised

This repo holds only the shared, generic parts. Your personal config lives in a separate,
private repo created from the template here. It contains your username, keys, git identities,
machines and dotfiles.

```sh
mkdir my-dev-env && cd my-dev-env
nix flake init -t github:TransitoryBliss/dev-env
```

The private repo's `flake.nix` uses this one as an input:

```nix
inputs.dev-env.url = "github:TransitoryBliss/dev-env";
outputs = { dev-env, ... }: {
  nixosConfigurations.vm = dev-env.lib.mkHost {
    system = "aarch64-linux";
    modules = [ ./users/me.nix ./hosts/vm.nix ];
  };
};
```

You get improvements to the base with `nix flake update dev-env`, without merging anything.
To change the base itself, fork this repo and point `inputs.dev-env.url` at your fork.
The template's README covers installing on each platform.

| Path                 | What                                                       |
| -------------------- | ---------------------------------------------------------- |
| `flake.nix`          | Exports `nixosModules`, `homeModules`, `lib.mkHost`, the template |
| `modules/nixos/`     | User account, Nix settings, platforms (`parallels.nix`, `wsl.nix`) |
| `modules/home/`      | Languages, editor, git identities, agents                  |
| `pkgs/`              | Packages not in nixpkgs (plannotator)                      |
| `templates/default/` | Starting point for a private config                        |

## Options

System level, usually in `users/<you>.nix` and `hosts/<machine>.nix`:

| Option                   | Meaning                                                            |
| ------------------------ | ------------------------------------------------------------------ |
| `devEnv.platform`        | `"parallels"` or `"wsl"`                                           |
| `devEnv.user.name`       | Your login name                                                    |
| `devEnv.user.sshKeys`    | Public keys allowed to SSH in (VM platforms)                       |
| `devEnv.user.home`       | Home-manager config for you (the options below go here)            |
| `devEnv.configDir`       | Checkout of your private config in the machine (default `~/dev-env`) |
| `devEnv.timeZone`        | Time zone (default `UTC`)                                          |
| `devEnv.unfreePackages`  | Extra unfree packages to allow, by name                            |

Home level, under `devEnv.user.home`:

| Option                               | Meaning                                              |
| ------------------------------------ | ---------------------------------------------------- |
| `devEnv.languages.go.enable`         | go, gopls, goimports, gofumpt, golangci-lint, delve  |
| `devEnv.languages.node.enable`       | bun, pnpm, typescript + language server, prettier, eslint_d |
| `devEnv.git.default`                 | `{ account, name, email }` used everywhere by default |
| `devEnv.git.overrides."<host/owner>"` | The same, for repos under one org or user            |

## Git identities and repositories

Repos live at `~/source/<host>/<owner>/<repo>`, managed by [ghq](https://github.com/x-motemen/ghq).
`ghq get owner/repo` clones there, and `repo [query]` jumps to one with fzf.

Every account gets its own SSH key, `~/.ssh/id_ed25519_<account>`. Git uses the default
identity everywhere, except in repos whose remote, or path under `~/source`, matches an override.
Keys are chosen by URL, so this works with any tool (`git clone`, `ghq get`, `go get`):

- An override's URLs, HTTPS or SSH, are rewritten to an SSH alias like
  `github.com-<account>`, which uses that account's key.
- The default account's own repos go over SSH with the default key.
- Other public repos stay on HTTPS and don't need a key.

On a new machine, `devenv-keys` creates the keys and prints each one with the account to add
it to (<https://github.com/settings/ssh/new>; a key can belong to only one GitHub account).
To check a key: `ssh -i ~/.ssh/id_ed25519_<account> -o IdentitiesOnly=yes -T git@github.com`.
For `gh`, run `gh auth login --git-protocol ssh --skip-ssh-key` once per account.

## Tools and where they come from

- **pi** comes from nixpkgs `master`, because
  [pi-claude-code-provider](https://pi.dev/packages/pi-claude-code-provider) needs pi 0.86.1+.
  Once that reaches `nixos-unstable`, pi moves back there (see `flake.nix`).
  rtk's pi extension is installed at `~/.pi/agent/extensions/rtk.ts`.
- **Claude Code** comes from `nixos-unstable`, with its auto-updater turned off. Log in with a
  Pro/Max/Team subscription. The pi provider runs `claude` under the hood and uses the same login.
- **herdr** comes from its own flake, pinned by tag in `flake.nix`.
- **plannotator** is a prebuilt release per architecture, in `pkgs/plannotator.nix`. Bump
  `version` and both hashes to update. There's no browser in the machine, so it serves its UI
  on port 19432. From a Mac, tunnel it with `make vm/ssh`; WSL forwards it to Windows' localhost.
- Some add-ons install through their own tooling, via the template's `make agents/setup`:
  plannotator's pi extension, the Claude Code provider for pi, rtk's Claude Code hook
  (`rtk init -g`), and the [herdr-annotate](https://github.com/plannotator/herdr-annotate) plugin.

### Prebuilt binaries and nix-ld

NixOS lacks the standard library paths prebuilt Linux binaries expect.
`programs.nix-ld` provides them, so tools that download their own binaries
(herdr plugins, plannotator, npm packages with native parts) run unchanged.

### herdr-annotate over SSH

When herdr runs in a VM you reach over SSH, `prefix+a` currently loses the selection
([herdr#3380](https://github.com/herdrdev/herdr/issues/3380)), and the VM has no clipboard.
Until that's fixed, trigger capture from the host while text is selected:

```sh
ssh <user>@<vm-ip> herdr plugin action invoke annotate.capture
```

## Developing this repo

`nix flake check` evaluates the template's two hosts (`example-vm` and `example-wsl`) against
this checkout. To try changes on a real machine before publishing, build your private config
against a local checkout: `make vm/bootstrap NIXADDR=<ip> DEV_ENV=../dev-env`.
