#!/usr/bin/env bash
# Render templates/default into a dev-env-example checkout, filled in for "ada".
#
#   templates/sync-example.sh <example-dir>          write the example
#   templates/sync-example.sh <example-dir> --check  only report drift (exit 1)
#
# Every template file is copied, and files the template no longer has are
# deleted, except the ones the example keeps by hand (KEEP below). users/me.nix
# is skipped (the example has users/ada.nix), and `users/me.nix` becomes
# `users/ada.nix` in the copies, and `NIXUSER ?= me` becomes `NIXUSER ?= ada` in
# Makefile. dev-env.mk is copied unchanged, so the example's `make base/check` passes.
# Run it by hand after changing the template, then commit in the example.
set -euo pipefail

usage() { echo "usage: $0 <example-dir> [--check]" >&2; exit 2; }
[[ $# -ge 1 && $# -le 2 ]] || usage
dest=$1
check=
if [[ $# -eq 2 ]]; then [[ $2 == --check ]] || usage; check=1; fi
[[ -d $dest ]] || { echo "$dest: not a directory" >&2; exit 2; }

src=$(cd "$(dirname "${BASH_SOURCE[0]}")/default" && pwd)

# Kept by hand in the example; never copied or deleted.
KEEP=(README.md AGENTS.md flake.lock users/ada.nix .git)
# Not the template's either: build results and local files, as in .gitignore.
IGNORE=(result 'result-*' .direnv Makefile.local)

render() {
  local out=$1 f
  local -a args=(-a --delete --exclude=/users/me.nix)
  for f in "${KEEP[@]}"; do args+=(--exclude="/$f"); done
  for f in "${IGNORE[@]}"; do args+=(--exclude="/$f"); done
  rsync "${args[@]}" "$src/" "$out/"
  # Fill in the blanks, in the copied files only.
  (cd "$src" && find . -type f ! -path ./users/me.nix -print0) |
    while IFS= read -r -d '' f; do
      f=${f#./}
      [[ $f == dev-env.mk ]] && continue
      local -a sub=(-e 's|users/me\.nix|users/ada.nix|g')
      [[ $f == Makefile ]] && sub+=(-e 's|^NIXUSER ?= me$|NIXUSER ?= ada|')
      if ! sed "${sub[@]}" "$out/$f" | cmp -s - "$out/$f"; then
        sed "${sub[@]}" "$out/$f" > "$out/$f.tmp"
        # Keep the file's mode; only the content changes.
        cat "$out/$f.tmp" > "$out/$f" && rm "$out/$f.tmp"
      fi
    done
}

if [[ -z $check ]]; then
  render "$dest"
  echo "Rendered $src into $dest. Review with git diff there, then commit."
  exit 0
fi

tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
# Start from the example as it is, so the kept files compare equal.
rsync -a --exclude=/.git "$dest/" "$tmp/"
render "$tmp"
excludes=(-x .git)
for f in "${IGNORE[@]}"; do excludes+=(-x "$f"); done
if diff -ruN "${excludes[@]}" "$dest" "$tmp"; then
  echo "$dest matches the template."
else
  echo "$dest has drifted from the template: run $0 $dest" >&2
  exit 1
fi
