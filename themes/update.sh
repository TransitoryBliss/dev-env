#!/usr/bin/env bash
# Regenerates themes/palettes.json: the terminal palette of every theme
# devEnv.theme.name accepts, from the Ghostty theme files in
# iTerm2-Color-Schemes (the collection Ghostty's own built-in themes come from),
# pinned to one commit so a rerun gives the same file.
#
#   themes/update.sh              # at REV below
#   REV=<sha> themes/update.sh    # to move the pin (then update REV here)
#
# Adding a theme: one line in THEMES (its nvim family must be in
# nvim/families.json), rerun, check it with nvim/check.sh, commit both.
set -euo pipefail

REV=${REV:-99d9701ba3cf4a06d24eea6ca4f25a64656b446b}
BASE="https://raw.githubusercontent.com/mbadolato/iTerm2-Color-Schemes/$REV/ghostty"
cd "$(dirname "$0")"

# name | Ghostty theme file | nvim family (nvim/families.json) | nvim colorscheme | appearance
THEMES='
catppuccin-mocha     | Catppuccin Mocha      | catppuccin  | catppuccin-mocha     | dark
catppuccin-macchiato | Catppuccin Macchiato  | catppuccin  | catppuccin-macchiato | dark
catppuccin-frappe    | Catppuccin Frappe     | catppuccin  | catppuccin-frappe    | dark
catppuccin-latte     | Catppuccin Latte      | catppuccin  | catppuccin-latte     | light
tokyonight-night     | TokyoNight Night      | tokyonight  | tokyonight-night     | dark
tokyonight-storm     | TokyoNight Storm      | tokyonight  | tokyonight-storm     | dark
tokyonight-moon      | TokyoNight Moon       | tokyonight  | tokyonight-moon      | dark
tokyonight-day       | TokyoNight Day        | tokyonight  | tokyonight-day       | light
gruvbox-dark         | Gruvbox Dark          | gruvbox     | gruvbox              | dark
gruvbox-light        | Gruvbox Light         | gruvbox     | gruvbox              | light
dracula              | Dracula               | dracula     | dracula              | dark
rose-pine            | Rose Pine             | rose-pine   | rose-pine-main       | dark
rose-pine-moon       | Rose Pine Moon        | rose-pine   | rose-pine-moon       | dark
rose-pine-dawn       | Rose Pine Dawn        | rose-pine   | rose-pine-dawn       | light
kanagawa-wave        | Kanagawa Wave         | kanagawa    | kanagawa-wave        | dark
kanagawa-dragon      | Kanagawa Dragon       | kanagawa    | kanagawa-dragon      | dark
kanagawa-lotus       | Kanagawa Lotus        | kanagawa    | kanagawa-lotus       | light
nord                 | Nord                  | nord        | nord                 | dark
everforest-dark      | Everforest Dark Med   | everforest  | everforest           | dark
everforest-light     | Everforest Light Med  | everforest  | everforest           | light
onedark              | Atom One Dark         | onedark     | onedark              | dark
nightfox             | Nightfox              | nightfox    | nightfox             | dark
carbonfox            | Carbonfox             | nightfox    | carbonfox            | dark
dayfox               | Dayfox                | nightfox    | dayfox               | light
solarized-dark       | iTerm2 Solarized Dark | solarized   | solarized            | dark
solarized-light      | iTerm2 Solarized Light| solarized   | solarized            | light
github-dark          | GitHub Dark Default   | github      | github_dark_default  | dark
github-light         | GitHub Light Default  | github      | github_light_default | light
monokai-pro          | Monokai Pro           | monokai-pro | monokai-pro          | dark
ayu-dark             | Ayu                   | ayu         | ayu-dark             | dark
ayu-mirage           | Ayu Mirage            | ayu         | ayu-mirage           | dark
ayu-light            | Ayu Light             | ayu         | ayu-light            | light
'

trim() { sed 's/^ *//; s/ *$//' <<<"$1"; }

out='{}'
while IFS='|' read -r name file family scheme appearance; do
  name=$(trim "$name"); [ -n "$name" ] || continue
  file=$(trim "$file"); family=$(trim "$family"); scheme=$(trim "$scheme"); appearance=$(trim "$appearance")
  jq -e --arg f "$family" 'has($f)' nvim/families.json >/dev/null \
    || { echo "$name: family $family is not in nvim/families.json" >&2; exit 1; }
  conf=$(curl -fsSL "$BASE/$(jq -rn --arg s "$file" '$s|@uri')")
  # Ghostty format: "palette = N=#rrggbb", "background = #rrggbb", ...
  theme=$(awk -F' = ' '
    $1 == "palette"      { split($2, p, "="); ansi[p[1]] = tolower(p[2]) }
    $1 == "background"   { bg = tolower($2) }
    $1 == "foreground"   { fg = tolower($2) }
    $1 == "cursor-color" { cur = tolower($2) }
    END {
      if (bg == "" || fg == "") exit 1
      printf "{\"background\":\"%s\",\"foreground\":\"%s\",\"cursor\":\"%s\",\"ansi\":[", bg, fg, (cur == "" ? fg : cur)
      for (i = 0; i < 16; i++) { if (!(i in ansi)) exit 1; printf "%s\"%s\"", (i ? "," : ""), ansi[i] }
      printf "]}"
    }' <<<"$conf") || { echo "$name: couldn't parse ghostty/$file" >&2; exit 1; }
  out=$(jq --arg n "$name" --arg src "iTerm2-Color-Schemes@${REV:0:7} ghostty/$file" \
           --arg fam "$family" --arg cs "$scheme" --arg app "$appearance" --argjson t "$theme" \
    '.[$n] = ($t + { appearance: $app, nvim: { family: $fam, colorscheme: $cs }, source: $src })' <<<"$out")
  echo "ok $name"
done <<<"$THEMES"

jq -S . <<<"$out" > palettes.json
echo "wrote themes/palettes.json ($(jq length palettes.json) themes)"
