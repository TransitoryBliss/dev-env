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

    home.packages = [ pkgs.ghq devenvKeys ];

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
      typeset -g _WT_SRC=${lib.escapeShellArg "${home}/source"} _WT_ROOT=${lib.escapeShellArg cfg.worktreeRoot}
      source ${./wt.zsh}
    '';
  };
}
