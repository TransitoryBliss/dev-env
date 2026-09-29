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
| `modules/nixos/{parallels,utm,vmware,wsl}.nix` | One per `devEnv.platform`. Always imported; everything under `config = lib.mkIf (platform == …)`. |
| `modules/nixos/vm.nix` | What the Mac VM platforms share (boot, disks by label, NetworkManager, firewall, SSH), for `platform` `utm`, `parallels` or `vmware`. |
| `modules/home/*.nix` | Home-manager: `languages` (flags), `editor`, `git` (identities, ghq, `wt`), `agents` (pi, Claude Code, rtk, herdr, plannotator). |
| `modules/home/wt.zsh` | `wt`: worktree + herdr workspace + agent per task. Sourced from `git.nix`'s `initContent`. |
| `pkgs/plannotator.nix` | Prebuilt binary per architecture. |
| `pkgs/pi-session-manager/` | Built from source, with our `Cargo.lock` and `security.patch`. |
| `modules/nixos/proxy.nix` | `devEnv.proxy`: Caddy on one localhost port, a `<name>.localhost` vhost per service. |
| `modules/home/session-manager.nix` | `devEnv.sessionManager`: PSM user service and pi extension. |
| `modules/home/backup.nix` | `devEnv.backup`: opt-in restic backup of agent sessions, selected per session folder by recorded cwd (`agent-sessions-select`); also sets Claude Code's `cleanupPeriodDays`. Enables user lingering from `modules/nixos/default.nix`. |
| `modules/home/secrets.nix` | `devEnv.secrets`: sops-nix, exports decrypted secrets from `.zshenv`, globally and per `host/owner` scope (re-checked on `cd`). |
| `modules/home/mcp.nix` | `devEnv.mcp`: MCP servers for pi, global and per `host/owner` scope (via `ancestorConfigRoots` = the home directory, absolute since a bare `~` is rejected: per-scope roots make the adapter warn outside them), fixed OAuth callback port. |

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
  from Nix, via the `languages` flags and `editor.nix`. The template's nvim config wires them
  through `vim.lsp.enable` (servers), conform.nvim (formatting) and nvim-lint (linting), and
  gates every one on `executable()`: a language the host hasn't enabled is skipped silently
  instead of erroring. A plugin's name for a tool is not always the binary's — nvim-lint calls
  golangci-lint `golangcilint` — so `available()` in `nvim/lua/plugins/format.lua` takes
  `{ name, binary }` pairs.
- **Plugins that download their own binaries don't belong here.** copilot.lua was left out for
  this reason: it fetches a 252 MB zip of copilot-language-server and extracts it with `unzip`
  (both its `binary` and `nodejs` targets are zips). If Copilot is ever wanted, `nixos-unstable`
  packages `copilot-language-server` (unfree) — add it to `devEnv.unfreePackages` and point
  `server.custom_server_filepath` at it, rather than letting the plugin download anything.
- **home-manager 26.05 option names:** `programs.git.settings` (not `userName`/`extraConfig`),
  `programs.ssh.settings` with OpenSSH directive names (not `matchBlocks`), and
  `programs.zsh.initContent` (not `initExtra`).
- **zsh would be in vi mode** without anyone asking: zsh picks the vi keymap when `$EDITOR`
  matches `*vi*`, and ours is `nvim`. Oh My Zsh's `lib/key-bindings.zsh` then forces emacs with
  `bindkey -e` anyway, so `defaultKeymap = "emacs"` in `modules/home/default.nix` states the
  outcome instead of leaving it to load order. Keybindings there are still bound with
  `bindkey -M` for `emacs`, `viins` and `vicmd`, and arrows for both `^[[A`/`^[OA` forms plus
  terminfo, since terminals send either depending on application keypad mode.
- **Oh My Zsh aliases shadow our shell functions.** `lib/directories.zsh` defines
  `alias md='mkdir -p'`, which collided with the `md` markdown helper in `editor.nix`. zsh
  expands aliases while *parsing*, so the alias breaks the definition ("defining function based
  on alias") *and* wins at the prompt afterwards — writing it as `function md { }` does not
  help. `unalias md` first. Check any new shell function against `$ZSH/lib/*.zsh`.
- **Anything a herdr pane must see belongs in `.zshenv`, not `home.sessionVariables`.** The
  latter lands in `hm-session-vars.sh`, which returns early when `__HM_SESS_VARS_SOURCED` is
  already set — and a herdr server started before a `make switch` hands that flag, with its
  own stale environment, to every shell it spawns afterwards. `programs.zsh.envExtra` writes
  `.zshenv`, which zsh reads unconditionally. Two things depend on this: `ZSH_CUSTOM` (Oh My
  Zsh's default `$ZSH/custom` is a read-only store path, so `herdr plugin install` cannot link
  into it, and the plugin's build step is non-interactive), and the `PLAYWRIGHT_*` variables
  (agents run in herdr panes; see the Playwright entry below). Setting both is fine and is
  what `languages.nix` does — `home.sessionVariables` still covers anything not started from
  zsh. After adding one, `herdr server reload-config` is *not* enough: the server's own
  environment is fixed at start, so either open a pane from a fresh login or restart it.
- **`herdr plugin install` leaves a dangling zsh plugin link.** The plugin's build step runs in
  herdr's temporary checkout and symlinks `$ZSH_CUSTOM/plugins/herdr` to it; herdr then moves
  the plugin to `~/.config/herdr/plugins/github/<id>-<hash>`. The template's `agents/setup`
  therefore also invokes the `install` action, which relinks in place. `plugin install` needs
  `--yes` when stdin is not a terminal, and `plugin uninstall` leaves the symlink behind.
- **The terminal palette is set by the shell, not the terminal.** Nothing inside the machine
  owns the 16 ANSI colours — Windows Terminal or herdr's pane emulator does. But both accept
  OSC writes (`OSC 4` per index, `OSC 10/11/12` for fg/bg/cursor), verified by querying the
  pane's pty before and after, so `modules/home/terminal.nix` writes the palette from an
  interactive zsh at `mkOrder 500`. Guard it with `-o interactive && -t 1 && $TERM !=
  (dumb|linux)`: escape sequences written into a pipe corrupt the reader. Note herdr's pane
  emulator answers OSC queries with its *own* built-in palette (Tomorrow Night), not the host
  terminal's and not `theme.name` — `[theme]` only styles herdr's chrome, and has no ANSI keys.
- **herdr keybindings:** `prefix+shift+r` is herdr's own `keys.reload_config`, so the
  herdr-ohmyzsh reload action is bound to `prefix+ctrl+r` instead of the `prefix+shift+r` its
  README suggests. Check new bindings against the upstream config reference before using them.
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
- **Playwright is two pins that must agree.** `devEnv.languages.playwright.enable` only provides
  browsers (`playwright-driver.browsers`, from `nixpkgs-unstable` — stable is far enough behind
  that no `@playwright/cli` release matches it); Playwright itself comes from npm with
  pi-playwright. Each `@playwright/cli` release pins a `playwright-core` that accepts *exactly
  one* Chromium revision, and Playwright refuses any other, so the template's `agents/setup`
  holds the CLI at the matching release with an npm `overrides` entry (`PLAYWRIGHT_CLI` in the
  Makefile). Letting Playwright download its own is not a way out: those are prebuilt binaries
  that don't run here, which is why `PLAYWRIGHT_SKIP_BROWSER_DOWNLOAD` is set. After a nixpkgs
  bump, compare `ls $PLAYWRIGHT_BROWSERS_PATH` with the revision in the candidate CLI's
  `playwright-core/browsers.json`; `agents/setup` warns when they have drifted apart.
  The override doubles as a bug fix: pi-playwright's wrapper looks for `playwright-cli` under
  its own package root, which npm's hoisting never creates — but the nesting npm uses for an
  overridden dependency does, so without the pin the skill is broken outright.
  The variables are exported from **both** `home.sessionVariables` and `programs.zsh.envExtra`
  on purpose (see the `.zshenv` entry above). An agent in a herdr pane that cannot see
  `PLAYWRIGHT_SKIP_BROWSER_DOWNLOAD` does not fail cleanly: the skill calls `install-browser`,
  downloads ~650M of prebuilt Chromium into `~/.cache/ms-playwright`, and it dies with exit
  127 on 26 missing libraries. The diagnosis then looks like a nix-ld problem, which it isn't.
  `PLAYWRIGHT_MCP_BROWSER=chromium` is needed too: the CLI otherwise defaults to the `chrome`
  *channel* and looks for Google Chrome in `/opt/google/chrome`.
- **Pi Session Manager** (`pkgs/pi-session-manager/`): upstream commits no `Cargo.lock`, so ours
  lives next to the package. Regenerate it in a checkout of the new tag with
  `CARGO_RESOLVER_INCOMPATIBLE_RUST_VERSIONS=fallback cargo generate-lockfile`; without that,
  cargo picks crates that need a newer rustc than nixpkgs has (`kstring` 2.0.5 wanted 1.96).
  `security.patch` is not optional: unpatched 0.8.6 takes `X-Forwarded-For: 127.0.0.1` from
  any client as proof of loopback (loopback skips the token), sends
  `Access-Control-Allow-Origin: *`, and ships a fixed default token. With its terminal
  endpoints that is a shell for anyone who reaches the port, or any web page through a
  tunnel. Reported to the maintainer privately. PSM rewrites its own `config.json`, so the
  user service's `ExecStartPre` forces `bind_addr = 127.0.0.1` with jq instead of
  home-manager owning the file. Regenerate the patch with the real git binary: rtk's `git
  diff` wrapper rewrites the output even when redirected, and the result won't apply.
- **devEnv.proxy** reads `devEnv.sessionManager` from the user's home-manager config to route
  `psm` by itself. Its checks (`Origin`, known hosts) are the reason the tunnel is safe, so
  keep them when adding services. The Mac VMs' firewall (`vm.nix`) is back on for the same reason.
  It also routes `plannotator` (19432) and `md` (6419), whose ports are fixed in `agents.nix`
  and `editor.nix`. Plannotator must stay in local mode (`PLANNOTATOR_REMOTE=0`): it detects
  SSH sessions and switches to remote mode by itself, which binds `0.0.0.0`. Local mode
  ignores `PLANNOTATOR_URL_HOST`, so its printed link keeps saying `localhost:19432`.
- **herdr:** plugin commands (`herdr plugin list/install`) need a running server; the
  template's `agents/setup` starts `herdr server` in the background. Known conflict:
  herdr-annotate's suggested `prefix+o` clashes with herdr's own default for notifications.
- **`devEnv.backup` selects by cwd, not by folder name.** pi's session folders
  (`--home-u-a-b--`) and Claude Code's (`-home-u-a-b`) both turn `/` into `-`, so `a/b-c` and
  `a-b/c` share a folder name. The selector reads every session header in a folder (pi nests
  subagent runs inside the parent's folder) and uploads the folder only if all of them are wanted;
  a mixed folder is skipped and logged, never partly uploaded. `sops-nix` checks keys at build
  time, so the `restic_*` secrets must exist before `enable = true`. `~/.claude/settings.json` is
  merged by an activation script, not managed, because `rtk init` writes to it; `cleanupPeriodDays`
  is never `0` (older Claude Code read that as "don't save transcripts"). To test without a
  bucket: `RESTIC_REPOSITORY=/tmp/r RESTIC_PASSWORD=x restic init`, then `backup --files-from`
  the output of `agent-sessions-select`, and `HOME=<scratch>` with fake session headers for the
  selection rules.
- **Secrets never go through Nix values.** `devEnv.secrets.env` maps variable names to keys in
  the sops file; `.zshenv` reads the decrypted file (`~/.config/sops-nix/secrets/<key>`) at
  shell start, so values never reach the store. sops-nix's home-manager module is imported on
  every host and inert while `sops.secrets` is empty, which is why `sopsFile = null` is safe.
  The age key is per machine at `~/.config/sops/age/keys.txt`, the sops CLI's default.
  `scopes` works by path (under every `devEnv.scopeRoots`), like `mcp.scopes`: `_dev_env_secrets` in `.zshenv` unsets every
  managed variable, exports the global ones, then a matching scope's (longest prefix first), and
  a `chpwd` hook reruns it. A scope secret that fails to decrypt leaves the variable unset, never
  the global value: the wrong workspace's key is worse than none. sops-nix validates at *build*
  time that every declared key exists in the file, so add the key with `sops` before declaring it.
  A running program keeps the keys of the directory it started in.
- **WSL:** renaming NixOS-WSL's default user requires `nixos-rebuild boot` plus a distro
  restart, not `switch` (see the template README). NixOS-WSL is imported on every host and
  inert unless `wsl.enable`. The `xdg-open` shim on WSL calls `explorer.exe`, which always
  exits 1.
- **comma / nix-index** come from the `nix-index-database` input's home-manager module (imported
  in `modules/home/default.nix`), which ships a prebuilt index; don't also add `nix-index` or
  `comma` to `home.packages`, they conflict with its wrappers. Testing them non-interactively
  misleads: `,` opens a picker (and fails with "Failed to open tty") whenever several packages
  provide the command, and the command-not-found handler only suggests a package when stdout
  is a terminal. Test with a command only one package has (`, figlet ok`).
- **`wt` (`modules/home/wt.zsh`)** is built on herdr's worktree API. `herdr worktree remove`
  closes the workspace but keeps the branch, so `wt` deletes it, and only when nothing is lost.
  Squash merges never make the branch an ancestor of the base, so "merged" also means a merged
  PR (`gh`) whose `headRefOid` is the worktree's exact tip; commits pushed after the merge keep
  it. `gc` keeps open worktrees with no commits: that is what a task that just started looks
  like. `wt done` run inside the worktree's own workspace kills its own shell when the workspace
  closes, so it finishes with `setsid -f` (log: `~/.local/state/wt.log`). Don't name a local
  `path` or `status` in it: zsh ties `path` to `$PATH`, and `status` is read-only. Field
  separators are `\x1f`, not tabs: `read` collapses runs of tabs and shifts empty fields.
  To test without starting pi: `WT_AGENT=true`, `wt -b <branch>` (no focus change), in a scratch
  repo with a local bare `origin`; drive `wt done` inside a worktree with `herdr pane run`.
  `--cwd` on a repo with no herdr workspace opens one for it, so close that afterwards.
  **Worktree layout:** `wt` passes `--path $_WT_ROOT/<host>/<owner>/<repo>/<branch>`
  (`devEnv.git.worktreeRoot`), mirroring `~/source`, so path-scoped config applies in
  worktrees too. Keep them out of `~/source`: ghq lists any directory with a `.git` in it,
  dot-directories included. Anything that scopes by path must cover every
  `devEnv.scopeRoots` (`mcp.nix` and `secrets.nix` do); git identities don't need it, since
  a worktree's gitdir is inside its main checkout. `_WT_ROOT`/`_WT_SRC` come from `git.nix`,
  so the detached `zsh -f` in `wt done` gets them passed explicitly.
- **UTM means Apple Virtualization, not QEMU.** The disk is virtio (`/dev/vda`, the Makefile's
  `NIXBLOCK` default; Parallels passes `/dev/sda`). `devEnv.utm.rosetta` stays off by default:
  nixpkgs' `virtualisation.rosetta` mounts UTM's `rosetta` virtiofs share without `nofail`, so
  enabling it without UTM's "Enable Rosetta" hangs the boot. `vm.nix` is imported where
  `parallels.nix` used to be, so list options (`extraGroups`) merge in the same order: splitting
  it left a Parallels host's `toplevel.drvPath` byte-identical. Check that again after touching
  it. `nix flake check` builds `example-vm` (UTM), `example-parallels` and `example-vmware`.
- **VMware Fusion** (Apple Silicon): NVMe disk (`NIXBLOCK=/dev/nvme0n1`), open-vm-tools via
  `virtualisation.vmware.guest`. That module adds `mptspi` to the initrd; it exists on
  aarch64 kernels too (the initrd builds). `systemd-boot.consoleMode = "0"` avoids Fusion's
  EFI console-mode error. Added because UTM's Shared network (Apple's per-VM Internet
  Sharing) had no internet on an MDM-managed Mac with the firewall locked on.
- **Makefile:** `vm/ssh` forwards `PROXY_PORT` (`devEnv.proxy.port`) and `MCP_OAUTH_PORT`
  (`devEnv.mcp.callbackPort`); a second VM running at the same time sets both in its host file
  and `Makefile.local` (read before the `?=` defaults). `HOST` defaults to the hostname on NixOS, and is only overridable from the
  command line. zsh's `HOST` variable must not leak in.

## Open items

- The WSL platform is evaluated but only partly exercised on real hardware: `xdg-open` and
  `md` opening the Windows browser, and `agents/setup`'s herdr server start.
- The `prefix+o` herdr-annotate/herdr key conflict in the template's `herdr/config.toml`.
