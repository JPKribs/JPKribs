#!/bin/bash

# Generate the profile README cards (cards/*.svg) from templates/ and update
# stats-history.json.
#
# Each card is a standalone SVG so the README can wrap every one in its own
# link — GitHub strips <a> elements inside SVGs rendered through <img>, so
# per-repo links are only possible with per-repo images.
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

# id | repo | display title | description | card width | right gutter.
#
# The id doubles as the output filename and the stats-history.json key prefix
# (<id>_stars) — existing ids must not change or delta history resets.
#
# Layout: the README butts the row's images together with NO whitespace, so
# each row's SVG widths (card + gutter) must sum to exactly 800 to line up
# with the full-width cards. Row 1 is 3-up (3×260 + 2×10), row 2 is 4-up
# (4×192.5 + 3×10). The gutter is transparent padding baked into the SVG;
# the last card of each row has none. Every card template also carries a
# 10px transparent bottom pad (footer excepted) so vertical gaps match the
# horizontal ones exactly.
# Descriptions must stay short enough for the narrow 4-up cards (~34 chars
# at 10px) and must not contain "|" (the field delimiter). Plain "&" is fine
# — titles/descriptions are XML- and sed-escaped before substitution.
# Alphabetical by display title: row 1 gets the first 3, row 2 the rest.
PLUGINS=(
  "custompages|JPKribs/jellyfin-plugin-custompages|Custom Pages|Permission Gated Custom Pages|260|10"
  "ddns|JPKribs/jellyfin-plugin-ddns|DDNS|Simple DDNS Manager|260|10"
  "livechannels|JPKribs/jellyfin-plugin-livechannels|Live Channels|Live TV Channels from Libraries|260|0"
  "poster|JPKribs/jellyfin-plugin-episodepostergenerator|Poster Generator|Custom Styling for Episode Posters|192.5|10"
  "sync|JPKribs/jellyfin-plugin-serversync|Server Sync|Sync Multiple Jellyfin Servers|192.5|10"
  "usermgmt|JPKribs/jellyfin-plugin-usermanagement|User Management|Group Management & User Invites|192.5|10"
  "youtube|JPKribs/jellyfin-plugin-youtubeaudio|YouTube Audio|Extract YouTube Audio|192.5|0"
)

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

sed -e "s|SWIFT_STARS_FORMATTED|$(format_k "$SWIFT_STARS")|g" \
    -e "s|SWIFT_DELTA_COLOR|$(delta_color "$SWIFT_DIFF")|g" \
    -e "s|SWIFT_DELTA|$(format_delta "$SWIFT_DIFF")|g" \
    "$TEMPLATES/swiftfin-card.svg" > "$OUT/swiftfin.svg"

# ---------------------------------------------------------------------------
# Plugin cards
# ---------------------------------------------------------------------------

for entry in "${PLUGINS[@]}"; do
  IFS='|' read -r id repo title desc width gutter <<< "$entry"
  echo "Fetching stars for $repo..." >&2
  stars=$(fetch_stars "$repo")
  stars=$(star_fallback "$stars" "${id}_stars")
  diff=$((stars - $(hist_old "${id}_stars")))
  entry_set "${id}_stars" "$stars"

  # Geometry from card width: total SVG width includes the transparent
  # gutter; contents center on the visible card, whose rect is inset 0.75
  # for the 1.5 stroke; the 59.3-wide logo is centered.
  read -r svg_w rect_w center logo_x <<< "$(awk -v w="$width" -v g="$gutter" \
    'BEGIN{printf "%g %g %g %g", w+g, w-1.5, w/2, w/2-29.65}')"

  sed -e "s|SVG_W|$svg_w|g" \
      -e "s|RECT_W|$rect_w|g" \
      -e "s|CENTER|$center|g" \
      -e "s|LOGO_X|$logo_x|g" \
      -e "s|PLUGIN_TITLE|$(esc "$title")|g" \
      -e "s|PLUGIN_DESC|$(esc "$desc")|g" \
      -e "s|PLUGIN_STARS|$stars|g" \
      -e "s|PLUGIN_DELTA_COLOR|$(delta_color "$diff")|g" \
      -e "s|PLUGIN_DELTA|$(format_delta "$diff")|g" \
      "$TEMPLATES/plugin-card.svg" > "$OUT/$id.svg"
done

# ---------------------------------------------------------------------------
# Footer card (contact info + last-updated date)
# ---------------------------------------------------------------------------

sed -e "s|UPDATED|$(date -u +'%b %d, %Y')|g" \
    "$TEMPLATES/footer-card.svg" > "$OUT/footer.svg"

# ---------------------------------------------------------------------------
# Persist history (keep last 7 days)
# ---------------------------------------------------------------------------

# Replace any existing entry for today so reruns don't shrink the 7-day window.
jq --argjson entry "$ENTRY" '[$entry] + map(select(.date != $entry.date)) | .[0:7]' stats-history.json > stats-history-tmp.json
mv stats-history-tmp.json stats-history.json

echo "Done: $(ls "$OUT" | wc -l | tr -d ' ') cards written to $OUT/" >&2
