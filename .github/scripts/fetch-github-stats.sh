#!/bin/bash

# Fetch real GitHub activity statistics

USERNAME="JPKribs"
GITHUB_API="https://api.github.com"
CURRENT_YEAR=$(date +%Y)

# Fetch all user repos
echo "Fetching repositories..." >&2
REPOS=$(curl -s -H "Authorization: Bearer ${GITHUB_TOKEN}" \
  "${GITHUB_API}/users/${USERNAME}/repos?per_page=100&type=all" | \
  jq -r '.[].full_name')

if [ -z "$REPOS" ]; then
  echo "Error: Failed to fetch repositories" >&2
  REPOS=""
fi

# Calculate total commits and yearly commits
TOTAL_COMMITS=0
YEAR_COMMITS=0
declare -A DAILY_COMMITS
declare -A LANGUAGE_BYTES

# Helper: paginated commit fetch — returns all commit dates for a given query
fetch_commit_dates() {
  local url="$1"
  local page=1
  while true; do
    RESPONSE=$(curl -s -H "Authorization: Bearer ${GITHUB_TOKEN}" \
      "${url}&per_page=100&page=${page}")
    DATES=$(echo "$RESPONSE" | jq -r '.[]? | .commit.author.date' 2>/dev/null)
    if [ -z "$DATES" ]; then break; fi
    echo "$DATES"
    COUNT=$(echo "$DATES" | wc -l | tr -d ' ')
    if [ "$COUNT" -lt 100 ]; then break; fi
    page=$((page + 1))
  done
}

YEAR_START="${CURRENT_YEAR}-01-01T00:00:00Z"

echo "Fetching commit data..." >&2
for repo in $REPOS; do
  # Fetch ALL commits for this repo by this user (paginated)
  ALL_DATES=$(fetch_commit_dates "${GITHUB_API}/repos/${repo}/commits?author=${USERNAME}")
  if [ -z "$ALL_DATES" ]; then
    REPO_COUNT=0
  else
    REPO_COUNT=$(echo "$ALL_DATES" | wc -l | tr -d ' ')
  fi
  TOTAL_COMMITS=$((TOTAL_COMMITS + REPO_COUNT))
  echo "  $repo: $REPO_COUNT commits" >&2

  # Process each commit date for yearly stats and daily tracking
  for commit_date in $ALL_DATES; do
    DAY=$(echo "$commit_date" | cut -d'T' -f1)
    DAILY_COMMITS[$DAY]=$((${DAILY_COMMITS[$DAY]:-0} + 1))

    # Count yearly commits
    if [[ "$commit_date" > "${YEAR_START}" ]] || [[ "$commit_date" == "${YEAR_START}" ]]; then
      YEAR_COMMITS=$((YEAR_COMMITS + 1))
    fi
  done

  # Get language byte counts for this repo
  REPO_LANGS=$(curl -s -H "Authorization: Bearer ${GITHUB_TOKEN}" \
    "${GITHUB_API}/repos/${repo}/languages" 2>/dev/null)

  if [ -n "$REPO_LANGS" ] && [ "$REPO_LANGS" != "null" ]; then
    for lang in $(echo "$REPO_LANGS" | jq -r 'keys[]' 2>/dev/null); do
      bytes=$(echo "$REPO_LANGS" | jq -r --arg l "$lang" '.[$l] // 0' 2>/dev/null)
      if [[ "$bytes" =~ ^[0-9]+$ ]]; then
        LANGUAGE_BYTES[$lang]=$((${LANGUAGE_BYTES[$lang]:-0} + bytes))
      fi
    done
  fi
done

# Calculate best streak (consecutive days with commits)
BEST_STREAK=0
CURRENT_STREAK=0
TEMP_STREAK=0

# Check last 365 days for streaks
for i in {0..365}; do
  if command -v gdate >/dev/null 2>&1; then
    DAY=$(gdate -u -d "${i} days ago" +%Y-%m-%d)
  else
    DAY=$(date -u -d "${i} days ago" +%Y-%m-%d 2>/dev/null || date -u -v-${i}d +%Y-%m-%d)
  fi

  if [ "${DAILY_COMMITS[$DAY]:-0}" -gt 0 ]; then
    TEMP_STREAK=$((TEMP_STREAK + 1))
    # Track current streak (from today backwards)
    if [ "$i" -eq 0 ] || [ "$CURRENT_STREAK" -gt 0 ]; then
      CURRENT_STREAK=$TEMP_STREAK
    fi
  else
    if [ "$TEMP_STREAK" -gt "$BEST_STREAK" ]; then
      BEST_STREAK=$TEMP_STREAK
    fi
    # Reset current streak if we hit today with no commits
    if [ "$i" -eq 0 ]; then
      CURRENT_STREAK=0
    fi
    TEMP_STREAK=0
  fi
done

if [ "$TEMP_STREAK" -gt "$BEST_STREAK" ]; then
  BEST_STREAK=$TEMP_STREAK
fi

# Get top 3 languages by byte count
TOTAL_BYTES=0
for lang in "${!LANGUAGE_BYTES[@]}"; do
  TOTAL_BYTES=$((TOTAL_BYTES + ${LANGUAGE_BYTES[$lang]}))
done
if [ "$TOTAL_BYTES" -eq 0 ]; then
  TOTAL_BYTES=1
fi

TOP_LANGS=$(for lang in "${!LANGUAGE_BYTES[@]}"; do
  bytes=${LANGUAGE_BYTES[$lang]}
  pct=$((bytes * 100 / TOTAL_BYTES))
  echo "$pct $lang"
done | sort -rn | head -4)

# If no languages found, provide defaults
if [ -z "$TOP_LANGS" ]; then
  TOP_LANGS="0 Unknown"
fi

# Fetch community stats
echo "Fetching community stats..." >&2
TOTAL_POSTS=0
TOTAL_REPLIES=0
TOTAL_DISCUSSIONS=0

# Get created issues (posts)
ISSUES_CREATED=$(curl -s -H "Authorization: Bearer ${GITHUB_TOKEN}" \
  "${GITHUB_API}/search/issues?q=author:${USERNAME}+type:issue" | \
  jq -r '.total_count // 0' 2>/dev/null)
TOTAL_POSTS=${ISSUES_CREATED:-0}

# Get issue comments (replies)
ISSUE_COMMENTS=$(curl -s -H "Authorization: Bearer ${GITHUB_TOKEN}" \
  "${GITHUB_API}/search/issues?q=commenter:${USERNAME}+-author:${USERNAME}" | \
  jq -r '.total_count // 0' 2>/dev/null)
TOTAL_REPLIES=${ISSUE_COMMENTS:-0}

# Get PR count (discussions)
PRS_CREATED=$(curl -s -H "Authorization: Bearer ${GITHUB_TOKEN}" \
  "${GITHUB_API}/search/issues?q=author:${USERNAME}+type:pr" | \
  jq -r '.total_count // 0' 2>/dev/null)
TOTAL_DISCUSSIONS=${PRS_CREATED:-0}

# Output data for use in workflow (without export, just echo)
echo "TOTAL_COMMITS=${TOTAL_COMMITS}"
echo "YEAR_COMMITS=${YEAR_COMMITS}"
echo "CURRENT_YEAR=${CURRENT_YEAR}"
echo "BEST_STREAK=${BEST_STREAK}"
echo "TOTAL_POSTS=${TOTAL_POSTS}"
echo "TOTAL_REPLIES=${TOTAL_REPLIES}"
echo "TOTAL_DISCUSSIONS=${TOTAL_DISCUSSIONS}"

# Output languages line by line to avoid eval issues
echo "LANG1_LINE='$(echo "$TOP_LANGS" | sed -n '1p')'"
echo "LANG2_LINE='$(echo "$TOP_LANGS" | sed -n '2p')'"
echo "LANG3_LINE='$(echo "$TOP_LANGS" | sed -n '3p')'"
echo "LANG4_LINE='$(echo "$TOP_LANGS" | sed -n '4p')'"
