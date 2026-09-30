# devEnv.notes: ideas and todos as markdown files in a git repo, for you and
# your agents.
#
#   devEnv.notes.repo = "github.com/you/notes";
#
# Installs `note` (with `idea` and `todo` as shorthands), which commits and
# pushes every change under a lock, and a `notes` skill for pi and Claude Code
# that tells agents how to use it. The checkout lives at ~/source/<repo>, like
# any ghq clone, and `note` clones it on first use.
#
# The repo's location is baked into the wrapper rather than exported, so agents
# in a herdr pane started before a `make switch` still find it (see AGENTS.md
# on .zshenv). Different machines can point at different repos, e.g. a work
# machine at a work account's notes, with the same format and skill.
{ config, lib, pkgs, ... }:

let
  cfg = config.devEnv.notes;

  note = pkgs.writeShellApplication {
    name = "note";
    runtimeInputs = with pkgs; [ git openssh coreutils util-linux gawk gnused ];
    text = ''
      if [ -z "''${NOTES_DIR:-}" ]; then NOTES_DIR=${lib.escapeShellArg cfg.dir}; fi
      if [ -z "''${NOTES_REPO:-}" ]; then NOTES_REPO=${lib.escapeShellArg "https://${cfg.repo}"}; fi
    '' + builtins.readFile ./note.sh;
  };

  shorthand = type: pkgs.writeShellScriptBin type ''
    exec ${note}/bin/note add -t ${type} "$@"
  '';
in
{
  options.devEnv.notes = {
    repo = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      default = null;
      example = "github.com/you/notes";
      description = ''
        Git repo for ideas and todos, as host/owner/repo. Setting it installs
        `note`, `idea`, `todo` and the notes skill; null leaves them out.
      '';
    };
    dir = lib.mkOption {
      type = lib.types.str;
      default = "${config.home.homeDirectory}/source/${toString cfg.repo}";
      defaultText = lib.literalExpression ''"''${home.homeDirectory}/source/''${devEnv.notes.repo}"'';
      description = "Checkout of the notes repo; `note` clones it here on first use.";
    };
  };

  config = lib.mkIf (cfg.repo != null) {
    home.packages = [ note (shorthand "idea") (shorthand "todo") ];

    home.file.".agents/skills/notes".source = ./skill;
    home.file.".claude/skills/notes".source = ./skill;
  };
}
