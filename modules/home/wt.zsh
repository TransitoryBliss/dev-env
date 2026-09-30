# wt: one git worktree, herdr workspace and agent per task. `wt -h` for usage.
#
# Worktrees live in $_WT_ROOT/<host>/<owner>/<repo>/<branch> (devEnv.git.worktreeRoot,
# default ~/.herdr/worktrees): the ~/source layout, so per-owner scopes (MCP servers,
# secrets) apply in them too, but outside ~/source, so ghq doesn't list them as repos.
# A repo outside ~/source goes under local/<parent dir>/<repo>. herdr's `worktree remove` keeps the
# branch, so wt deletes it; that is safe because wt only removes a worktree when
# nothing would be lost (clean, and merged, squash-merged through a PR, or with no
# commits the default branch lacks), unless forced.
#
# `wt gc --auto` also runs by itself (modules/home/git.nix): hourly from a systemd
# user timer, and from a herdr plugin hook whenever a workspace closes.
#
# Sourced from ~/.zshrc by modules/home/git.nix. Needs git, jq, herdr; gh for
# squash-merge detection.

typeset -g _WT_SELF=${(%):-%N}
# Set by modules/home/git.nix before sourcing this; the defaults are for `zsh -f`.
typeset -g _WT_ROOT=${_WT_ROOT:-$HOME/.herdr/worktrees}
typeset -g _WT_SRC=${_WT_SRC:-$HOME/source}
typeset -g _WT_SEP=$'\x1f' # not a tab: `read` collapses runs of tabs, dropping empty fields

wt() {
  case $1 in
    done) shift; _wt_done "$@" ;;
    ls) shift; _wt_ls "$@" ;;
    gc) shift; _wt_gc "$@" ;;
    '' | -h | --help) _wt_usage ;;
    *) _wt_new "$@" ;;
  esac
}

_wt_usage() {
  print -r -- "wt [-b] [--plan] <branch> [prompt]
                           new worktree off the default branch, in its own herdr
                           workspace, with \$WT_AGENT (default: pi) started in it.
                           -b: stay where you are. An existing worktree is reopened.
                           --plan: start pi in plannotator's plan mode; the plan goes
                           to .wt/plan.md, kept out of git and saved to
                           ~/.local/state/wt/plans/ when the worktree is removed.
wt done [-f] [--check]     in a worktree: remove it and its branch, if nothing is lost.
                           -f: remove it anyway, uncommitted and unmerged work too.
                           --check: change nothing; print the state as JSON.
wt ls                      every worktree under ${_WT_ROOT/#$HOME/~}, with its state
wt gc [-n]                 remove merged ones, and closed ones with no new commits.
                           -n: only say what would go. Also runs by itself, hourly
                           and whenever a herdr workspace closes.

States: dirty (uncommitted changes), merged (a merged PR has this exact commit),
in-base (no commits the default branch lacks: new, or merged normally), unmerged,
orphan (its main checkout is gone)."
}

# Where a new worktree of main checkout $1 for branch $2 goes: the checkout's path
# under ~/source, mirrored under $_WT_ROOT.
_wt_path() {
  local main=${1:A} rel
  if [[ $main == ${_WT_SRC:A}/?* ]]; then
    rel=${main#${_WT_SRC:A}/}
  else
    rel=local/${main:h:t}/${main:t}
  fi
  print -r -- $_WT_ROOT/$rel/$2
}

# Main checkout of the repo that $1 belongs to.
_wt_main() {
  local common
  common=$(git -C "$1" rev-parse --path-format=absolute --git-common-dir 2>/dev/null) || return 1
  print -r -- ${common:h}
}

_wt_fetch() {
  git -C "$1" remote get-url origin >/dev/null 2>&1 && git -C "$1" fetch -q origin 2>/dev/null
  return 0
}

# The ref new branches start from, and that "merged" is measured against.
_wt_base() {
  local ref
  if ref=$(git -C "$1" symbolic-ref -q --short refs/remotes/origin/HEAD); then
    print -r -- $ref; return
  fi
  for ref in origin/main origin/master main master; do
    git -C "$1" rev-parse -q --verify "$ref^{commit}" >/dev/null && { print -r -- $ref; return }
  done
  print HEAD
}

# _wt_state <dir> <base>: dirty, merged, in-base or unmerged.
_wt_state() {
  local dir=$1 base=$2 branch tip
  [[ -z $(git -C "$dir" status --porcelain 2>/dev/null) ]] || { print dirty; return }
  branch=$(git -C "$dir" branch --show-current)
  tip=$(git -C "$dir" rev-parse HEAD)
  # A squash merge never makes the branch an ancestor of base, so ask GitHub. Only a
  # PR whose head is this exact commit counts: commits pushed after the merge aren't.
  if [[ -n $branch ]] && (( $+commands[gh] )) &&
    [[ -n $(cd -q "$dir" && gh pr list --head "$branch" --state merged \
      --json headRefOid --jq ".[] | select(.headRefOid == \"$tip\") | .headRefOid" 2>/dev/null) ]]; then
    print merged; return
  fi
  git -C "$dir" merge-base --is-ancestor HEAD "$base" 2>/dev/null && { print in-base; return }
  print unmerged
}

# "<checkout path><sep><workspace id>" for each open herdr worktree workspace.
_wt_workspaces() {
  (( $+commands[herdr] )) || return 0
  herdr workspace list 2>/dev/null | jq -r --arg s "$_WT_SEP" \
    '.result.workspaces[] | select(.worktree.checkout_path) | "\(.worktree.checkout_path)\($s)\(.workspace_id)"'
}

_wt_workspace_of() {
  local p id
  _wt_workspaces | while IFS=$_WT_SEP read -r p id; do
    [[ ${p:A} == ${1:A} ]] && { print -r -- $id; return }
  done
}

# Linked worktrees under $_WT_ROOT (their .git is a file): <host>/<owner>/<repo>/<branch>,
# with up to three more levels for slashes in the branch or nested owners (GitLab groups).
_wt_dirs() {
  local g
  for g in $_WT_ROOT/*/*/*/*/.git(N.) $_WT_ROOT/*/*/*/*/*/.git(N.) \
    $_WT_ROOT/*/*/*/*/*/*/.git(N.) $_WT_ROOT/*/*/*/*/*/*/*/.git(N.); do
    # A submodule inside a worktree has a .git file too.
    [[ -z $(git -C "${g:h}" rev-parse --show-superproject-working-tree 2>/dev/null) ]] &&
      print -r -- ${g:h}
  done
}

# One "dir main branch state workspace age" line ($_WT_SEP-separated) per worktree.
_wt_scan() {
  local d main branch state age p id
  local -A base open
  while IFS=$_WT_SEP read -r p id; do open[${p:A}]=$id; done < <(_wt_workspaces)
  for d in ${(f)"$(_wt_dirs)"}; do
    if ! main=$(_wt_main "$d") || [[ ! -d $main ]]; then
      print -r -- "$d$_WT_SEP$_WT_SEP$_WT_SEP""orphan$_WT_SEP${open[${d:A}]}$_WT_SEP"
      continue
    fi
    (( $+base[$main] )) || { _wt_fetch "$main"; base[$main]=$(_wt_base "$main") }
    branch=$(git -C "$d" branch --show-current)
    state=$(_wt_state "$d" "$base[$main]")
    age=$(git -C "$d" log -1 --format=%cr)
    print -r -- "$d$_WT_SEP$main$_WT_SEP$branch$_WT_SEP$state$_WT_SEP${open[${d:A}]}$_WT_SEP$age"
  done
}

# _wt_remove <dir> <main> <branch> <workspace id or ""> <force: "" or 1>
# Copies a worktree's .wt/ (plans from `wt --plan`) to
# ~/.local/state/wt/plans/<host>/<owner>/<repo>/<branch>-<time>/, if it has any markdown.
_wt_save_plan() {
  local dir=$1 rel dest
  local -a plans=($dir/.wt/**/*.md(N.) $dir/.wt/**/*.mdx(N.))
  (( $#plans )) || return 0
  rel=${${dir:A}#${_WT_ROOT:A}/}
  [[ $rel != /* ]] || rel=local/${dir:t}
  dest=${XDG_STATE_HOME:-$HOME/.local/state}/wt/plans/$rel-$(date +%Y%m%d-%H%M%S)
  mkdir -p "$dest" && cp -R "$dir/.wt/." "$dest/" || return 1
  print -r -- "wt: saved plan to ${dest/#$HOME/~}"
}

# Excludes /.wt/ in the repo's own info/exclude (shared by all its worktrees): no
# global gitignore, and no change to a tracked .gitignore.
_wt_exclude() {
  local ex
  ex=$(git -C "$1" rev-parse --path-format=absolute --git-common-dir)/info/exclude || return
  mkdir -p "${ex:h}"
  grep -qxF '/.wt/' "$ex" 2>/dev/null || print -r -- '/.wt/' >>"$ex"
}

_wt_remove() {
  local dir=$1 main=$2 branch=$3 wsid=$4 force=$5 d
  # Save the plan first; if that fails, keep the worktree rather than lose it.
  _wt_save_plan "$dir" || { print -u2 "wt: couldn't save the plan in $dir/.wt; not removing it"; return 1 }
  if [[ -n $wsid ]]; then
    herdr worktree remove --workspace "$wsid" ${force:+--force} >/dev/null || return
  else
    git -C "$main" worktree remove ${force:+--force} "$dir" || return
  fi
  [[ -z $branch ]] || git -C "$main" branch -q -D "$branch"
  git -C "$main" worktree prune
  # herdr leaves the empty <repo> directory (and a/ for a branch a/b) behind. Owner
  # directories with scope files (.mcp.json) aren't empty, so they stay.
  d=${dir:h}
  while [[ $d == $_WT_ROOT/?* ]] && rmdir "$d" 2>/dev/null; do d=${d:h}; done
  return 0
}

_wt_new() {
  local focus=--focus plan
  while [[ $1 == -* ]]; do
    case $1 in
      -b) focus=--no-focus ;;
      --plan) plan=1 ;;
      *) print -u2 "wt: unknown option $1"; return 2 ;;
    esac
    shift
  done
  local branch=$1 prompt=$2 agent=${WT_AGENT:-pi} main base out pane dir existing
  [[ -n $branch ]] || { _wt_usage; return 2 }
  if [[ -n $plan ]]; then
    # An array, not ${${(z)agent}[1]}: for a one-word agent that takes the first letter.
    local -a words=(${(z)agent})
    [[ ${words[1]:t} == pi ]] || { print -u2 "wt: --plan needs pi, not $agent"; return 1 }
    # Without a prompt the agent picks its own plan file (PLAN.md), which git sees.
    [[ -n $prompt ]] || { print -u2 "wt: --plan needs a prompt saying what to plan"; return 2 }
  fi
  [[ -n $HERDR_ENV ]] || { print -u2 "wt: run it inside herdr"; return 1 }
  main=$(_wt_main .) || { print -u2 "wt: not in a git repo"; return 1 }

  existing=$(git -C "$main" worktree list --porcelain |
    awk -v b="branch refs/heads/$branch" '/^worktree /{p=substr($0,10)} $0==b{print p; exit}')
  if [[ -n $existing ]]; then
    [[ ${existing:A} != ${main:A} ]] || { print -u2 "wt: $branch is checked out in $main"; return 1 }
    herdr worktree open --cwd "$main" --path "$existing" $focus >/dev/null
    return
  fi

  _wt_fetch "$main"
  base=$(_wt_base "$main")
  out=$(herdr worktree create --cwd "$main" --branch "$branch" --base "$base" \
    --path "$(_wt_path "$main" "$branch")" --label "$branch" $focus) || return
  pane=$(jq -r '.result.root_pane.pane_id // empty' <<<"$out")
  dir=$(jq -r '.result.worktree.path // empty' <<<"$out")
  [[ -n $pane ]] || { print -u2 "wt: unexpected reply from herdr: $out"; return 1 }
  # Carry direnv trust over, but only for an .envrc identical to the main checkout's.
  [[ -f $dir/.envrc ]] && cmp -s "$dir/.envrc" "$main/.envrc" && direnv allow "$dir"
  if [[ -n $plan ]]; then
    _wt_exclude "$main"
    # One line: it's typed into the pane's shell.
    prompt="$prompt (Write the plan to .wt/plan.md: that directory is kept out of git and saved when the worktree is removed.)"
  fi
  # --plan goes after the prompt: pi parses the command line before plannotator
  # registers --plan as a boolean, so `--plan '<prompt>'` swallows the prompt as
  # the flag's value and pi starts with no first message.
  herdr pane run "$pane" "$agent${prompt:+ ${(qq)prompt}}${plan:+ --plan}" >/dev/null
  [[ $focus == --focus ]] || print -r -- "wt: $branch started in ${dir/#$HOME/~}"
}

# wt done [-f] [--check]. --check (for the pi extension) changes nothing and prints
# {dir, main, branch, base, state, safe, workspace, closes_this}. $WT_DONE_DELAY
# delays a detached removal by that many seconds, so whatever runs in the closing
# workspace (pi) can exit first.
_wt_done() {
  local force check dir main branch base state wsid log
  while (( $# )); do
    case $1 in
      -f) force=1 ;;
      --check) check=1 ;;
      *) print -u2 "wt done: unknown option $1"; return 2 ;;
    esac
    shift
  done
  dir=$(git rev-parse --show-toplevel 2>/dev/null) || { print -u2 "wt: not in a git repo"; return 1 }
  main=$(_wt_main "$dir")
  [[ ${dir:A} != ${main:A} ]] || { print -u2 "wt: $dir is the main checkout, not a worktree"; return 1 }
  branch=$(git -C "$dir" branch --show-current)
  if [[ -z $force || -n $check ]]; then
    _wt_fetch "$main"
    base=$(_wt_base "$main")
    state=$(_wt_state "$dir" "$base")
  fi
  wsid=$(_wt_workspace_of "$dir")
  if [[ -n $check ]]; then
    local -a plans=($dir/.wt/**/*.md(N.) $dir/.wt/**/*.mdx(N.))
    jq -n --arg dir "$dir" --arg main "$main" --arg branch "$branch" --arg base "$base" \
      --arg state "$state" --arg ws "$wsid" --arg here "$HERDR_WORKSPACE_ID" \
      --argjson plan $(( $#plans > 0 )) \
      '{dir: $dir, main: $main, branch: $branch, base: $base, state: $state,
        safe: ($state == "merged" or $state == "in-base"), workspace: $ws,
        closes_this: ($ws != "" and $ws == $here), has_plan: ($plan == 1)}'
    return
  fi
  if [[ -z $force ]]; then
    case $state in
      dirty) print -u2 "wt: uncommitted changes in $dir (wt done -f throws them away)"; return 1 ;;
      unmerged) print -u2 "wt: $branch has commits $base lacks and no merged PR (wt done -f deletes them)"; return 1 ;;
    esac
  fi
  cd "$main" # leave the checkout before it goes
  if [[ -n $wsid && $wsid == $HERDR_WORKSPACE_ID ]]; then
    # Removing it closes this workspace, and this shell with it: finish detached.
    log=${XDG_STATE_HOME:-$HOME/.local/state}/wt.log
    mkdir -p "${log:h}"
    print -r -- "wt: removing ${dir/#$HOME/~}; this workspace will close"
    setsid -f zsh -fc "sleep ${(q)${WT_DONE_DELAY:-0}}; _WT_ROOT=${(q)_WT_ROOT} _WT_SRC=${(q)_WT_SRC}; source ${(q)_WT_SELF}; _wt_remove ${(q)dir} ${(q)main} ${(q)branch} ${(q)wsid} ${(q)force}" \
      </dev/null >>$log 2>&1
  else
    _wt_remove "$dir" "$main" "$branch" "$wsid" "$force" && print -r -- "wt: removed ${dir/#$HOME/~}"
  fi
}

_wt_ls() {
  local d main branch state wsid age n=0
  _wt_scan | while IFS=$_WT_SEP read -r d main branch state wsid age; do
    (( n++ )) || printf '%-9s %-5s %-16s %s\n' STATE OPEN 'LAST COMMIT' WORKTREE
    printf '%-9s %-5s %-16s %s\n' "$state" "${wsid:+yes}" "$age" "${d#$_WT_ROOT/}"
  done
  (( n )) || print "wt: no worktrees under ${_WT_ROOT/#$HOME/~}"
}

# Reports a kept worktree, except in --auto runs (which only report removals).
# Reads $auto from _wt_gc through zsh's dynamic scoping.
_wt_keep() { [[ -n $auto ]] || print -r -- "keep    $1" }

# wt gc [-n] [--auto]. --auto is for unattended runs (timer, herdr hook): it skips
# instead of waiting when another gc runs, spares the workspace you're looking at,
# only prints removals, and shows a herdr notification for them.
# One scan-and-remove pass of _wt_gc. Reads dry, auto and removed from _wt_gc
# (dynamic scoping). Returns 1, removing nothing, if herdr doesn't answer.
_wt_gc_pass() {
  local focused d main branch state wsid age name why
  # Open workspaces are what protect a started task. If herdr doesn't answer, every
  # worktree would look closed, so remove nothing. Asked each pass: a pass that
  # follows a close event must see that workspace as closed.
  if ! (( $+commands[herdr] )) || ! focused=$(herdr workspace list 2>/dev/null |
    jq -er '[.result.workspaces[] | select(.focused) | .workspace_id] | join(" ")'); then
    print -u2 "wt: herdr isn't answering, so there's no telling which worktrees are open; removing nothing"
    return 1
  fi
  _wt_scan | while IFS=$_WT_SEP read -r d main branch state wsid age; do
    name=${d#$_WT_ROOT/}
    case $state in
      merged) why='PR merged' ;;
      in-base)
        # An open one with no commits is usually a task that has just started.
        [[ -z $wsid ]] || { _wt_keep "$name: no commits yet, but open"; continue }
        why='no commits beyond the default branch' ;;
      *) _wt_keep "$name: $state"; continue ;;
    esac
    if [[ -n $wsid && $wsid == $HERDR_WORKSPACE_ID ]]; then
      _wt_keep "$name: you're in it, use wt done"; continue
    fi
    if [[ -n $auto && -n $wsid && " $focused " == *" $wsid "* ]]; then
      continue # on screen right now; the next run gets it
    fi
    if [[ -n $dry ]]; then
      print -r -- "remove  $name ($why)"
    elif _wt_remove "$d" "$main" "$branch" "$wsid" "" </dev/null; then
      removed+=($name)
      print -r -- "removed $name ($why)"
    fi
  done
  return 0
}

_wt_gc() {
  local dry auto wait=120 lock lockfd again rc=0 s=s
  local -a removed
  while (( $# )); do
    case $1 in
      -n) dry=1 ;;
      --auto) auto=1; wait=0 ;;
      *) print -u2 "wt gc: unknown option $1"; return 2 ;;
    esac
    shift
  done
  # One gc at a time: the hook fires again for every workspace a gc closes, and
  # several close events can arrive within milliseconds.
  zmodload zsh/system || return 1
  lock=${XDG_STATE_HOME:-$HOME/.local/state}/wt-gc.lock
  again=$lock.again
  mkdir -p "${lock:h}" && : >>"$lock" # zsystem flock doesn't create the file
  if ! zsystem flock -t $wait -f lockfd "$lock" 2>/dev/null; then
    # The running gc may have scanned before our event: ask it for another pass
    # instead of dropping the event.
    [[ -n $auto ]] && { : >>"$again"; return 0 }
    print -u2 "wt: another wt gc is still running"; return 1
  fi
  while :; do
    {
      while :; do
        rm -f "$again"
        _wt_gc_pass || { rc=1; break }
        [[ -e $again ]] || break
      done
    } always {
      zsystem flock -u $lockfd
    }
    # A request that came in between the last check and the unlock. If someone else
    # holds the lock by now, it's theirs to handle.
    [[ $rc == 0 && -e $again ]] && zsystem flock -t 0 -f lockfd "$lock" 2>/dev/null || break
  done
  if [[ -n $auto ]] && (( $#removed )); then
    (( $#removed == 1 )) && s=
    herdr notification show "wt: removed $#removed worktree$s" --body "${(j:, :)removed}" >/dev/null 2>&1
  fi
  # Unattended runs never fail loudly (systemd, the hook); a manual one says so.
  [[ -n $auto ]] && return 0 || return $rc
}
