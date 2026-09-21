# Language toolchains, toggled per host with flags, e.g.
#   devEnv.languages.go.enable = true;
{ inputs }:
{ config, lib, pkgs, ... }:

let
  cfg = config.devEnv.languages;

  # Chromium for Playwright. Stable nixpkgs is too far behind for any
  # @playwright/cli release to match it (see the playwright block below).
  unstable = import inputs.nixpkgs-unstable {
    inherit (pkgs.stdenv.hostPlatform) system;
  };
in
{
  options.devEnv.languages = {
    go.enable = lib.mkEnableOption "Go toolchain";
    node.enable = lib.mkEnableOption "Node.js / TypeScript toolchain (with bun)";
    playwright.enable = lib.mkEnableOption "Playwright browsers from Nix (for the pi-playwright skill)";
  };

  config = lib.mkMerge [
    (lib.mkIf cfg.go.enable {
      home.packages = with pkgs; [
        go
        gopls
        gotools # goimports
        gofumpt
        golangci-lint
        delve
      ];
      home.sessionPath = [ "$HOME/go/bin" ];
    })

    (lib.mkIf cfg.node.enable {
      home.packages = with pkgs; [
        bun
        pnpm
        typescript
        typescript-language-server
        prettier
        eslint_d
      ];
    })

    # Browsers only: Playwright itself comes from npm, with the CLI pinned by
    # `make agents/setup` to the release whose playwright-core expects exactly
    # the Chromium revision below. Playwright refuses any other revision, and
    # its own downloads are prebuilt binaries that don't run on NixOS, so the
    # two version lines have to be kept in step by hand. Nothing is added to
    # home.packages: the store path in hm-session-vars.sh is what keeps the
    # browsers alive across garbage collection.
    (lib.mkIf cfg.playwright.enable {
      home.sessionVariables = {
        PLAYWRIGHT_BROWSERS_PATH = "${unstable.playwright-driver.browsers}";
        # Makes `npx playwright install` a no-op instead of fetching binaries
        # that would only fail to start.
        PLAYWRIGHT_SKIP_BROWSER_DOWNLOAD = "1";
        # playwright-cli defaults to the "chrome" *channel*, i.e. a Google
        # Chrome installed at /opt/google/chrome. There is none here; point it
        # at the bundled Chromium, which is what PLAYWRIGHT_BROWSERS_PATH holds.
        PLAYWRIGHT_MCP_BROWSER = "chromium";
      };
    })
  ];
}
