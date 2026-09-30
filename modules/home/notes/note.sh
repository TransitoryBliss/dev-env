# note: ideas and todos as markdown files in a git repo, shared by you and your
# agents. Every change is committed and pushed. The wrapper in default.nix sets
# NOTES_DIR and NOTES_REPO (devEnv.notes); the environment can override both.
#
# Several agents can run it at once in the same checkout: everything that
# touches git holds a flock on .git/note.lock, and a mutation commits only the
# files it changed, so it never sweeps up someone else's half-written file.

: "${NOTES_REPO:=}"
: "${NOTES_DIR:?NOTES_DIR is not set}"
export GIT_TERMINAL_PROMPT=0
export GIT_SSH_COMMAND="${GIT_SSH_COMMAND:-ssh -o ConnectTimeout=10}"

usage() {
  cat <<'EOF'
note: ideas and todos in a git repo, committed and pushed on every change.

  note add <title> [-t idea|todo] [--tag a,b] [-p host/owner/repo | -P] [-m text]... [-e]
  idea <title> [...]           same as note add -t idea
  todo <title> [...]           same as note add -t todo
  note ls [-a | -s status] [-t idea|todo] [--tag x] [-p project | -H]
  note show <ref>              print an item
  note path <ref>              absolute path of an item
  note start <ref>             status: doing
  note done <ref>              status: done
  note drop <ref>              status: dropped
  note reopen <ref>            status: open
  note promote <ref>           move an idea to todos/
  note edit <ref>              open in $EDITOR, then commit and push
  note sync [message]          commit every change in the repo, pull, push
  note dir                     print the repo's directory

<ref> is a file name, with or without its date and .md, or any unique part of one.
add: -p defaults to the repo you're in (host/owner/repo); -P leaves it out.
  -m adds a paragraph to the body; -e opens $EDITOR before committing.
ls: shows open and doing items by default; -a shows all, -H only the repo you're in.
EOF
}

die() { echo "note: $*" >&2; exit 1; }
warn() { echo "note: $*" >&2; }
need() { [[ $# -ge 2 ]] || die "$1 needs a value"; }
g() { git -C "$NOTES_DIR" "$@"; }

# Clones into a temporary directory and renames it into place, so several
# first runs at once can't trip over each other: `mv -T` fails for all but one.
ensure_repo() {
  if [[ -d $NOTES_DIR/.git ]]; then return 0; fi
  [[ -n $NOTES_REPO ]] || die "$NOTES_DIR is not a git repo, and there's no NOTES_REPO to clone"
  local parent tmp
  parent=$(dirname "$NOTES_DIR")
  mkdir -p "$parent"
  tmp=$(mktemp -d "$parent/.note-clone.XXXXXX")
  warn "cloning $NOTES_REPO into $NOTES_DIR"
  if git clone -q "$NOTES_REPO" "$tmp/repo"; then
    mv -T "$tmp/repo" "$NOTES_DIR" 2>/dev/null || true
  fi
  rm -rf "$tmp"
  [[ -d $NOTES_DIR/.git ]] || die "couldn't clone $NOTES_REPO"
}

# Pulls, then resolves: for commands that only read an item.
fresh() {
  local rel
  ensure_repo
  lock
  pull
  unlock
  rel=$(resolve "$1")
  echo "$rel"
}

lock() {
  exec 9>"$NOTES_DIR/.git/note.lock"
  flock -w 60 9 || die "another note has held $NOTES_DIR/.git/note.lock for a minute"
}
unlock() { flock -u 9; }

has_head() { g rev-parse --verify -q HEAD >/dev/null; }
has_upstream() { g rev-parse --verify -q '@{u}' >/dev/null; }

# Brings in the remote's commits. Never fails: offline, or with a conflict,
# the change still gets committed locally and a later sync pushes it.
pull() {
  if ! g fetch -q 2>/dev/null; then
    warn "couldn't fetch (offline?); working locally"
    return 0
  fi
  if ! has_upstream; then return 0; fi
  if ! has_head || [[ -z $(g rev-list '@{u}..HEAD') ]]; then
    g merge -q --ff-only '@{u}' 2>/dev/null ||
      warn "couldn't fast-forward (uncommitted edits in the way?); run note sync"
  elif ! g rebase -q --autostash '@{u}' >/dev/null 2>&1; then
    g rebase --abort >/dev/null 2>&1 || true
    warn "couldn't rebase onto the remote; resolve it by hand in $NOTES_DIR"
  fi
}

push() {
  if ! has_head; then return 0; fi
  local err=''
  for _ in 1 2 3; do
    if err=$(g push -q -u origin HEAD 2>&1); then return 0; fi
    pull
  done
  warn "push failed; the commit is saved locally and the next note command pushes it:"
  printf '%s\n' "$err" >&2
}

# commit <message> <path>...: commits exactly these paths (new, changed,
# deleted or moved), whatever else is staged or dirty.
commit() {
  local msg=$1 p
  local -a paths=()
  shift
  for p in "$@"; do
    if [[ -e $NOTES_DIR/$p || -n $(g ls-files -- "$p") ]]; then paths+=("$p"); fi
  done
  if ((${#paths[@]} == 0)); then return 0; fi
  g add -A -- "${paths[@]}"
  if g diff --cached --quiet -- "${paths[@]}"; then return 0; fi
  g commit -q -m "$msg" -- "${paths[@]}"
}

# host/owner/repo of the repo the caller is in, when it's under ~/source.
# A worktree's common dir is inside its main checkout, so worktrees count too.
current_project() {
  local common top src notes
  common=$(git rev-parse --path-format=absolute --git-common-dir 2>/dev/null) || return 0
  top=$(realpath -q "$(dirname "$common")") || return 0
  notes=$(realpath -q "$NOTES_DIR" 2>/dev/null) || notes=''
  if [[ $top == "$notes" ]]; then return 0; fi
  src=$(realpath -q "$HOME/source") || return 0
  case $top in "$src"/*/*/*) echo "${top#"$src"/}" ;; esac
}

slugify() {
  local s
  s=$(printf '%s' "$1" |
    sed -E 's/å|ä|à|á|Å|Ä|À|Á/a/g; s/ö|ø|ó|Ö|Ø|Ó/o/g; s/é|è|ê|É|È/e/g; s/ü|Ü/u/g' |
    tr '[:upper:]' '[:lower:]' |
    sed -E 's/[^a-z0-9]+/-/g; s/^-+//' | cut -c1-60 | sed -E 's/-+$//')
  echo "${s:-note}"
}

title_of() {
  local t
  t=$(awk 'NR==1 && /^---$/ { fm=1; next } fm && /^---$/ { fm=0; next }
           !fm && /^# / { print substr($0, 3); exit }' "$1")
  if [[ -z $t ]]; then t=$(basename "$1" .md); fi
  echo "$t"
}

# fm_set <file> <key> <value>: sets a frontmatter field, adding it if missing.
fm_set() {
  local f=$1 tmp
  [[ $(head -n1 "$f") == --- ]] || die "$f has no frontmatter"
  tmp=$(mktemp -p "$NOTES_DIR/.git" note.XXXXXX)
  awk -v k="$2" -v v="$3" '
    NR==1 { fm=1; print; next }
    fm && /^---$/ { if (!done) print k ": " v; fm=0; print; next }
    fm && index($0, k ":") == 1 { print k ": " v; done=1; next }
    { print }' "$f" >"$tmp"
  mv "$tmp" "$f"
}

# Prints the item's path relative to the repo. An exact name (with or without
# the date) wins; otherwise the ref must be part of exactly one name.
resolve() {
  local ref=$1 f base exact=''
  local -a matches=()
  ref=${ref#"$NOTES_DIR"/}
  ref=${ref%.md}
  ref=${ref##*/}
  [[ -n $ref ]] || die "empty ref"
  shopt -s nullglob
  for f in "$NOTES_DIR"/todos/*.md "$NOTES_DIR"/ideas/*.md; do
    base=$(basename "$f" .md)
    if [[ $base == "$ref" || ${base:11} == "$ref" ]]; then exact=${f#"$NOTES_DIR"/}; fi
    if [[ $base == *"$ref"* ]]; then matches+=("${f#"$NOTES_DIR"/}"); fi
  done
  if [[ -n $exact ]]; then
    echo "$exact"
  elif ((${#matches[@]} == 1)); then
    echo "${matches[0]}"
  elif ((${#matches[@]} == 0)); then
    die "nothing matches '$1' (note ls -a lists everything)"
  else
    die "'$1' matches several items: ${matches[*]}"
  fi
}

cmd_add() {
  local type=idea title='' tags='' proj='' noproj=0 edit=0
  local -a body=()
  while (($#)); do
    case $1 in
      -t | --type) need "$@"; type=$2; shift 2 ;;
      --tag | --tags) need "$@"; tags=${tags:+$tags,}$2; shift 2 ;;
      -p | --project) need "$@"; proj=$2; shift 2 ;;
      -P | --no-project) noproj=1; shift ;;
      -m | --message) need "$@"; body+=("$2"); shift 2 ;;
      -e | --edit) edit=1; shift ;;
      --) shift; title="$title${title:+ }$*"; break ;;
      -*) die "unknown option for add: $1" ;;
      *) title="$title${title:+ }$1"; shift ;;
    esac
  done
  case $type in idea | todo) ;; *) die "type must be idea or todo, not '$type'" ;; esac
  [[ -n $title ]] || die "usage: note add <title> [options]"
  if ((noproj)); then proj=''; elif [[ -z $proj ]]; then proj=$(current_project); fi
  tags=$(printf '%s' "$tags" | sed -E 's/#//g; s/[[:space:]]*,[[:space:]]*/, /g; s/^[, ]+//; s/[, ]+$//')

  ensure_repo
  lock
  pull
  local date slug name rel n=2 p
  date=$(date +%F)
  slug=$(slugify "$title")
  name="$date-$slug"
  while [[ -e $NOTES_DIR/ideas/$name.md || -e $NOTES_DIR/todos/$name.md ]]; do
    name="$date-$slug-$n"
    n=$((n + 1))
  done
  rel="${type}s/$name.md"
  mkdir -p "$NOTES_DIR/${type}s"
  {
    echo ---
    echo "status: open"
    echo "created: $date"
    echo "tags: [$tags]"
    if [[ -n $proj ]]; then echo "project: $proj"; fi
    echo ---
    echo "# $title"
    for p in "${body[@]}"; do
      echo
      echo "$p"
    done
  } >"$NOTES_DIR/$rel"
  if ((edit)); then
    unlock
    ${EDITOR:-vi} "$NOTES_DIR/$rel"
    lock
  fi
  commit "$type: $title" "$rel"
  push
  unlock
  echo "$NOTES_DIR/$rel"
}

cmd_ls() {
  local sre='^(open|doing)$' type='' tag='' proj=''
  while (($#)); do
    case $1 in
      -a | --all) sre=''; shift ;;
      -s | --status) need "$@"; sre="^($2)\$"; shift 2 ;;
      -t | --type) need "$@"; type=$2; shift 2 ;;
      --tag) need "$@"; tag=${2#\#}; shift 2 ;;
      -p | --project) need "$@"; proj=$2; shift 2 ;;
      -H | --here)
        proj=$(current_project)
        [[ -n $proj ]] || die "-H: not inside a repo under ~/source"
        shift ;;
      *) die "unknown option for ls: $1" ;;
    esac
  done
  ensure_repo
  lock
  pull
  unlock
  cd "$NOTES_DIR" || die "can't cd to $NOTES_DIR"
  shopt -s nullglob
  local -a files=(todos/*.md ideas/*.md)
  if ((${#files[@]} == 0)); then return 0; fi
  awk -v sre="$sre" -v want_type="$type" -v want_tag="$tag" -v want_proj="$proj" '
    function flush(  t, name, extra) {
      if (file == "") return
      t = (file ~ /^ideas\//) ? "idea" : "todo"
      if (sre != "" && st !~ sre) return
      if (want_type != "" && t != want_type) return
      gsub(/[][ "\047]/, "", tg)
      if (want_tag != "" && index("," tg ",", "," want_tag ",") == 0) return
      gsub(/["\047]/, "", pr)
      if (want_proj != "" && pr != want_proj) return
      name = file; sub(/^[a-z]+\//, "", name); sub(/\.md$/, "", name)
      extra = (tg != "") ? "  [" tg "]" : ""
      if (pr != "" && want_proj == "") extra = extra "  (" pr ")"
      printf "%-7s %-4s  %s  %s%s\n", st, t, name, (ti != "" ? ti : name), extra
    }
    FNR == 1 { flush(); file = FILENAME; st = ""; tg = ""; pr = ""; ti = ""; fm = 0 }
    FNR == 1 && /^---$/ { fm = 1; next }
    fm && /^---$/ { fm = 0; next }
    fm {
      if (sub(/^status:[ \t]*/, "")) st = $0
      else if (sub(/^tags:[ \t]*/, "")) tg = $0
      else if (sub(/^project:[ \t]*/, "")) pr = $0
      next
    }
    ti == "" && /^# / { ti = substr($0, 3) }
    END { flush() }' "${files[@]}"
}

cmd_status() {
  local st=$1 verb=$2 rel
  shift 2
  [[ $# -eq 1 ]] || die "usage: note $verb <ref>"
  ensure_repo
  lock
  pull
  rel=$(resolve "$1")
  fm_set "$NOTES_DIR/$rel" status "$st"
  commit "$verb: $(title_of "$NOTES_DIR/$rel")" "$rel"
  push
  unlock
  echo "$st: $rel"
}

cmd_promote() {
  [[ $# -eq 1 ]] || die "usage: note promote <ref>"
  local rel dest
  ensure_repo
  lock
  pull
  rel=$(resolve "$1")
  [[ $rel == ideas/* ]] || die "$rel is not an idea"
  dest="todos/${rel#ideas/}"
  [[ ! -e $NOTES_DIR/$dest ]] || die "$dest already exists"
  mkdir -p "$NOTES_DIR/todos"
  mv "$NOTES_DIR/$rel" "$NOTES_DIR/$dest"
  commit "promote: $(title_of "$NOTES_DIR/$dest")" "$rel" "$dest"
  push
  unlock
  echo "$NOTES_DIR/$dest"
}

cmd_edit() {
  [[ $# -eq 1 ]] || die "usage: note edit <ref>"
  local rel
  ensure_repo
  lock
  pull
  rel=$(resolve "$1")
  unlock
  ${EDITOR:-vi} "$NOTES_DIR/$rel"
  lock
  commit "edit: $(title_of "$NOTES_DIR/$rel")" "$rel"
  push
  unlock
}

cmd_sync() {
  local msg=${*:-update notes}
  ensure_repo
  lock
  g add -A
  if ! g diff --cached --quiet; then g commit -q -m "$msg"; fi
  pull
  push
  unlock
}

cmd=${1:-ls}
if (($#)); then shift; fi
case $cmd in
  add | new) cmd_add "$@" ;;
  idea | todo) cmd_add -t "$cmd" "$@" ;;
  ls | list) cmd_ls "$@" ;;
  show | cat) [[ $# -eq 1 ]] || die "usage: note show <ref>"; rel=$(fresh "$1"); cat "$NOTES_DIR/$rel" ;;
  path) [[ $# -eq 1 ]] || die "usage: note path <ref>"; rel=$(fresh "$1"); echo "$NOTES_DIR/$rel" ;;
  start) cmd_status doing start "$@" ;;
  done) cmd_status 'done' 'done' "$@" ;;
  drop) cmd_status dropped drop "$@" ;;
  reopen) cmd_status open reopen "$@" ;;
  promote) cmd_promote "$@" ;;
  edit) cmd_edit "$@" ;;
  sync) cmd_sync "$@" ;;
  dir) echo "$NOTES_DIR" ;;
  help | -h | --help) usage ;;
  *) usage >&2; exit 1 ;;
esac
