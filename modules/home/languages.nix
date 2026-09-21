# Language toolchains, toggled per host with flags, e.g.
#   devEnv.languages.go.enable = true;
{ config, lib, pkgs, ... }:

let
  cfg = config.devEnv.languages;
in
{
  options.devEnv.languages = {
    go.enable = lib.mkEnableOption "Go toolchain";
    node.enable = lib.mkEnableOption "Node.js / TypeScript toolchain (with bun)";
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
  ];
}
