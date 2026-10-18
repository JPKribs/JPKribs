#!/bin/bash

# Generate the profile README cards (cards/*.svg) from templates/ and update
# stats-history.json.
#
# Each card is a standalone SVG so the README can wrap every one in its own
# link — GitHub strips <a> elements inside SVGs rendered through <img>, so
# per-repo links are only possible with per-repo images.
#
# Every dynamic card is rendered twice: the desktop layout and a full-width
# "-mobile" variant with larger type. The README picks between them with
# <picture><source media="(max-width: ...)"> so fluid/narrow viewports get a
# stack of full-width cards instead of a fixed-width grid — see the README's
# layout notes for the breakpoints and measured GitHub column widths.
# (header-mobile.svg is static and lives directly in cards/, like header.svg.)
#
# Runs in CI with GITHUB_TOKEN. Also runs locally without a token: star
# counts come from the unauthenticated API.

cd "$(dirname "$0")/../.." || exit 1

TEMPLATES=templates
OUT=cards
mkdir -p "$OUT"

TOKEN="${GITHUB_TOKEN:-}"
AUTH=()
if [ -n "$TOKEN" ]; then
  AUTH=(-H "Authorization: Bearer ${TOKEN}")
fi

# id | repo | display title | description.
#
# The id doubles as the output filename, the logo filename (logos/<id>.png)
# and the stats-history.json key prefix (<id>_stars). Existing ids must not
# change or delta history resets.
#
# Layout: the desktop grid is variable and fluid. Plugins fill rows of at
# most MAX_PER_ROW cards and rows are balanced (7 plugins become 4 + 3, 8
# become 4 + 4, 5 become 3 + 2). GitHub strips CSS but keeps percentage
# widths on images, so every card gets its share of the row as a percentage
# (minus a hair) and the row fills the column at any width without wrapping.
# Visible cards in a row are equal, gaps are transparent padding that scales
# with the row, and every row is ROW_W viewBox units wide, so card heights
# match across rows. Every card also carries a 10 unit transparent bottom pad.
# Descriptions must stay short enough for a four card row (~34 chars at 10px)
# and must not contain "|". Plain "&" is fine, text is XML and sed escaped.
# Alphabetical by display title.
PLUGINS=(
  "poster|JPKribs/jellyfin-plugin-artworkgenerator|Artwork Generator|Custom Posters, Logos & Backdrops"
  "custompages|JPKribs/jellyfin-plugin-custompages|Custom Pages|Permission Gated Custom Pages"
  "ddns|JPKribs/jellyfin-plugin-ddns|DDNS|Simple DDNS Manager"
  "livechannels|JPKribs/jellyfin-plugin-livechannels|Live Channels|Live TV Channels from Libraries"
  "sync|JPKribs/jellyfin-plugin-serversync|Server Sync|Sync Multiple Jellyfin Servers"
  "usermgmt|JPKribs/jellyfin-plugin-usermanagement|User Management|Group Management & User Invites"
  "youtube|JPKribs/jellyfin-plugin-youtubeaudio|YouTube Audio|Extract YouTube Audio"
)

MAX_PER_ROW=4
ROW_W=846
GUTTER=10

# Prints "svg_width left_pad visible_width percent" for each plugin in order, balancing
# the rows. Visible cards in a row are equal. Inner edges carry half the
# gutter as transparent padding and outer edges none, so a row lines up flush
# with the full width cards above and below it.
plugin_layout() {
  awk -v n="${#PLUGINS[@]}" -v max="$MAX_PER_ROW" -v row="$ROW_W" -v gut="$GUTTER" 'BEGIN {
    rows = int((n + max - 1) / max)
    base = int(n / rows); extra = n % rows
    for (r = 0; r < rows; r++) {
      k = base + (r < extra ? 1 : 0)
      vis = (row - gut * (k - 1)) / k
      for (c = 0; c < k; c++) {
        left = (c == 0 ? 0 : gut / 2); right = (c == k - 1 ? 0 : gut / 2)
        w = vis + left + right
        printf "%g %g %g %.3f\n", w, left, vis, w / row * 100 - 0.05
      }
    }
  }'
}

# Escape free text for substitution into the SVG templates: XML-encode
# (& < >), then backslash-escape sed replacement metacharacters (\ and &).
esc() {
  printf '%s' "$1" | \
    sed -e 's/&/\&amp;/g' -e 's/</\&lt;/g' -e 's/>/\&gt;/g' | \
    sed -e 's/[\\&]/\\&/g'
}

fetch_stars() {
  local s
  s=$(curl -s "${AUTH[@]}" "https://api.github.com/repos/$1" | jq -r '.stargazers_count // 0')
  if ! [[ "$s" =~ ^[0-9]+$ ]]; then s=0; fi
  echo "$s"
}

format_k() {
  if [ "$1" -gt 1000 ]; then
    echo "$(echo "scale=1; ($1+50)/1000" | bc)k"
  else
    echo "$1"
  fi
}

format_delta() {
  if [ "$1" -gt 0 ]; then echo "+$1"
  elif [ "$1" -lt 0 ]; then echo "$1"
  else echo "--"
  fi
}

delta_color() {
  if [ "$1" -gt 0 ]; then echo "#3fb950"
  elif [ "$1" -lt 0 ]; then echo "#f85149"
  else echo "#8b949e"
  fi
}

# History: newest entry for fallbacks, oldest (~7 days back) for deltas.
if [ -f stats-history.json ]; then
  PREV_DATA=$(jq '.[0] // {}' stats-history.json)
  OLD_DATA=$(jq '.[-1] // {}' stats-history.json)
else
  echo "[]" > stats-history.json
  PREV_DATA="{}"
  OLD_DATA="{}"
fi

# If a star count came back 0 (rate limit / hiccup), reuse the newest history
# value.
star_fallback() {
  local cur="$1" key="$2"
  if [ "$cur" -eq 0 ]; then
    cur=$(echo "$PREV_DATA" | jq -r --arg k "$key" '.[$k] // 0')
    if ! [[ "$cur" =~ ^[0-9]+$ ]]; then cur=0; fi
  fi
  echo "$cur"
}

hist_old() {
  echo "$OLD_DATA" | jq -r --arg k "$1" '.[$k] // 0'
}

# Today's history entry, built up incrementally.
TODAY=$(date -u +%Y-%m-%d)
ENTRY=$(jq -n --arg date "$TODAY" '{date: $date}')
entry_set() {
  ENTRY=$(echo "$ENTRY" | jq --arg k "$1" --argjson v "$2" '.[$k] = $v')
}

# ---------------------------------------------------------------------------
# Swiftfin featured card
# ---------------------------------------------------------------------------

echo "Fetching Swiftfin stars..." >&2
SWIFT_STARS=$(fetch_stars jellyfin/Swiftfin)
SWIFT_STARS=$(star_fallback "$SWIFT_STARS" swift_stars)
SWIFT_DIFF=$((SWIFT_STARS - $(hist_old swift_stars)))
entry_set swift_stars "$SWIFT_STARS"

for variant in "" "-mobile"; do
  sed -e "s|SWIFT_STARS_FORMATTED|$(format_k "$SWIFT_STARS")|g" \
      -e "s|SWIFT_DELTA_COLOR|$(delta_color "$SWIFT_DIFF")|g" \
      -e "s|SWIFT_DELTA|$(format_delta "$SWIFT_DIFF")|g" \
      "$TEMPLATES/swiftfin-card$variant.svg" > "$OUT/swiftfin$variant.svg"
done

# ---------------------------------------------------------------------------
# Plugin cards
# ---------------------------------------------------------------------------

mapfile -t LAYOUT < <(plugin_layout)
README_CARDS=""
for i in "${!PLUGINS[@]}"; do
  IFS='|' read -r id repo title desc <<< "${PLUGINS[$i]}"
  read -r svg_w left vis pct <<< "${LAYOUT[$i]}"
  logo="data:image/png;base64,$(base64 < "logos/$id.png" | tr -d '\n')"
  README_CARDS+="<a href=\"https://github.com/$repo\"><picture><source media=\"(max-width: 1279px)\" srcset=\"cards/$id-mobile.svg\"><img src=\"cards/$id.svg\" alt=\"$title\" align=\"top\" width=\"$pct%\"></picture></a>"
  echo "Fetching stars for $repo..." >&2
  stars=$(fetch_stars "$repo")
  stars=$(star_fallback "$stars" "${id}_stars")
  diff=$((stars - $(hist_old "${id}_stars")))
  entry_set "${id}_stars" "$stars"

  # Geometry: the visible card starts after the left padding, its rect is
  # inset 0.75 for the 1.5 stroke, and the title, text and 59.3 wide logo
  # center on it.
  read -r rect_x rect_w center logo_x <<< "$(awk -v l="$left" -v v="$vis" \
    'BEGIN{printf "%g %g %g %g", l+0.75, v-1.5, l+v/2, l+v/2-29.65}')"

  sed -e "s|SVG_W|$svg_w|g" \
      -e "s|RECT_X|$rect_x|g" \
      -e "s|RECT_W|$rect_w|g" \
      -e "s|CENTER|$center|g" \
      -e "s|LOGO_X|$logo_x|g" \
      -e "s|PLUGIN_TITLE|$(esc "$title")|g" \
      -e "s|PLUGIN_DESC|$(esc "$desc")|g" \
      -e "s|PLUGIN_STARS|$stars|g" \
      -e "s|PLUGIN_DELTA_COLOR|$(delta_color "$diff")|g" \
      -e "s|PLUGIN_DELTA|$(format_delta "$diff")|g" \
      -e "s|PLUGIN_LOGO|$logo|g" \
      "$TEMPLATES/plugin-card.svg" > "$OUT/$id.svg"

  # Mobile variant: fixed full-width layout. Its intrinsic size is 1600px
  # (2× the 800 viewBox) so it always exceeds the README column and
  # max-width:100% scales it to fill exactly.
  sed -e "s|PLUGIN_TITLE|$(esc "$title")|g" \
      -e "s|PLUGIN_DESC|$(esc "$desc")|g" \
      -e "s|PLUGIN_STARS|$stars|g" \
      -e "s|PLUGIN_DELTA_COLOR|$(delta_color "$diff")|g" \
      -e "s|PLUGIN_DELTA|$(format_delta "$diff")|g" \
      -e "s|PLUGIN_LOGO|$logo|g" \
      "$TEMPLATES/plugin-card-mobile.svg" > "$OUT/$id-mobile.svg"
done

# The README's plugin row is rebuilt from PLUGINS, so adding a plugin above
# is all it takes to grow the grid.
awk -v cards="$README_CARDS" '
  /<!-- plugins:start -->/ { print; print "<div align=\"center\">" cards "</div>"; skip = 1; next }
  /<!-- plugins:end -->/ { skip = 0 }
  !skip
' README.md > README.tmp && mv README.tmp README.md

# ---------------------------------------------------------------------------
# Footer card (contact info + last-updated date)
# ---------------------------------------------------------------------------

for variant in "" "-mobile"; do
  sed -e "s|UPDATED|$(date -u +'%b %d, %Y')|g" \
      "$TEMPLATES/footer-card$variant.svg" > "$OUT/footer$variant.svg"
done

# ---------------------------------------------------------------------------
# Persist history (keep last 7 days)
# ---------------------------------------------------------------------------

# Replace any existing entry for today so reruns don't shrink the 7-day window.
jq --argjson entry "$ENTRY" '[$entry] + map(select(.date != $entry.date)) | .[0:7]' stats-history.json > stats-history-tmp.json
mv stats-history-tmp.json stats-history.json

echo "Done: $(ls "$OUT" | wc -l | tr -d ' ') cards written to $OUT/" >&2
