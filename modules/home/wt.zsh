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
  print -r -- "wt [-b] <branch> [prompt]  new worktree off the default branch, in its own herdr
                           workspace, with \$WT_AGENT (default: pi) started in it.
                           -b: stay where you are. An existing worktree is reopened.
wt done [-f]               in a worktree: remove it and its branch, if nothing is lost.
                           -f: remove it anyway, uncommitted and unmerged work too.
wt ls                      every worktree under ${_WT_ROOT/#$HOME/~}, with its state
wt gc [-n]                 remove merged ones, and closed ones with no new commits.
                           -n: only say what would go.

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
_wt_remove() {
  local dir=$1 main=$2 branch=$3 wsid=$4 force=$5 d
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
  local focus=--focus
  [[ $1 == -b ]] && { focus=--no-focus; shift }
  local branch=$1 prompt=$2 main base out pane dir existing
  [[ -n $branch ]] || { _wt_usage; return 2 }
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
  herdr pane run "$pane" "${WT_AGENT:-pi}${prompt:+ ${(qq)prompt}}" >/dev/null
  [[ $focus == --focus ]] || print -r -- "wt: $branch started in ${dir/#$HOME/~}"
}

_wt_done() {
  local force dir main branch base state wsid log
  [[ $1 == -f ]] && force=1
  dir=$(git rev-parse --show-toplevel 2>/dev/null) || { print -u2 "wt: not in a git repo"; return 1 }
  main=$(_wt_main "$dir")
  [[ ${dir:A} != ${main:A} ]] || { print -u2 "wt: $dir is the main checkout, not a worktree"; return 1 }
  branch=$(git -C "$dir" branch --show-current)
  if [[ -z $force ]]; then
    _wt_fetch "$main"
    base=$(_wt_base "$main")
    state=$(_wt_state "$dir" "$base")
    case $state in
      dirty) print -u2 "wt: uncommitted changes in $dir (wt done -f throws them away)"; return 1 ;;
      unmerged) print -u2 "wt: $branch has commits $base lacks and no merged PR (wt done -f deletes them)"; return 1 ;;
    esac
  fi
  wsid=$(_wt_workspace_of "$dir")
  cd "$main" # leave the checkout before it goes
  if [[ -n $wsid && $wsid == $HERDR_WORKSPACE_ID ]]; then
    # Removing it closes this workspace, and this shell with it: finish detached.
    log=${XDG_STATE_HOME:-$HOME/.local/state}/wt.log
    mkdir -p "${log:h}"
    print -r -- "wt: removing ${dir/#$HOME/~}; this workspace will close"
    setsid -f zsh -fc "_WT_ROOT=${(q)_WT_ROOT} _WT_SRC=${(q)_WT_SRC}; source ${(q)_WT_SELF}; _wt_remove ${(q)dir} ${(q)main} ${(q)branch} ${(q)wsid} ${(q)force}" \
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

_wt_gc() {
  local dry d main branch state wsid age name why
  [[ $1 == -n ]] && dry=1
  _wt_scan | while IFS=$_WT_SEP read -r d main branch state wsid age; do
    name=${d#$_WT_ROOT/}
    case $state in
      merged) why='PR merged' ;;
      in-base)
        # An open one with no commits is usually a task that has just started.
        [[ -z $wsid ]] || { print -r -- "keep    $name: no commits yet, but open"; continue }
        why='no commits beyond the default branch' ;;
      *) print -r -- "keep    $name: $state"; continue ;;
    esac
    if [[ -n $wsid && $wsid == $HERDR_WORKSPACE_ID ]]; then
      print -r -- "keep    $name: you're in it, use wt done"; continue
    fi
    if [[ -n $dry ]]; then
      print -r -- "remove  $name ($why)"
    else
      _wt_remove "$d" "$main" "$branch" "$wsid" "" </dev/null && print -r -- "removed $name ($why)"
    fi
  done
}
