# Terminal colour palette, applied by the shell rather than by the terminal's
# own config, e.g.
#   devEnv.terminalPalette = "gruvbox-dark";
#
# Terminal emulators resolve ANSI colour *indices* (1 = red, 4 = blue, ...) into
# pixels using a palette we normally cannot reach from inside the machine: on
# WSL it lives in Windows Terminal's settings.json, outside Nix. But the palette
# is also writable at runtime with OSC escape sequences (OSC 4 for the 16
# indices, OSC 10/11/12 for foreground, background and cursor), and both
# Windows Terminal and herdr's pane emulator honour them, so an interactive zsh
# can set it on startup and everything downstream -- the prompt, ls, fzf,
# zsh-syntax-highlighting -- lands on these colours without being configured
# one by one.
{ config, lib, ... }:

let
  cfg = config.devEnv;

  # Each palette: the 16 ANSI slots in order (0-7 normal, 8-15 bright), plus
  # the foreground, background and cursor.
  palettes = {
    gruvbox-dark = {
      # github.com/morhetz/gruvbox, dark medium.
      ansi = [
        "#282828" # 0  black        bg
        "#cc241d" # 1  red
        "#98971a" # 2  green
        "#d79921" # 3  yellow
        "#458588" # 4  blue
        "#b16286" # 5  magenta      purple
        "#689d6a" # 6  cyan         aqua
        "#a89984" # 7  white        fg4
        "#928374" # 8  bright black gray
        "#fb4934" # 9  bright red
        "#b8bb26" # 10 bright green
        "#fabd2f" # 11 bright yellow
        "#83a598" # 12 bright blue
        "#d3869b" # 13 bright magenta
        "#8ec07c" # 14 bright cyan
        "#ebdbb2" # 15 bright white fg1
      ];
      foreground = "#ebdbb2";
      background = "#282828";
      cursor = "#ebdbb2";
    };

    catppuccin-mocha = {
      ansi = [
        "#45475a"
        "#f38ba8"
        "#a6e3a1"
        "#f9e2af"
        "#89b4fa"
        "#f5c2e7"
        "#94e2d5"
        "#bac2de"
        "#585b70"
        "#f38ba8"
        "#a6e3a1"
        "#f9e2af"
        "#89b4fa"
        "#f5c2e7"
        "#94e2d5"
        "#a6adc8"
      ];
      foreground = "#cdd6f4";
      background = "#1e1e2e";
      cursor = "#f5e0dc";
    };
  };

  palette = palettes.${cfg.terminalPalette};

  # One write for the whole palette, so the terminal repaints once.
  setSequences =
    lib.concatStringsSep "" (
      lib.imap0 (i: colour: ''''${esc}]4;${toString i};${colour}''${st}'') palette.ansi
    )
    + ''''${esc}]10;${palette.foreground}''${st}''
    + ''''${esc}]11;${palette.background}''${st}''
    + ''''${esc}]12;${palette.cursor}''${st}'';
in
{
  options.devEnv.terminalPalette = lib.mkOption {
    type = lib.types.nullOr (lib.types.enum (lib.attrNames palettes));
    default = null;
    example = "gruvbox-dark";
    description = ''
      Colour palette an interactive zsh writes to its terminal on startup, or
      null to leave the terminal's own colours alone.
    '';
  };

  config = lib.mkIf (cfg.terminalPalette != null) {
    # Order 500 so the colours are in place before anything prints: the prompt,
    # Oh My Zsh's output, and the "plugin not found" notice all come later.
    programs.zsh.initContent = lib.mkOrder 500 ''
      # Terminal colours (${cfg.terminalPalette}). Only for a real interactive
      # terminal: writing escape sequences into a pipe would corrupt whatever
      # is reading it, and the Linux console and dumb terminals do not take
      # OSC. Terminals that ignore OSC drop these silently.
      if [[ -o interactive && -t 1 && $TERM != (dumb|linux) ]]; then
        () {
          local esc=$'\e' st=$'\e\\'
          print -rn -- "${setSequences}"
        }
      fi
    '';
  };
}
