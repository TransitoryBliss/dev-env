#!/usr/bin/env bash
# Loads every theme in themes/palettes.json in headless nvim, with your own nvim
# config (which must load spec.lua), and reports the ones that fail. For each it
# prints nvim's own background next to the terminal palette's: they should be
# the same or close, and each variant of a family should differ. It checks that
# a theme loads and is the right variant, not how it looks.
#
#   themes/nvim/check.sh            # all themes
#   themes/nvim/check.sh dracula    # just these
set -uo pipefail
cd "$(dirname "$0")/.."

nvim --headless "+Lazy! install" +qa >/dev/null 2>&1

tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
names=("$@")
[ ${#names[@]} -gt 0 ] || mapfile -t names < <(jq -r 'keys[]' palettes.json)

fail=0
printf '     %-22s %-22s %-6s %-8s %s\n' theme colorscheme mode nvim-bg palette-bg
for name in "${names[@]}"; do
  jq -e --arg n "$name" '.[$n] // error("unknown theme") | . + { name: $n }' \
    palettes.json > "$tmp/theme.json" 2>/dev/null \
    || { printf 'FAIL %-22s not in palettes.json\n' "$name"; fail=1; continue; }
  want=$(jq -r .nvim.colorscheme "$tmp/theme.json")
  pbg=$(jq -r .background "$tmp/theme.json")
  mode=$(jq -r .appearance "$tmp/theme.json")
  got=$(DEV_ENV_THEME="$tmp/theme.json" nvim --headless \
    "+lua io.stdout:write(table.concat({vim.g.dev_env_theme_applied or 'none', vim.o.background, vim.g.dev_env_theme_bg or 'none', ((vim.g.dev_env_theme_error or ''):gsub('[\n|]', ' '))}, '|'))" \
    +qa 2>&1 | tail -1)
  IFS='|' read -r scheme bg nbg err <<<"$got"
  if [ "$scheme" = "$want" ] && [ "$bg" = "$mode" ] && [ -z "$err" ]; then
    printf 'ok   %-22s %-22s %-6s %-8s %s\n' "$name" "$scheme" "$bg" "$nbg" "$pbg"
  else
    printf 'FAIL %-22s want %s (%s), got %s (%s) %s\n' "$name" "$want" "$mode" "$scheme" "$bg" "$err"
    fail=1
  fi
done
exit $fail
