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
- **`ZSH_CUSTOM` must be set in `.zshenv`, not `home.sessionVariables`.** Oh My Zsh's default
  `$ZSH/custom` is a read-only store path, so `herdr plugin install` cannot link into it. The
  writable replacement is exported from `programs.zsh.envExtra`: `home.sessionVariables` lands
  in `hm-session-vars.sh`, which returns early when `__HM_SESS_VARS_SOURCED` is already set,
  and a long-lived herdr server inherits that from the shell that started it. `.zshenv` is
  read unconditionally, which is what the plugin's non-interactive build step sees.
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
  `PLAYWRIGHT_MCP_BROWSER=chromium` is needed too: the CLI otherwise defaults to the `chrome`
  *channel* and looks for Google Chrome in `/opt/google/chrome`.
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
