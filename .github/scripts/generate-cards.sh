#!/bin/bash

# Generate the profile README cards (cards/*.svg) from templates/ and update
# stats-history.json.
#
# Each card is a standalone SVG so the README can wrap every one in its own
# link — GitHub strips <a> elements inside SVGs rendered through <img>, so
# per-repo links are only possible with per-repo images.
#
# Runs in CI with GITHUB_TOKEN/STATS_TOKEN. Also runs locally without a token:
# star counts come from the unauthenticated API and activity stats fall back
# to the latest stats-history.json entry.

cd "$(dirname "$0")/../.." || exit 1

TEMPLATES=templates
OUT=cards
mkdir -p "$OUT"

TOKEN="${STATS_TOKEN:-${GITHUB_TOKEN:-}}"
AUTH=()
if [ -n "$TOKEN" ]; then
  AUTH=(-H "Authorization: Bearer ${TOKEN}")
fi

# id | repo | display title | card width | right gutter.
#
# The id doubles as the output filename and the stats-history.json key prefix
# (<id>_stars) — existing ids must not change or delta history resets.
#
# Layout: the README butts the row's images together with NO whitespace, so
# each row's SVG widths (card + gutter) must sum to exactly 800 to line up
# with the full-width cards. Row 1 is 3-up (3×260 + 2×10), row 2 is 4-up
# (4×192.5 + 3×10). The gutter is transparent padding baked into the SVG;
# the last card of each row has none.
PLUGINS=(
  "poster|JPKribs/jellyfin-plugin-episodepostergenerator|Poster Generator|260|10"
  "sync|JPKribs/jellyfin-plugin-serversync|Server Sync|260|10"
  "youtube|JPKribs/jellyfin-plugin-youtubeaudio|YouTube Audio|260|0"
  "custompages|JPKribs/jellyfin-plugin-custompages|Custom Pages|192.5|10"
  "ddns|JPKribs/jellyfin-plugin-ddns|DDNS|192.5|10"
  "livechannels|JPKribs/jellyfin-plugin-livechannels|Live Channels|192.5|10"
  "usermgmt|JPKribs/jellyfin-plugin-usermanagement|User Management|192.5|0"
)

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
  IFS='|' read -r id repo title width gutter <<< "$entry"
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
      -e "s|PLUGIN_TITLE|$title|g" \
      -e "s|PLUGIN_STARS|$stars|g" \
      -e "s|PLUGIN_DELTA_COLOR|$(delta_color "$diff")|g" \
      -e "s|PLUGIN_DELTA|$(format_delta "$diff")|g" \
      "$TEMPLATES/plugin-card.svg" > "$OUT/$id.svg"
done

# ---------------------------------------------------------------------------
# Activity + language stats card
# ---------------------------------------------------------------------------

TOTAL_COMMITS=0 YEAR_COMMITS=0 BEST_STREAK=0
TOTAL_POSTS=0 TOTAL_REPLIES=0 TOTAL_DISCUSSIONS=0
LANG1_LINE="" LANG2_LINE="" LANG3_LINE="" LANG4_LINE=""
CURRENT_YEAR=$(date -u +%Y)

if [ -n "$TOKEN" ]; then
  eval "$(bash .github/scripts/fetch-github-stats.sh)"
else
  echo "No token — using activity stats from history." >&2
fi

# Fallback to the newest history entry if the API returned nothing.
if [ "$TOTAL_COMMITS" -eq 0 ]; then TOTAL_COMMITS=$(echo "$PREV_DATA" | jq -r '.total_commits // 0'); fi
if [ "$YEAR_COMMITS" -eq 0 ]; then YEAR_COMMITS=$(echo "$PREV_DATA" | jq -r '.year_commits // 0'); fi
if [ "$BEST_STREAK" -eq 0 ]; then BEST_STREAK=$(echo "$PREV_DATA" | jq -r '.best_streak // 0'); fi
if [ "$TOTAL_POSTS" -eq 0 ]; then TOTAL_POSTS=$(echo "$PREV_DATA" | jq -r '.total_posts // 0'); fi
if [ "$TOTAL_REPLIES" -eq 0 ]; then TOTAL_REPLIES=$(echo "$PREV_DATA" | jq -r '.total_replies // 0'); fi
if [ "$TOTAL_DISCUSSIONS" -eq 0 ]; then TOTAL_DISCUSSIONS=$(echo "$PREV_DATA" | jq -r '.total_discussions // 0'); fi

# Monotonic guard: all-time totals only ever grow, so never let a transient
# API hiccup drop them. NOTE: year_commits is intentionally excluded — it
# must reset to ~0 each January.
PREV_COMMITS=$(echo "$PREV_DATA" | jq -r '.total_commits // 0')
PREV_POSTS=$(echo "$PREV_DATA" | jq -r '.total_posts // 0')
PREV_REPLIES=$(echo "$PREV_DATA" | jq -r '.total_replies // 0')
PREV_DISCUSSIONS=$(echo "$PREV_DATA" | jq -r '.total_discussions // 0')
if [ "$TOTAL_COMMITS" -lt "$PREV_COMMITS" ]; then TOTAL_COMMITS=$PREV_COMMITS; fi
if [ "$TOTAL_POSTS" -lt "$PREV_POSTS" ]; then TOTAL_POSTS=$PREV_POSTS; fi
if [ "$TOTAL_REPLIES" -lt "$PREV_REPLIES" ]; then TOTAL_REPLIES=$PREV_REPLIES; fi
if [ "$TOTAL_DISCUSSIONS" -lt "$PREV_DISCUSSIONS" ]; then TOTAL_DISCUSSIONS=$PREV_DISCUSSIONS; fi

# Parse top 4 languages (line format: "44 Swift"), falling back to history.
parse_lang_name() { echo "$1" | awk '{$1=""; print}' | sed 's/^ //'; }
parse_lang_pct()  { echo "$1" | awk '{print $1}'; }
LANG1_PCT=$(parse_lang_pct "$LANG1_LINE"); LANG1_NAME=$(parse_lang_name "$LANG1_LINE")
LANG2_PCT=$(parse_lang_pct "$LANG2_LINE"); LANG2_NAME=$(parse_lang_name "$LANG2_LINE")
LANG3_PCT=$(parse_lang_pct "$LANG3_LINE"); LANG3_NAME=$(parse_lang_name "$LANG3_LINE")
LANG4_PCT=$(parse_lang_pct "$LANG4_LINE"); LANG4_NAME=$(parse_lang_name "$LANG4_LINE")
for n in 1 2 3 4; do
  name_var="LANG${n}_NAME" pct_var="LANG${n}_PCT"
  if [ -z "${!name_var}" ]; then
    printf -v "$name_var" '%s' "$(echo "$PREV_DATA" | jq -r ".lang${n}.name // \"Unknown\"")"
    printf -v "$pct_var" '%s' "$(echo "$PREV_DATA" | jq -r ".lang${n}.pct // 0")"
  fi
  if ! [[ "${!pct_var}" =~ ^[0-9]+$ ]]; then printf -v "$pct_var" '0'; fi
done

lang_color() {
  case "$1" in
    Swift) echo "#F05138" ;;
    Go) echo "#00ADD8" ;;
    "C#") echo "#512BD4" ;;
    Python) echo "#3776AB" ;;
    JavaScript) echo "#F7DF1E" ;;
    TypeScript) echo "#3178C6" ;;
    *) echo "#8B949E" ;;
  esac
}

YEAR_DIFF=$((YEAR_COMMITS - $(hist_old year_commits)))
COMMITS_DIFF=$((TOTAL_COMMITS - $(hist_old total_commits)))
DISCUSSIONS_DIFF=$((TOTAL_DISCUSSIONS - $(hist_old total_discussions)))
UPDATED=$(date -u +'%b %d, %Y')

sed -e "s|BEST_STREAK|$BEST_STREAK|g" \
    -e "s|YEAR_COMMITS|$YEAR_COMMITS|g" \
    -e "s|CURRENT_YEAR|$CURRENT_YEAR|g" \
    -e "s|TOTAL_COMMITS|$TOTAL_COMMITS|g" \
    -e "s|TOTAL_DISCUSSIONS|$TOTAL_DISCUSSIONS|g" \
    -e "s|YEAR_DELTA_COLOR|$(delta_color "$YEAR_DIFF")|g" \
    -e "s|YEAR_DELTA|$(format_delta "$YEAR_DIFF")|g" \
    -e "s|COMMITS_DELTA_COLOR|$(delta_color "$COMMITS_DIFF")|g" \
    -e "s|COMMITS_DELTA|$(format_delta "$COMMITS_DIFF")|g" \
    -e "s|DISCUSSIONS_DELTA_COLOR|$(delta_color "$DISCUSSIONS_DIFF")|g" \
    -e "s|DISCUSSIONS_DELTA|$(format_delta "$DISCUSSIONS_DIFF")|g" \
    -e "s|LANG1_NAME|$LANG1_NAME|g" \
    -e "s|LANG1_PCT|$LANG1_PCT|g" \
    -e "s|LANG1_WIDTH|$((LANG1_PCT * 320 / 100))|g" \
    -e "s|LANG1_COLOR|$(lang_color "$LANG1_NAME")|g" \
    -e "s|LANG2_NAME|$LANG2_NAME|g" \
    -e "s|LANG2_PCT|$LANG2_PCT|g" \
    -e "s|LANG2_WIDTH|$((LANG2_PCT * 320 / 100))|g" \
    -e "s|LANG2_COLOR|$(lang_color "$LANG2_NAME")|g" \
    -e "s|LANG3_NAME|$LANG3_NAME|g" \
    -e "s|LANG3_PCT|$LANG3_PCT|g" \
    -e "s|LANG3_WIDTH|$((LANG3_PCT * 320 / 100))|g" \
    -e "s|LANG3_COLOR|$(lang_color "$LANG3_NAME")|g" \
    -e "s|LANG4_NAME|$LANG4_NAME|g" \
    -e "s|LANG4_PCT|$LANG4_PCT|g" \
    -e "s|LANG4_WIDTH|$((LANG4_PCT * 320 / 100))|g" \
    -e "s|LANG4_COLOR|$(lang_color "$LANG4_NAME")|g" \
    -e "s|UPDATED|$UPDATED|g" \
    "$TEMPLATES/stats-card.svg" > "$OUT/stats.svg"

# ---------------------------------------------------------------------------
# Persist history (keep last 7 days)
# ---------------------------------------------------------------------------

entry_set total_commits "$TOTAL_COMMITS"
entry_set year_commits "$YEAR_COMMITS"
entry_set best_streak "$BEST_STREAK"
entry_set total_posts "$TOTAL_POSTS"
entry_set total_replies "$TOTAL_REPLIES"
entry_set total_discussions "$TOTAL_DISCUSSIONS"
for n in 1 2 3 4; do
  name_var="LANG${n}_NAME" pct_var="LANG${n}_PCT"
  ENTRY=$(echo "$ENTRY" | jq --arg k "lang${n}" --arg n "${!name_var}" --argjson p "${!pct_var}" '.[$k] = {name: $n, pct: $p}')
done

# Replace any existing entry for today so reruns don't shrink the 7-day window.
jq --argjson entry "$ENTRY" '[$entry] + map(select(.date != $entry.date)) | .[0:7]' stats-history.json > stats-history-tmp.json
mv stats-history-tmp.json stats-history.json

echo "Done: $(ls "$OUT" | wc -l | tr -d ' ') cards written to $OUT/" >&2
