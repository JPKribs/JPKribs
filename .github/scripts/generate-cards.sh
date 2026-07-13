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

# id | repo | display title | description | visible width | right gutter.
#
# The id doubles as the output filename and the stats-history.json key prefix
# (<id>_stars) — existing ids must not change or delta history resets.
#
# Layout: the desktop grid only ever shows on github.com viewports ≥1280px,
# where the profile README column is a FIXED 846px (measured Jul 2026; the
# column is fluid below that, and the README swaps to full-width mobile
# cards there — see the README's <picture> sources). Rows are therefore
# static and sized to fill the column flush, flex-grow style:
#   row 1: 4 cards × 203.75 visible + 3×10 gutters = 845
#   row 2: 3 cards × 275    visible + 2×10 gutters = 845
# (845, not 846, leaves 1px slack so subpixel rounding can never overflow
# the column and wrap a card.) The gutter is transparent right-side padding
# baked into the SVG; the last card of each row has none. Every card
# template also carries a 10px transparent bottom pad (footer excepted) so
# vertical gaps match the horizontal ones exactly.
# Descriptions must stay short enough for the ~204px row-1 cards (~34 chars
# at 10px) and must not contain "|" (the field delimiter). Plain "&" is fine
# — titles/descriptions are XML- and sed-escaped before substitution.
# Alphabetical by display title: row 1 gets the first 4, row 2 the rest.
PLUGINS=(
  "custompages|JPKribs/jellyfin-plugin-custompages|Custom Pages|Permission Gated Custom Pages|203.75|10"
  "ddns|JPKribs/jellyfin-plugin-ddns|DDNS|Simple DDNS Manager|203.75|10"
  "livechannels|JPKribs/jellyfin-plugin-livechannels|Live Channels|Live TV Channels from Libraries|203.75|10"
  "poster|JPKribs/jellyfin-plugin-episodepostergenerator|Poster Generator|Custom Styling for Episode Posters|203.75|0"
  "sync|JPKribs/jellyfin-plugin-serversync|Server Sync|Sync Multiple Jellyfin Servers|275|10"
  "usermgmt|JPKribs/jellyfin-plugin-usermanagement|User Management|Group Management & User Invites|275|10"
  "youtube|JPKribs/jellyfin-plugin-youtubeaudio|YouTube Audio|Extract YouTube Audio|275|0"
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

for variant in "" "-mobile"; do
  sed -e "s|SWIFT_STARS_FORMATTED|$(format_k "$SWIFT_STARS")|g" \
      -e "s|SWIFT_DELTA_COLOR|$(delta_color "$SWIFT_DIFF")|g" \
      -e "s|SWIFT_DELTA|$(format_delta "$SWIFT_DIFF")|g" \
      "$TEMPLATES/swiftfin-card$variant.svg" > "$OUT/swiftfin$variant.svg"
done

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

  # Mobile variant: fixed full-width layout. Its intrinsic size is 1600px
  # (2× the 800 viewBox) so it always exceeds the README column and
  # max-width:100% scales it to fill exactly.
  sed -e "s|PLUGIN_TITLE|$(esc "$title")|g" \
      -e "s|PLUGIN_DESC|$(esc "$desc")|g" \
      -e "s|PLUGIN_STARS|$stars|g" \
      -e "s|PLUGIN_DELTA_COLOR|$(delta_color "$diff")|g" \
      -e "s|PLUGIN_DELTA|$(format_delta "$diff")|g" \
      "$TEMPLATES/plugin-card-mobile.svg" > "$OUT/$id-mobile.svg"
done

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
