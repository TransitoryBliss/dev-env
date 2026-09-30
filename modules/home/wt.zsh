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
# `wt task` groups worktrees of several repos of one org into one piece of work: one
# branch name, one herdr workspace, one lead pi session, and the order the PRs merge
# in. See "tasks" at the end.
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
    task) shift; _wt_task "$@" ;;
    status) shift; _wt_task_status "$@" ;;
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

wt task [-b] [--plan | --from-plan <file>] <name> <repo>... [-- <prompt>]
                           in an org folder (or a repo) under ~/source: one task across
                           repos of that org, listed in the order their PRs merge. Each
                           gets a worktree on branch <name>; one herdr workspace holds a
                           lead pi session (in the task folder) and a tab per repo.
                           Again with more repos: adds them. --from-plan: the approved
                           plan the lead implements.
wt task status [name]      each repo's PR, checks, and what it waits for (also: wt status)
wt task done [-f] [name]   remove every worktree, branch and the task, if nothing is lost
wt task ls                 every task

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
    # Task folders only hold links to worktrees (and GLOB_DOTS may be on).
    [[ $g == */.tasks/* ]] && continue
    # A submodule inside a worktree has a .git file too.
    [[ -z $(git -C "${g:h}" rev-parse --show-superproject-working-tree 2>/dev/null) ]] &&
      print -r -- ${g:h}
  done
}

# One "dir main branch state workspace age task task-open" line ($_WT_SEP-separated)
# per worktree.
_wt_scan() {
  local d main branch state age p id t r topen
  local -A base open task opentask
  while IFS=$_WT_SEP read -r p id; do open[${p:A}]=$id; done < <(_wt_workspaces)
  # Task worktrees aren't herdr worktrees: they count as open while their task is.
  for t in $_WT_ROOT/*/*/.tasks/*/task.json(N.); do
    topen=; _wt_task_open ${t:h} && topen=1
    for r in ${(f)"$(jq -r '.repos[].dir' $t 2>/dev/null)"}; do
      task[${r:A}]=${t:h:t}; opentask[${r:A}]=$topen
    done
  done
  for d in ${(f)"$(_wt_dirs)"}; do
    if ! main=$(_wt_main "$d") || [[ ! -d $main ]]; then
      print -r -- "$d$_WT_SEP$_WT_SEP$_WT_SEP""orphan$_WT_SEP${open[${d:A}]}$_WT_SEP$_WT_SEP${task[${d:A}]}$_WT_SEP${opentask[${d:A}]}"
      continue
    fi
    (( $+base[$main] )) || { _wt_fetch "$main"; base[$main]=$(_wt_base "$main") }
    branch=$(git -C "$d" branch --show-current)
    state=$(_wt_state "$d" "$base[$main]")
    age=$(git -C "$d" log -1 --format=%cr)
    print -r -- "$d$_WT_SEP$main$_WT_SEP$branch$_WT_SEP$state$_WT_SEP${open[${d:A}]}$_WT_SEP$age$_WT_SEP${task[${d:A}]}$_WT_SEP${opentask[${d:A}]}"
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
  # A command name is never a branch: `wt -b status` would otherwise make one.
  if [[ $branch == (done|ls|gc|task|status) ]]; then
    print -u2 "wt: \"$branch\" is a wt command, not a branch name"
    print -u2 "usage: wt [-b] [--plan] <branch> [prompt]"
    return 2
  fi
  # The branch comes first: `wt --plan "<prompt>"` would otherwise take the prompt as
  # the branch and then complain that the prompt is missing.
  if ! git check-ref-format --branch "$branch" >/dev/null 2>&1; then
    if [[ $branch == *[[:space:]]* ]]; then
      print -u2 "wt: \"$branch\" looks like a prompt, not a branch name; the branch comes first"
    else
      print -u2 "wt: \"$branch\" isn't a valid branch name"
    fi
    print -u2 "usage: wt [-b] [--plan] <branch> [prompt]"
    return 2
  fi
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
  # In a task's own folder (where its lead session runs), done means the whole task.
  local td
  if td=$(_wt_task_find) && [[ ${PWD:A} == ${td:A} || ${PWD:A} == ${td:A}/* ]]; then
    _wt_task_done "$@"; return
  fi
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
  local d main branch state wsid age task topen n=0
  _wt_scan | while IFS=$_WT_SEP read -r d main branch state wsid age task topen; do
    (( n++ )) || printf '%-9s %-5s %-16s %-20s %s\n' STATE OPEN 'LAST COMMIT' TASK WORKTREE
    printf '%-9s %-5s %-16s %-20s %s\n' "$state" "${${wsid:-$topen}:+yes}" "$age" "${task:--}" "${d#$_WT_ROOT/}"
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
  local focused d main branch state wsid age task topen name why t td r left
  # Open workspaces are what protect a started task. If herdr doesn't answer, every
  # worktree would look closed, so remove nothing. Asked each pass: a pass that
  # follows a close event must see that workspace as closed.
  if ! (( $+commands[herdr] )) || ! focused=$(herdr workspace list 2>/dev/null |
    jq -er '[.result.workspaces[] | select(.focused) | .workspace_id] | join(" ")'); then
    print -u2 "wt: herdr isn't answering, so there's no telling which worktrees are open; removing nothing"
    return 1
  fi
  _wt_scan | while IFS=$_WT_SEP read -r d main branch state wsid age task topen; do
    name=${d#$_WT_ROOT/}
    # A task's workspace holds all its repos: a merged one stays until the task closes.
    [[ -z $topen ]] || { _wt_keep "$name: part of task $task, which is open"; continue }
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
  # A closed task whose worktrees are all gone: save its plan, drop its folder.
  for t in $_WT_ROOT/*/*/.tasks/*/task.json(N.); do
    td=${t:h}; name=${td#$_WT_ROOT/}; left=0
    for r in ${(f)"$(jq -r '.repos[].dir' $t 2>/dev/null)"}; do [[ -d $r ]] && (( left++ )); done
    (( left )) && continue
    _wt_task_open $td && { _wt_keep "$name: its worktrees are gone, but it's open"; continue }
    if [[ -n $dry ]]; then
      print -r -- "remove  $name (task with no worktrees left)"
    elif _wt_task_save $td && rm -rf "$td"; then
      rmdir "${td:h}" 2>/dev/null
      removed+=($name)
      print -r -- "removed $name (task with no worktrees left)"
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

# ---- tasks ----
#
# A task lives in $_WT_ROOT/<host>/<owner>/.tasks/<name>/: task.json (its repos in the
# order their PRs merge, each with the repos it waits for), an AGENTS.md that tells
# the lead pi session about them, links to the worktrees, and plan.md if planned.
# Its worktrees sit where `wt` always puts them, on branch <name>, so per-owner
# scopes apply. herdr doesn't know them as worktrees: a task counts as open while
# any herdr pane is in its folder or one of its worktrees (or for two minutes after
# task.json changed, which covers creating it), and gc keeps an open task's
# worktrees, merged ones too.

# host/owner of the org that $1 is in (under ~/source or the worktree root).
_wt_org() {
  local d=${1:A} root rel
  local -a parts
  for root in ${_WT_SRC:A} ${_WT_ROOT:A}; do
    [[ $d == $root/?* ]] || continue
    rel=${d#$root/}; parts=(${(s:/:)rel})
    (( $#parts >= 2 )) && [[ $parts[1] != local ]] && { print -r -- $parts[1]/$parts[2]; return 0 }
  done
  return 1
}

# The task folder for task $1, or (no name) the task that $PWD is in.
_wt_task_find() {
  local name=$1 org t r here=${PWD:A}
  if [[ -n $name ]]; then
    org=$(_wt_org .) && [[ -f $_WT_ROOT/$org/.tasks/$name/task.json ]] &&
      { print -r -- $_WT_ROOT/$org/.tasks/$name; return 0 }
    local -a hits=($_WT_ROOT/*/*/.tasks/$name/task.json(N.))
    (( $#hits == 1 )) && { print -r -- ${hits[1]:h}; return 0 }
    (( $#hits > 1 )) && print -u2 "wt: several orgs have a task called $name; run it in the org folder"
    return 1
  fi
  for t in $_WT_ROOT/*/*/.tasks/*/task.json(N.); do
    [[ $here == ${t:h:A} || $here == ${t:h:A}/* ]] && { print -r -- ${t:h}; return 0 }
    for r in ${(f)"$(jq -r '.repos[].dir' $t 2>/dev/null)"}; do
      [[ $here == ${r:A} || $here == ${r:A}/* ]] && { print -r -- ${t:h}; return 0 }
    done
  done
  return 1
}

# herdr workspaces with a pane in task folder $1 or one of its worktrees.
_wt_task_workspaces() {
  (( $+commands[herdr] )) || return 0
  local td=${1:A} r ws c f
  local -a roots=($td)
  for r in ${(f)"$(jq -r '.repos[].dir' $1/task.json 2>/dev/null)"}; do roots+=(${r:A}); done
  herdr pane list 2>/dev/null |
    jq -r --arg s "$_WT_SEP" '.result.panes[] | "\(.workspace_id)\($s)\(.cwd // "")\($s)\(.foreground_cwd // "")"' |
    while IFS=$_WT_SEP read -r ws c f; do
      for r in $roots; do
        if [[ -n $c && ( $c == $r || $c == $r/* ) ]] || [[ -n $f && ( $f == $r || $f == $r/* ) ]]; then
          print -r -- $ws; break
        fi
      done
    done | sort -u
}

_wt_task_open() {
  local -a fresh=($1/task.json(Nmm-2))
  (( $#fresh )) && return 0
  [[ -n $(_wt_task_workspaces $1) ]]
}

# Copies task folder $1 (without its links) to ~/.local/state/wt/plans/<host>/<owner>/
# tasks/<name>-<time>/, if it has a plan (markdown besides AGENTS.md).
_wt_task_save() {
  local td=$1 rel dest
  local -a plans=($td/**/*.(md|mdx)(N.))  # ** doesn't follow the links into worktrees
  plans=(${plans:#$td/AGENTS.md})
  (( $#plans )) || return 0
  rel=${${td:A}#${_WT_ROOT:A}/}
  dest=${XDG_STATE_HOME:-$HOME/.local/state}/wt/plans/${rel/\/.tasks\//\/tasks\/}-$(date +%Y%m%d-%H%M%S)
  mkdir -p "$dest" && cp -R "$td/." "$dest/" || return 1
  find "$dest" -type l -delete
  print -r -- "wt: saved the task's plan to ${dest/#$HOME/~}"
}

# _wt_task_remove <task folder> <force: "" or 1>: every worktree and branch, then the folder.
_wt_task_remove() {
  local td=$1 force=$2 e n dir main rc=0
  for e in ${(f)"$(jq -r --arg s "$_WT_SEP" '.repos[] | "\(.name)\($s)\(.dir)\($s)\(.main)"' $td/task.json)"}; do
    IFS=$_WT_SEP read -r n dir main <<<"$e"
    [[ -d $dir ]] || continue
    _wt_remove "$dir" "$main" "$(git -C "$dir" branch --show-current)" "" "$force" </dev/null || rc=1
  done
  (( rc )) && { print -u2 "wt: kept ${td/#$HOME/~}: not every worktree could be removed"; return 1 }
  _wt_task_save $td || { print -u2 "wt: couldn't save the task's plan; keeping ${td/#$HOME/~}"; return 1 }
  rm -rf "$td"; rmdir "${td:h}" 2>/dev/null
  return 0
}

_wt_task() {
  case $1 in
    status) shift; _wt_task_status "$@" ;;
    done) shift; _wt_task_done "$@" ;;
    ls) shift; _wt_task_ls "$@" ;;
    '' | -h | --help) _wt_usage ;;
    *) _wt_task_new "$@" ;;
  esac
}

_wt_task_new() {
  local focus=--focus plan from
  while [[ $1 == -* && $1 != -- ]]; do
    case $1 in
      -b) focus=--no-focus ;;
      --plan) plan=1 ;;
      --from-plan) from=$2; shift ;;
      *) print -u2 "wt task: unknown option $1"; return 2 ;;
    esac
    shift
  done
  local name=$1 prompt agent=${WT_AGENT:-pi} org td t r m main dir base existing prev new lead e
  local usage="usage: wt task [-b] [--plan | --from-plan <file>] <name> <repo>... [-- <prompt>]"
  local -a repos mains added words open_ws
  [[ -n $name ]] || { print -u2 $usage; return 2 }
  shift
  while (( $# )) && [[ $1 != -- ]]; do repos+=($1); shift; done
  [[ $1 == -- ]] && { shift; prompt="$*" }

  if [[ $name != [A-Za-z0-9]* || $name == *[^A-Za-z0-9._-]* ]] ||
    ! git check-ref-format --branch "$name" >/dev/null 2>&1; then
    if [[ $name == *[[:space:]]* ]]; then
      print -u2 "wt: \"$name\" looks like a prompt, not a task name; the name comes first"
    else
      print -u2 "wt: \"$name\" isn't a valid task name (letters, digits, . _ -)"
    fi
    print -u2 $usage; return 2
  fi
  [[ $name == (status|done|ls) ]] && { print -u2 "wt: \"$name\" is a wt task command, not a name"; return 2 }
  [[ -n $plan && -n $from ]] && { print -u2 "wt: --plan and --from-plan don't go together"; return 2 }
  if [[ -n $plan ]]; then
    words=(${(z)agent})
    [[ ${words[1]:t} == pi ]] || { print -u2 "wt: --plan needs pi, not $agent"; return 1 }
    [[ -n $prompt ]] || { print -u2 "wt: --plan needs a prompt saying what to plan (after --)"; return 2 }
  fi
  if [[ -n $from ]]; then
    [[ -f $from ]] || { print -u2 "wt: no plan file $from"; return 1 }
    from=${from:A}
  fi
  [[ -n $HERDR_ENV ]] || { print -u2 "wt: run it inside herdr"; return 1 }
  org=$(_wt_org .) || { print -u2 "wt: run it in an org folder (or a repo) under ${_WT_SRC/#$HOME/~}"; return 1 }
  td=$_WT_ROOT/$org/.tasks/$name; t=$td/task.json
  [[ -f $t ]] || new=1
  [[ -z $new ]] || (( $#repos )) || { print -u2 "wt: which repos?"; print -u2 $usage; return 2 }

  # Check every repo before creating anything.
  for r in $repos; do
    if [[ $r == */* ]]; then
      [[ ${r%/*} == ${org#*/} ]] || { print -u2 "wt: $r isn't in ${org#*/}; a task stays in one org"; return 1 }
      r=${r#*/}
    fi
    m=$_WT_SRC/$org/$r
    main=$(_wt_main "$m" 2>/dev/null) && [[ ${main:A} == ${m:A} ]] ||
      { print -u2 "wt: no checkout of $r at ${m/#$HOME/~} (ghq get ${org#*/}/$r)"; return 1 }
    mains+=($main)
  done

  mkdir -p $td || return 1
  [[ -f $t ]] || jq -n --arg n $name --arg org $org --arg at "$(date -Iseconds)" \
    '{name: $n, org: $org, created: $at, repos: []}' >$t || return 1
  for main in $mains; do
    r=${main:t}
    [[ -n $(jq -r --arg r $r '.repos[] | select(.name == $r) | .name' $t) ]] && continue
    existing=$(git -C "$main" worktree list --porcelain |
      awk -v b="branch refs/heads/$name" '/^worktree /{p=substr($0,10)} $0==b{print p; exit}')
    if [[ -n $existing ]]; then
      [[ ${existing:A} != ${main:A} ]] || { print -u2 "wt: $name is checked out in $main itself"; return 1 }
      dir=$existing
    else
      dir=$(_wt_path "$main" "$name")
      _wt_fetch "$main"; base=$(_wt_base "$main")
      mkdir -p "${dir:h}"
      if git -C "$main" rev-parse -q --verify "refs/heads/$name" >/dev/null; then
        git -C "$main" worktree add -q "$dir" "$name" || return 1
      else
        # --no-track: a push without -u must not go to the default branch.
        git -C "$main" worktree add -q --no-track -b "$name" "$dir" "$base" || return 1
      fi
      [[ -f $dir/.envrc ]] && cmp -s "$dir/.envrc" "$main/.envrc" && direnv allow "$dir"
    fi
    # A chain: each repo merges after the one before it.
    prev=$(jq -r '.repos[-1].name // empty' $t)
    jq --arg r $r --arg m $main --arg d ${dir:A} --arg p "$prev" \
      '.repos += [{name: $r, main: $m, dir: $d, after: (if $p == "" then [] else [$p] end)}]' \
      $t >$t.tmp && mv $t.tmp $t || return 1
    ln -sfn "${dir:A}" "$td/$r"
    added+=($r)
  done
  if [[ -n $from && $from != ${td:A}/plan.md ]]; then
    cp "$from" $td/plan.md || return 1
    # A plan written in an org folder moves into the task; one inside a repo stays.
    git -C "${from:h}" rev-parse --is-inside-work-tree >/dev/null 2>&1 || rm -f "$from"
  fi
  _wt_task_agents $td

  open_ws=(${(f)"$(_wt_task_workspaces $td)"})
  if (( $#open_ws )); then
    for r in $added; do
      herdr tab create --workspace $open_ws[1] --label $r --no-focus \
        --cwd "$(jq -r --arg r $r '.repos[] | select(.name == $r) | .dir' $t)" >/dev/null
    done
    [[ $focus == --focus ]] && herdr workspace focus $open_ws[1] >/dev/null
    [[ -z $prompt ]] || print -u2 "wt: task $name is already open; the prompt wasn't sent"
    (( $#added )) && print -r -- "wt: added ${(j:, :)added} to task $name (AGENTS.md is updated)"
    return 0
  fi

  local out ws pane
  out=$(herdr workspace create --cwd $td --label $name $focus) || return 1
  ws=$(jq -r '.result.workspace.workspace_id // empty' <<<"$out")
  pane=$(jq -r '.result.root_pane.pane_id // empty' <<<"$out")
  [[ -n $pane ]] || { print -u2 "wt: unexpected reply from herdr: $out"; return 1 }
  for e in ${(f)"$(jq -r --arg s "$_WT_SEP" '.repos[] | "\(.name)\($s)\(.dir)"' $t)"}; do
    IFS=$_WT_SEP read -r r dir <<<"$e"
    herdr tab create --workspace $ws --cwd "$dir" --label $r --no-focus >/dev/null
  done
  if [[ -n $from ]]; then
    lead="Implement the approved plan in plan.md, repo by repo in the order AGENTS.md gives.${prompt:+ $prompt}"
  elif [[ -n $plan ]]; then
    lead="$prompt (Write the plan to plan.md in this task folder: it's outside every repo, and saved when the task is done.)"
  else
    lead=$prompt
  fi
  words=(${(z)agent})
  # Reopening a task: pick its last session up again.
  [[ -z $new && -z $lead && ${words[1]:t} == pi ]] && agent="$agent -c"
  # --plan after the prompt (see _wt_new).
  herdr pane run $pane "$agent${lead:+ ${(qq)lead}}${plan:+ --plan}" >/dev/null
  [[ $focus == --focus ]] ||
    print -r -- "wt: task $name started in ${td/#$HOME/~}: $(jq -r '[.repos[].name] | join(" → ")' $t)"
}

# AGENTS.md for the lead session, regenerated from task.json.
_wt_task_agents() {
  local td=$1 t=$1/task.json name org
  name=$(jq -r .name $t); org=$(jq -r .org $t)
  {
    print -r -- "# Task: $name"
    print
    print -r -- "This folder is a task spanning several repos of $org. It is not a git repository:"
    print -r -- "each repo is a git worktree on branch \`$name\`, linked here by its name. Run git in a"
    print -r -- "repo (\`git -C <repo> ...\`, or cd into it), never here."
    print
    print -r -- "Repos, in the order their PRs merge:"
    print
    jq -r '.repos | to_entries[] | "\(.key + 1). `\(.value.name)`: \(.value.dir)" +
      (if (.value.after | length) > 0 then " (merges after \(.value.after | join(", ")))" else "" end)' $t
    print
    print -r -- "- Commit in each repo separately, and push its branch: \`git -C <repo> push -u origin $name\`."
    print -r -- "- One PR per repo (\`gh pr create\`, run inside the repo). A repo that merges after another"
    print -r -- "  gets a draft PR (\`--draft\`) until the one before it is merged, and its description"
    print -r -- "  says: \"Part of $name. Merge after <owner>/<repo>#<number>.\""
    print -r -- "- \`wt task status\` (or the wt tool's status action) shows each repo's PR, its checks,"
    print -r -- "  and what it waits for."
    [[ -f $td/plan.md ]] && print -r -- "- The plan is in plan.md."
    print -r -- "- Don't remove worktrees or this folder: the user runs /wt done once everything is merged."
  } >$td/AGENTS.md
}

_wt_task_status() {
  local td t e n dir main after state pr num prst checks url wait next
  local -A merged
  local -a rows
  td=$(_wt_task_find "$1") || { print -u2 "wt: no task ${1:-here}: run it in a task, or give its name"; return 1 }
  t=$td/task.json
  for e in ${(f)"$(jq -r --arg s "$_WT_SEP" '.repos[] | "\(.name)\($s)\(.dir)\($s)\(.main)\($s)\(.after | join(" "))"' $t)"}; do
    IFS=$_WT_SEP read -r n dir main after <<<"$e"
    if [[ -d $dir ]]; then
      _wt_fetch "$main"; state=$(_wt_state "$dir" "$(_wt_base "$main")" </dev/null)
    else
      state=removed
    fi
    pr=$(cd -q "$main" && gh pr list --head "$(jq -r .name $t)" --state all --limit 1 \
      --json number,state,isDraft,url,statusCheckRollup --jq '.[0] // empty | [
        (.number | tostring),
        (if .state == "MERGED" then "merged" elif .state == "CLOSED" then "closed"
         elif .isDraft then "draft" else "open" end),
        ([.statusCheckRollup[]? | (.conclusion // .state // "") | ascii_upcase] as $c |
         if ($c | length) == 0 then "-"
         elif any($c[]; . == "FAILURE" or . == "ERROR" or . == "CANCELLED" or . == "TIMED_OUT" or . == "ACTION_REQUIRED") then "failing"
         elif any($c[]; . == "" or . == "PENDING" or . == "QUEUED" or . == "IN_PROGRESS" or . == "EXPECTED") then "pending"
         else "passing" end),
        .url] | join("\u001f")' </dev/null 2>/dev/null) || pr="?"
    IFS=$_WT_SEP read -r num prst checks url <<<"$pr"
    [[ $prst == merged ]] && merged[$n]=1
    rows+=("$n$_WT_SEP$state$_WT_SEP$num$_WT_SEP$prst$_WT_SEP$checks$_WT_SEP$url$_WT_SEP$after")
  done
  print -r -- "task $(jq -r .name $t) (${td/#$HOME/~})"
  printf '%-20s %-9s %-12s %-8s %s\n' REPO WORKTREE PR CHECKS 'WAITS FOR'
  for e in $rows; do
    IFS=$_WT_SEP read -r n state num prst checks url after <<<"$e"
    wait=; for a in ${=after}; do (( $+merged[$a] )) || wait+="${wait:+, }$a"; done
    case $num in
      '?') pr='?' ;;
      '') pr=- ;;
      *) pr="#$num $prst" ;;
    esac
    printf '%-20s %-9s %-12s %-8s %s\n' $n $state "$pr" "${checks:--}" "${wait:--}"
    [[ -n $next || -n $wait || $prst == merged ]] && continue
    case $prst in
      '') [[ $num == '?' ]] && next="check $n's PR on GitHub (gh can't see it)" ||
            next="open a PR for $n (gh pr create, in its worktree)" ;;
      draft) next="mark $n's PR ready (gh pr ready) and get it merged: $url" ;;
      closed) next="$n's PR was closed without merging: $url" ;;
      *) next="merge $n's PR: $url" ;;
    esac
  done
  print
  if (( ${#merged} == $#rows )); then
    print "Every PR is merged: wt task done removes the task."
  else
    print -r -- "Next: ${next:-wait for the PRs above}"
  fi
}

# wt task done [-f] [--check] [name]. --check (for the pi extension) changes nothing
# and prints {task, dir, repos: [{name, dir, state, safe}], safe, closes_this, has_plan}.
_wt_task_done() {
  local force check name td t e n dir main state safe=1 log w here=0
  local -a rows ws
  while (( $# )); do
    case $1 in
      -f) force=1 ;;
      --check) check=1 ;;
      -*) print -u2 "wt task done: unknown option $1"; return 2 ;;
      *) name=$1 ;;
    esac
    shift
  done
  td=$(_wt_task_find "$name") || { print -u2 "wt: no task ${name:-here}: run it in a task, or give its name"; return 1 }
  t=$td/task.json; name=$(jq -r .name $t)
  for e in ${(f)"$(jq -r --arg s "$_WT_SEP" '.repos[] | "\(.name)\($s)\(.dir)\($s)\(.main)"' $t)"}; do
    IFS=$_WT_SEP read -r n dir main <<<"$e"
    if [[ -d $dir ]]; then
      _wt_fetch "$main"; state=$(_wt_state "$dir" "$(_wt_base "$main")" </dev/null)
    else
      state=removed
    fi
    [[ $state == (merged|in-base|removed) ]] || safe=
    rows+=("$n$_WT_SEP$dir$_WT_SEP$state")
  done
  ws=(${(f)"$(_wt_task_workspaces $td)"})
  [[ -n $HERDR_WORKSPACE_ID ]] && (( ${ws[(Ie)$HERDR_WORKSPACE_ID]} )) && here=1
  if [[ -n $check ]]; then
    local -a plans=($td/**/*.(md|mdx)(N.)); plans=(${plans:#$td/AGENTS.md})
    print -rl -- $rows | jq -R -s --arg s "$_WT_SEP" --arg task $name --arg dir $td \
      --argjson safe ${${safe:+true}:-false} --argjson here $here --argjson plan $(( $#plans > 0 )) \
      '{task: $task, dir: $dir, safe: $safe, closes_this: ($here == 1), has_plan: ($plan == 1),
        repos: [split("\n")[] | select(length > 0) | split($s) |
          {name: .[0], dir: .[1], state: .[2], safe: (.[2] == "merged" or .[2] == "in-base" or .[2] == "removed")}]}'
    return
  fi
  if [[ -z $force && -z $safe ]]; then
    print -u2 "wt: not removing task $name; work would be lost:"
    for e in $rows; do
      IFS=$_WT_SEP read -r n dir state <<<"$e"
      [[ $state == (merged|in-base|removed) ]] || print -u2 "  $n: $state"
    done
    print -u2 "wt task done -f throws that work away."
    return 1
  fi
  cd "$_WT_SRC/${${td:h:h}#$_WT_ROOT/}" 2>/dev/null || cd ~ # leave the task before it goes
  if (( here )); then
    # Closing the task's workspace closes this shell too: finish detached.
    log=${XDG_STATE_HOME:-$HOME/.local/state}/wt.log
    mkdir -p "${log:h}"
    print -r -- "wt: removing task $name; its workspace will close"
    setsid -f zsh -fc "sleep ${(q)${WT_DONE_DELAY:-0}}; _WT_ROOT=${(q)_WT_ROOT} _WT_SRC=${(q)_WT_SRC}; source ${(q)_WT_SELF}; _wt_task_remove ${(q)td} ${(q)force} && for w in ${(j: :)${(q)ws}}; do herdr workspace close \$w; done" \
      </dev/null >>$log 2>&1
  else
    _wt_task_remove $td "$force" || return 1
    for w in $ws; do herdr workspace close $w >/dev/null 2>&1; done
    print -r -- "wt: removed task $name"
  fi
}

_wt_task_ls() {
  local t open n=0
  for t in $_WT_ROOT/*/*/.tasks/*/task.json(N.); do
    (( n++ )) || printf '%-28s %-28s %-5s %s\n' TASK ORG OPEN 'REPOS (merge order)'
    open=; [[ -n $(_wt_task_workspaces ${t:h}) ]] && open=yes
    printf '%-28s %-28s %-5s %s\n' ${t:h:t} "$(jq -r .org $t)" "${open:--}" "$(jq -r '[.repos[].name] | join(" → ")' $t)"
  done
  (( n )) || print "wt: no tasks"
}
