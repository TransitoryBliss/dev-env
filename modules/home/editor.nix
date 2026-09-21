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
  ];

  home.sessionVariables = {
    EDITOR = "nvim";
    VISUAL = "nvim";
  };

  home.shellAliases.vim = "nvim";

  # Symlink to the checkout rather than the Nix store so lazy.nvim can write
  # lazy-lock.json and config edits apply without a rebuild.
  xdg.configFile."nvim".source =
    config.lib.file.mkOutOfStoreSymlink "${config.devEnv.configDir}/nvim";
}
