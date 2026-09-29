# Git identity: a default GitHub account, plus overrides for specific orgs/users.
# Each account gets its own SSH key, ~/.ssh/id_ed25519_<account>.
# Repos are laid out as ~/source/<host>/<owner>/<repo> (use `ghq get owner/repo`).
#
#   devEnv.git = {
#     default = { account = "Foo"; name = "Foo Bar"; email = "foo@example.com"; };
#     overrides."github.com/some-org" = { account = "Bar"; name = "Bar"; email = "bar@example.com"; };
#   };
#
# Key selection works by URL, so it applies to every tool (git, ghq, go, npm):
# an override's URLs are rewritten to an SSH host alias ("github.com-Bar") that
# carries its key. Plain github.com uses the default key. Name and email are
# picked by the repo's remote URL or its path under ~/source.
#
# `wt` puts worktrees in devEnv.git.worktreeRoot, mirroring the ~/source layout
# (<root>/<host>/<owner>/<repo>/<branch>), so per-owner scopes apply there too:
# modules that scope by path (mcp, secrets) cover every devEnv.scopeRoots.
# Git identities need nothing extra: a worktree's gitdir is inside its main
# checkout's .git.
{ config, lib, pkgs, ... }:

let
  cfg = config.devEnv.git;
  home = config.home.homeDirectory;

  identityType = lib.types.submodule {
    options = {
      account = lib.mkOption {
        type = lib.types.str;
        description = "Login the SSH key is registered to; also names the key file.";
      };
      name = lib.mkOption { type = lib.types.str; };
      email = lib.mkOption { type = lib.types.str; };
    };
  };

  keyFor = id: "${home}/.ssh/id_ed25519_${id.account}";

  splitRemote = remote:
    let parts = lib.splitString "/" remote;
    in { host = lib.head parts; owner = lib.concatStringsSep "/" (lib.tail parts); };

  # Every way the same owner can be written in a remote URL.
  urlPrefixes = { host, owner, ... }: [
    "https://${host}/${owner}/"
    "git@${host}:${owner}/"
    "ssh://git@${host}/${owner}/"
  ];

  overrideList = lib.mapAttrsToList (remote: id: { inherit id; } // splitRemote remote) cfg.overrides;
  aliasFor = o: "${o.host}-${o.id.account}";

  identityIncludes = lib.concatMap (o:
    map (condition: {
      inherit condition;
      contents.user = { inherit (o.id) name email; };
    }) (map (p: "hasconfig:remote.*.url:${p}**") (urlPrefixes o)
        ++ [ "gitdir:${home}/source/${o.host}/${o.owner}/" ])
  ) overrideList;

  # Private repos over SSH even when cloned with an https URL (ghq's default).
  urlRewrites = lib.listToAttrs (
    [ (lib.nameValuePair "git@github.com:${cfg.default.account}/" {
        insteadOf = "https://github.com/${cfg.default.account}/";
      }) ]
    ++ map (o: lib.nameValuePair "git@${aliasFor o}:${o.owner}/" {
         insteadOf = urlPrefixes o;
       }) overrideList
  );

  sshBlocks = {
    "github.com" = {
      IdentityFile = keyFor cfg.default;
      IdentitiesOnly = "yes";
    };
  } // lib.listToAttrs (map (o: lib.nameValuePair (aliasFor o) {
    HostName = o.host;
    IdentityFile = keyFor o.id;
    IdentitiesOnly = "yes";
  }) overrideList);

  # One entry per account, even if several overrides share it.
  accounts = lib.attrValues (lib.listToAttrs (map (id: lib.nameValuePair id.account id)
    ([ cfg.default ] ++ lib.attrValues cfg.overrides)));

  # Creates missing SSH keys and prints where to register them.
  devenvKeys = pkgs.writeShellApplication {
    name = "devenv-keys";
    runtimeInputs = [ pkgs.openssh ];
    text = lib.concatMapStrings (id: ''
      if [ ! -f ${keyFor id} ]; then
        ssh-keygen -t ed25519 -f ${keyFor id} -C "${id.email} ($(hostname))"
      fi
      echo
      echo "== Add to the ${id.account} account (GitHub: https://github.com/settings/ssh/new):"
      cat ${keyFor id}.pub
    '') accounts;
  };

  wtEnv = ''
    typeset -g _WT_SRC=${lib.escapeShellArg "${home}/source"} _WT_ROOT=${lib.escapeShellArg cfg.worktreeRoot}
  '';

  # `wt gc --auto` outside an interactive shell: the systemd timer and the herdr
  # hook. Fetches must fail rather than prompt (no terminal, maybe no ssh-agent);
  # a failed fetch only makes wt keep more. herdr comes from the user's profile.
  wtGc = pkgs.writeScript "wt-gc" ''
    #!${pkgs.zsh}/bin/zsh -f
    export PATH=${lib.makeBinPath (with pkgs; [ git jq gh openssh coreutils util-linux gawk diffutils ])}:${config.home.profileDirectory}/bin:$PATH
    export GIT_TERMINAL_PROMPT=0 GIT_SSH_COMMAND='ssh -o BatchMode=yes'
    # The hook runs with the closed (or some other) workspace's ids; they mean nothing here.
    unset HERDR_WORKSPACE_ID HERDR_TAB_ID HERDR_PANE_ID
    ${wtEnv}
    source ${./wt.zsh}
    _wt_gc "$@"
  '';

  # `wt` as an executable, for callers that aren't zsh: pi's bash tool, `!` commands,
  # the pi extension. In zsh the function of the same name wins, which matters for
  # `wt done`: only the function can move your shell out of the checkout it deletes.
  wtBin = pkgs.writeScriptBin "wt" ''
    #!${pkgs.zsh}/bin/zsh -f
    export PATH=${lib.makeBinPath (with pkgs; [ git jq gh openssh coreutils util-linux gawk diffutils ])}:${config.home.profileDirectory}/bin:$PATH
    ${wtEnv}
    source ${./wt.zsh}
    wt "$@"
  '';

  # herdr records a linked plugin by its resolved path and re-reads the manifest on
  # every event, so the manifest is copied to a fixed place (not linked into the
  # store, whose path changes on each rebuild) and its command may change freely.
  wtPluginManifest = pkgs.writeText "herdr-plugin.toml" ''
    id = "dev-env.wt"
    name = "wt"
    version = "0.1.0"
    min_herdr_version = "0.7.0"
    description = "Remove merged git worktrees when a workspace closes (wt gc --auto)"
    platforms = ["linux", "macos"]

    [[events]]
    on = "workspace.closed"
    command = ["${wtGc}", "--auto"]
  '';
  wtPluginDir = "${config.xdg.dataHome}/wt/herdr-plugin";
in
{
  options.devEnv.git = {
    default = lib.mkOption {
      type = identityType;
      description = "GitHub identity and SSH key used unless an override matches.";
    };
    overrides = lib.mkOption {
      type = lib.types.attrsOf identityType;
      default = { };
      description = ''Identities for specific "host/owner" prefixes, e.g. "github.com/some-org".'';
    };
    worktreeRoot = lib.mkOption {
      type = lib.types.str;
      default = "${home}/.herdr/worktrees";
      description = ''
        Where `wt` puts worktrees, as <root>/<host>/<owner>/<repo>/<branch>: the
        ~/source layout, so per-owner scopes apply in them. Outside ~/source, so
        ghq doesn't list them as repos. Must be under the home directory.
      '';
    };
  };

  options.devEnv.scopeRoots = lib.mkOption {
    type = lib.types.listOf lib.types.str;
    readOnly = true;
    default = [ "${home}/source" cfg.worktreeRoot ];
    description = ''Directories laid out as <host>/<owner>/...: per-owner scopes (mcp, secrets) apply under each.'';
  };

  config = {
    assertions = [{
      assertion = lib.hasPrefix "${home}/" cfg.worktreeRoot;
      message = "devEnv.git.worktreeRoot must be under ${home}: scope files are placed there with home.file.";
    }];

    home.packages = [ pkgs.ghq devenvKeys wtBin ];

    programs.git = {
      enable = true;
      settings = {
        user = { inherit (cfg.default) name email; };
        url = urlRewrites;
        ghq.root = "${home}/source";
      };
      includes = identityIncludes;
    };

    programs.ssh = {
      enable = true;
      enableDefaultConfig = false;
      settings = sshBlocks;
    };

    # `repo [query]`: fuzzy-jump to a repo under ~/source.
    # `wt`: one worktree, herdr workspace and agent per task (see wt.zsh).
    programs.zsh.initContent = ''
      repo() {
        local dir
        dir=$(ghq list | fzf --query="$*" --select-1) && cd "$(ghq root)/$dir"
      }
      ${wtEnv}
      source ${./wt.zsh}
    '';

    # /wt done, /wt ls, /wt <branch> in pi, and a `wt` tool for the agent (start/list only).
    home.file.".pi/agent/extensions/wt.ts".source = ./wt-pi.ts;

    # Worktree cleanup without asking: hourly, and whenever a herdr workspace closes.
    # `wt gc --auto` only removes what loses nothing (see wt.zsh).
    systemd.user.services.wt-gc = {
      Unit.Description = "Remove merged git worktrees (wt gc --auto)";
      Service = {
        Type = "oneshot";
        ExecStart = "${wtGc} --auto";
      };
    };
    systemd.user.timers.wt-gc = {
      Unit.Description = "Remove merged git worktrees hourly";
      Timer = {
        OnCalendar = "hourly";
        Persistent = true;
        RandomizedDelaySec = "5m";
      };
      Install.WantedBy = [ "timers.target" ];
    };

    home.activation.wtHerdrPlugin = lib.hm.dag.entryAfter [ "linkGeneration" ] ''
      run mkdir -p ${lib.escapeShellArg wtPluginDir}
      run install -m 644 ${wtPluginManifest} ${lib.escapeShellArg "${wtPluginDir}/herdr-plugin.toml"}
      herdr=${config.home.path}/bin/herdr
      if [ -x "$herdr" ] && ! run "$herdr" plugin link ${lib.escapeShellArg wtPluginDir} >/dev/null 2>&1; then
        warnEcho "wt: couldn't link the herdr plugin; run: herdr plugin link ${wtPluginDir}"
      fi
    '';
  };
}
