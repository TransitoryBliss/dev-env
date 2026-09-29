# devEnv.backup: opt-in restic backups of agent sessions (pi and Claude Code).
#
#   devEnv.backup = {
#     enable = true;
#     excludeScopes = [ "github.com/some-employer" ];   # never back these up
#   };
#
# pi keeps sessions in ~/.pi/agent/sessions/<folder per cwd>/, Claude Code in
# ~/.claude/projects/<folder per cwd>/. The folder names encode the cwd lossily
# ("/" and "-" both become "-"), so folders are chosen by the cwd each session
# records: a folder is backed up when every session in it was started at or
# below an `include` directory and none at or below an excluded one. A folder
# mixing both is skipped (and logged), never partly uploaded. Everything else
# (pi's sessions.db index, missions, /tmp sessions) stays out.
# `agent-sessions-select` prints the current selection.
#
# The repository, its password and (optionally) backend credentials come from
# devEnv.secrets.sopsFile, as the keys named in `secrets`. The environment
# secret holds KEY=value lines, e.g. AWS_ACCESS_KEY_ID/AWS_SECRET_ACCESS_KEY
# for an S3-compatible bucket (Backblaze B2:
# s3:https://s3.<region>.backblazeb2.com/<bucket>/agent-sessions).
#
# Also sets Claude Code's cleanupPeriodDays to 36500: by default it deletes
# transcripts after 30 days, before a backup can matter. Never 0: older versions
# read that as "don't save transcripts at all".
{ config, lib, pkgs, ... }:

let
  cfg = config.devEnv.backup;
  home = config.home.homeDirectory;
  secretPath = name: config.sops.secrets.${name}.path;

  excluded = cfg.exclude
    ++ lib.concatMap (owner: map (root: "${root}/${owner}") config.devEnv.scopeRoots) cfg.excludeScopes;

  secretNames = lib.filter (s: s != null)
    [ cfg.secrets.repository cfg.secrets.password cfg.secrets.environment ];

  select = pkgs.writeShellApplication {
    name = "agent-sessions-select";
    runtimeInputs = [ pkgs.coreutils pkgs.findutils pkgs.jq ];
    text = ''
      include=(${lib.escapeShellArgs cfg.include})
      exclude=(${lib.escapeShellArgs excluded})
      shopt -s nullglob

      # under <dir> <prefix>...: is dir one of the prefixes or below one?
      under() {
        local d=$1 p
        shift
        for p in "$@"; do [[ $d == "$p" || $d == "$p"/* ]] && return 0; done
        return 1
      }

      # decide <folder>, cwds on stdin: print the folder if all are wanted.
      decide() {
        local dir=$1 cwd wanted=0 unwanted=0
        while IFS= read -r cwd; do
          [[ -n $cwd ]] || continue
          if under "$cwd" "''${exclude[@]}" || ! under "$cwd" "''${include[@]}"; then
            unwanted=1
          else
            wanted=1
          fi
        done
        if (( unwanted )); then
          (( wanted )) && echo "agent-sessions-select: skipping $dir: it mixes wanted and unwanted sessions" >&2
          return 0
        fi
        (( wanted )) && printf '%s\n' "$dir"
        return 0
      }

      # pi: the first line of every session file is a header with its cwd;
      # subagent runs nest their own session files inside the parent's folder.
      for dir in "$HOME/.pi/agent/sessions"/*/; do
        dir=''${dir%/}
        find "$dir" -name '*.jsonl' -print0 |
          while IFS= read -r -d "" f; do head -n1 "$f"; echo; done |
          jq -rR 'fromjson? | objects | select(.type == "session") | .cwd // empty' |
          decide "$dir"
      done

      # Claude Code: the first entry with a cwd, per transcript.
      for dir in "$HOME/.claude/projects"/*/; do
        dir=''${dir%/}
        for f in "$dir"/*.jsonl; do
          jq -rnR 'first(inputs | fromjson? | objects | .cwd // empty | select(. != ""))' "$f" || true
        done | decide "$dir"
      done
    '';
  };
in
{
  options.devEnv.backup = {
    enable = lib.mkEnableOption "hourly restic backups of agent sessions (pi, Claude Code)";

    include = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [ home ];
      description = "Sessions started at or below these directories are backed up.";
    };

    exclude = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [ ];
      description = "...unless they were started at or below one of these.";
    };

    excludeScopes = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [ ];
      example = [ "github.com/some-employer" ];
      description = ''"host/owner" prefixes to exclude under every devEnv.scopeRoots (~/source and the `wt` worktrees).'';
    };

    secrets = {
      repository = lib.mkOption {
        type = lib.types.str;
        default = "restic_repository";
        description = "Key in the sops file holding the restic repository.";
      };
      password = lib.mkOption {
        type = lib.types.str;
        default = "restic_password";
        description = "Key holding the repository password. Keep a copy outside the machine too: without it the backup can't be read.";
      };
      environment = lib.mkOption {
        type = lib.types.nullOr lib.types.str;
        default = "restic_env";
        description = "Key holding KEY=value lines for the backend (credentials), or null.";
      };
    };

    timerConfig = lib.mkOption {
      type = lib.types.attrs;
      default = { OnCalendar = "hourly"; Persistent = true; RandomizedDelaySec = "5m"; };
      description = "systemd timer settings for the backup.";
    };

    pruneOpts = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [ "--keep-hourly 48" "--keep-daily 30" "--keep-monthly 24" ];
      description = "`restic forget` options run after each backup.";
    };
  };

  config = lib.mkIf cfg.enable {
    assertions = [{
      assertion = config.devEnv.secrets.sopsFile != null;
      message = "devEnv.backup needs devEnv.secrets.sopsFile: the repository and its password come from it.";
    }];

    sops.secrets = lib.genAttrs secretNames (_: { });

    services.restic = {
      enable = true;
      backups.agent-sessions = {
        repositoryFile = secretPath cfg.secrets.repository;
        passwordFile = secretPath cfg.secrets.password;
        environmentFile =
          if cfg.secrets.environment == null then null else secretPath cfg.secrets.environment;
        dynamicFilesFrom = lib.getExe select;
        initialize = true;
        inherit (cfg) timerConfig pruneOpts;
      };
    };

    # The secrets are decrypted by sops-nix's own user service.
    systemd.user.services.restic-backups-agent-sessions.Unit = {
      After = [ "sops-nix.service" ];
      Wants = [ "sops-nix.service" ];
    };

    home.packages = [ select ];

    # Merged into the existing file rather than managed: `rtk init` writes it too.
    # Only once ~/.claude exists, so a first `claude` login still happens first.
    home.activation.claudeKeepTranscripts = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
      f=${lib.escapeShellArg "${home}/.claude/settings.json"}
      if [ -d "$(dirname "$f")" ] && [ ! -L "$f" ]; then
        current=$(${lib.getExe pkgs.jq} -r '.cleanupPeriodDays // empty' "$f" 2>/dev/null || true)
        if [ "$current" != 36500 ]; then
          tmp=$(mktemp "$f.XXXXXX")
          if [ ! -e "$f" ]; then
            echo '{ "cleanupPeriodDays": 36500 }' > "$tmp"
          elif ! ${lib.getExe pkgs.jq} '.cleanupPeriodDays = 36500' "$f" > "$tmp"; then
            rm -f "$tmp"; echo "devEnv.backup: $f isn't valid JSON, cleanupPeriodDays not set" >&2; tmp=
          fi
          [ -z "$tmp" ] || { chmod 644 "$tmp"; run mv "$tmp" "$f"; }
        fi
      fi
    '';
  };
}
