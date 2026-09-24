{ config, pkgs, ... }:

{
  home.packages = with pkgs; [
    neovim
    nodejs # npm for `pi install`
    gcc # nvim-treesitter compiles parsers
    tree-sitter
    gh # octo.nvim
    lua-language-server
    stylua
    yaml-language-server
    nil # Nix language server; the config itself is Nix
    # Markdown: go-grip previews in the browser, glow renders in the terminal.
    go-grip
    glow
  ];

  home.sessionVariables = {
    EDITOR = "nvim";
    VISUAL = "nvim";
  };

  home.shellAliases.vim = "nvim";

  # `md [file|dir]`: preview markdown with live reload on a fixed port (6419),
  # with devEnv.proxy at http://md.localhost:8090. go-grip's -H only sets the
  # printed URL: it still listens on all interfaces, so the Parallels firewall
  # is what keeps it private there. It only
  # tries to open a browser where xdg-open exists (on WSL it opens Windows').
  #
  # Oh My Zsh's lib/directories.zsh defines `alias md='mkdir -p'`. zsh expands
  # aliases while parsing, so the alias both breaks this definition ("defining
  # function based on alias") and wins at the prompt afterwards, even when the
  # function is written with the `function` keyword. Drop it first.
  programs.zsh.initContent = ''
    unalias md 2>/dev/null
    md() {
      local open=false
      command -v xdg-open >/dev/null && open=true
      go-grip -b="$open" -H 127.0.0.1 -p "''${MD_PORT:-6419}" "$@"
    }
  '';

  # Symlink to the checkout rather than the Nix store so lazy.nvim can write
  # lazy-lock.json and config edits apply without a rebuild.
  xdg.configFile."nvim".source =
    config.lib.file.mkOutOfStoreSymlink "${config.devEnv.configDir}/nvim";
}
