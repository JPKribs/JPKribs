#!/bin/bash

# Fetch real GitHub activity statistics
# This script pulls actual data from GitHub API and generates SVG heatmap data

USERNAME="JPKribs"
GITHUB_API="https://api.github.com"

# Color mapping for contribution levels
get_color() {
  local count=$1
  if [ "$count" -eq 0 ]; then
    echo "#161b22"
  elif [ "$count" -le 3 ]; then
    echo "#0e4429"
  elif [ "$count" -le 6 ]; then
    echo "#006d32"
  elif [ "$count" -le 9 ]; then
    echo "#26a641"
  else
    echo "#39d353"
  fi
}

# Fetch all user repos
echo "Fetching repositories..." >&2
REPOS=$(curl -s -H "Authorization: token ${GITHUB_TOKEN}" \
  "${GITHUB_API}/users/${USERNAME}/repos?per_page=100&type=all" | \
  jq -r '.[].full_name')

# Calculate total commits across all repos
TOTAL_COMMITS=0
declare -A DAILY_COMMITS
declare -A LANGUAGE_BYTES

echo "Fetching commit data..." >&2
for repo in $REPOS; do
  # Get commits from last 50 days
  COMMITS=$(curl -s -H "Authorization: token ${GITHUB_TOKEN}" \
    "${GITHUB_API}/repos/${repo}/commits?author=${USERNAME}&per_page=100&since=$(date -u -v-50d +%Y-%m-%dT%H:%M:%SZ 2>/dev/null || date -u -d '50 days ago' +%Y-%m-%dT%H:%M:%SZ)" | \
    jq -r '.[] | .commit.author.date')

  for commit_date in $COMMITS; do
    DAY=$(echo "$commit_date" | cut -d'T' -f1)
    DAILY_COMMITS[$DAY]=$((${DAILY_COMMITS[$DAY]:-0} + 1))
    TOTAL_COMMITS=$((TOTAL_COMMITS + 1))
  done

  # Get language statistics
  LANGS=$(curl -s -H "Authorization: token ${GITHUB_TOKEN}" \
    "${GITHUB_API}/repos/${repo}/languages")

  while IFS=":" read -r lang bytes; do
    lang=$(echo "$lang" | tr -d '"' | xargs)
    bytes=$(echo "$bytes" | tr -d ',' | xargs)
    if [ -n "$lang" ] && [ -n "$bytes" ]; then
      LANGUAGE_BYTES[$lang]=$((${LANGUAGE_BYTES[$lang]:-0} + bytes))
    fi
  done < <(echo "$LANGS" | jq -r 'to_entries | .[] | "\(.key):\(.value)"')
done

# Calculate current and best streak
CURRENT_STREAK=0
BEST_STREAK=0
TEMP_STREAK=0
YESTERDAY=$(date -u -v-1d +%Y-%m-%d 2>/dev/null || date -u -d '1 day ago' +%Y-%m-%d)

for i in {0..49}; do
  DAY=$(date -u -v-${i}d +%Y-%m-%d 2>/dev/null || date -u -d "${i} days ago" +%Y-%m-%d)
  if [ "${DAILY_COMMITS[$DAY]:-0}" -gt 0 ]; then
    TEMP_STREAK=$((TEMP_STREAK + 1))
    if [ "$i" -eq 0 ] || [ "$CURRENT_STREAK" -gt 0 ]; then
      CURRENT_STREAK=$((CURRENT_STREAK + 1))
    fi
  else
    if [ "$TEMP_STREAK" -gt "$BEST_STREAK" ]; then
      BEST_STREAK=$TEMP_STREAK
    fi
    TEMP_STREAK=0
    if [ "$i" -le 1 ]; then
      CURRENT_STREAK=0
    fi
  fi
done

if [ "$TEMP_STREAK" -gt "$BEST_STREAK" ]; then
  BEST_STREAK=$TEMP_STREAK
fi

# Calculate language percentages
TOTAL_BYTES=0
for bytes in "${LANGUAGE_BYTES[@]}"; do
  TOTAL_BYTES=$((TOTAL_BYTES + bytes))
done

declare -A LANGUAGE_PCT
for lang in "${!LANGUAGE_BYTES[@]}"; do
  PCT=$((${LANGUAGE_BYTES[$lang]} * 100 / TOTAL_BYTES))
  LANGUAGE_PCT[$lang]=$PCT
done

# Get top 3 languages
TOP_LANGS=$(for lang in "${!LANGUAGE_PCT[@]}"; do
  echo "${LANGUAGE_PCT[$lang]} $lang"
done | sort -rn | head -3)

# Generate heatmap SVG for last 49 days (7 weeks x 7 days)
HEATMAP_SVG=""
X_START=60
Y_START=445
CELL_SIZE=10
CELL_GAP=13

for week in {0..6}; do
  X_POS=$((X_START + week * CELL_GAP))

  for day in {0..6}; do
    DAY_INDEX=$((week * 7 + day))
    DATE=$(date -u -v-$((48 - DAY_INDEX))d +%Y-%m-%d 2>/dev/null || date -u -d "$((48 - DAY_INDEX)) days ago" +%Y-%m-%d)
    COMMITS=${DAILY_COMMITS[$DATE]:-0}
    COLOR=$(get_color $COMMITS)
    Y_POS=$((Y_START + day * CELL_GAP))

    HEATMAP_SVG="${HEATMAP_SVG}              <rect x=\"${X_POS}\" y=\"${Y_POS}\" width=\"${CELL_SIZE}\" height=\"${CELL_SIZE}\" rx=\"2\" fill=\"${COLOR}\"/>\n"
  done
  HEATMAP_SVG="${HEATMAP_SVG}\n"
done

# Export data for use in workflow
echo "TOTAL_COMMITS=${TOTAL_COMMITS}"
echo "CURRENT_STREAK=${CURRENT_STREAK}"
echo "BEST_STREAK=${BEST_STREAK}"
echo "TOP_LANGS<<EOF"
echo "$TOP_LANGS"
echo "EOF"
echo "HEATMAP_SVG<<EOF"
echo -e "$HEATMAP_SVG"
echo "EOF"
