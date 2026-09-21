{ config, pkgs, ... }:

{
  home.packages = with pkgs; [
    neovim
    nodejs # npm for `pi install`; copilot.vim
    gcc # nvim-treesitter compiles parsers
    tree-sitter
    gh # octo.nvim
    lua-language-server
    stylua
    yaml-language-server
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
  # forwarded to the host like plannotator's. go-grip prints the URL; it only
  # tries to open a browser where xdg-open exists (on WSL it opens Windows').
  programs.zsh.initContent = ''
    md() {
      local open=false
      command -v xdg-open >/dev/null && open=true
      go-grip -b="$open" -p "''${MD_PORT:-6419}" "$@"
    }
  '';

  # Symlink to the checkout rather than the Nix store so lazy.nvim can write
  # lazy-lock.json and config edits apply without a rebuild.
  xdg.configFile."nvim".source =
    config.lib.file.mkOutOfStoreSymlink "${config.devEnv.configDir}/nvim";
}
