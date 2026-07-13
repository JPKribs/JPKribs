#!/bin/bash

# Generate the profile README cards (cards/*.svg) from templates/ and update
# stats-history.json.
#
# Each card is a standalone SVG so the README can wrap every one in its own
# link — GitHub strips <a> elements inside SVGs rendered through <img>, so
# per-repo links are only possible with per-repo images.
#
# Every dynamic card is rendered twice: the desktop layout and a full-width
# 800px "-mobile" variant with larger type. The README picks between them
# with <picture><source media="(max-width: ...)"> so narrow viewports get a
# uniform stack of full-width cards instead of wrapped fixed-width rows.
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
# The id doubles as the output filename and the stats-history.json key prefix
# (<id>_stars) — existing ids must not change or delta history resets.
#
# Layout: every desktop plugin card is a uniform 202.5px SVG — a 192.5px
# visible card with a 5px transparent gutter baked into EACH side, so cards
# wrap like a centered flex row at any container width: 4 per row when
# there's room (4×202.5 = 810, visible span exactly 800 to match the
# full-width cards), then 3/2/1 as it narrows. The README puts all of them
# in ONE centered <div> with no whitespace between images. Every card
# template also carries a 10px transparent bottom pad (footer excepted) so
# vertical gaps match the horizontal ones exactly.
# Descriptions must stay short enough for the 192.5px cards (~34 chars at
# 10px) and must not contain "|" (the field delimiter). Plain "&" is fine
# — titles/descriptions are XML- and sed-escaped before substitution.
# Ordered alphabetically by display title.
PLUGINS=(
  "custompages|JPKribs/jellyfin-plugin-custompages|Custom Pages|Permission Gated Custom Pages"
  "ddns|JPKribs/jellyfin-plugin-ddns|DDNS|Simple DDNS Manager"
  "livechannels|JPKribs/jellyfin-plugin-livechannels|Live Channels|Live TV Channels from Libraries"
  "poster|JPKribs/jellyfin-plugin-episodepostergenerator|Poster Generator|Custom Styling for Episode Posters"
  "sync|JPKribs/jellyfin-plugin-serversync|Server Sync|Sync Multiple Jellyfin Servers"
  "usermgmt|JPKribs/jellyfin-plugin-usermanagement|User Management|Group Management & User Invites"
  "youtube|JPKribs/jellyfin-plugin-youtubeaudio|YouTube Audio|Extract YouTube Audio"
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
  IFS='|' read -r id repo title desc <<< "$entry"
  echo "Fetching stars for $repo..." >&2
  stars=$(fetch_stars "$repo")
  stars=$(star_fallback "$stars" "${id}_stars")
  diff=$((stars - $(hist_old "${id}_stars")))
  entry_set "${id}_stars" "$stars"

  for variant in "" "-mobile"; do
    sed -e "s|PLUGIN_TITLE|$(esc "$title")|g" \
        -e "s|PLUGIN_DESC|$(esc "$desc")|g" \
        -e "s|PLUGIN_STARS|$stars|g" \
        -e "s|PLUGIN_DELTA_COLOR|$(delta_color "$diff")|g" \
        -e "s|PLUGIN_DELTA|$(format_delta "$diff")|g" \
        "$TEMPLATES/plugin-card$variant.svg" > "$OUT/$id$variant.svg"
  done
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
