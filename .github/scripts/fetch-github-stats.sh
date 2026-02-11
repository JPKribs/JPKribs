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

echo "Fetching commit data..." >&2
for repo in $REPOS; do
  # Get total commit count for this repo
  REPO_TOTAL=$(curl -s -H "Authorization: Bearer ${GITHUB_TOKEN}" \
    "${GITHUB_API}/repos/${repo}/commits?author=${USERNAME}&per_page=1" | \
    jq -r 'length')

  # Try to get commit count from contributor stats
  CONTRIBUTOR_STATS=$(curl -s -H "Authorization: Bearer ${GITHUB_TOKEN}" \
    "${GITHUB_API}/repos/${repo}/stats/contributors")

  CONTRIBUTOR_COMMITS=$(echo "$CONTRIBUTOR_STATS" | \
    jq -r --arg user "$USERNAME" '.[] | select(.author.login == $user) | .total // 0' 2>/dev/null)

  # Fallback: if contributor stats failed or returned 0, count commits directly
  if [ -z "$CONTRIBUTOR_COMMITS" ] || [ "$CONTRIBUTOR_COMMITS" = "0" ]; then
    echo "  Contributor stats unavailable for $repo, counting commits directly..." >&2
    DIRECT_COUNT=$(curl -s -H "Authorization: Bearer ${GITHUB_TOKEN}" \
      "${GITHUB_API}/repos/${repo}/commits?author=${USERNAME}&per_page=100" | \
      jq -r 'length' 2>/dev/null)

    if [ -n "$DIRECT_COUNT" ] && [ "$DIRECT_COUNT" != "0" ]; then
      TOTAL_COMMITS=$((TOTAL_COMMITS + DIRECT_COUNT))
      echo "    Found $DIRECT_COUNT commits via direct count" >&2
    fi
  else
    TOTAL_COMMITS=$((TOTAL_COMMITS + CONTRIBUTOR_COMMITS))
    echo "  $repo: $CONTRIBUTOR_COMMITS commits" >&2
  fi

  # Get commits from current year for yearly stats and daily tracking
  YEAR_START="${CURRENT_YEAR}-01-01T00:00:00Z"
  YEAR_COMMITS_DATA=$(curl -s -H "Authorization: Bearer ${GITHUB_TOKEN}" \
    "${GITHUB_API}/repos/${repo}/commits?author=${USERNAME}&per_page=100&since=${YEAR_START}" | \
    jq -r '.[]? | .commit.author.date' 2>/dev/null)

  for commit_date in $YEAR_COMMITS_DATA; do
    YEAR_COMMITS=$((YEAR_COMMITS + 1))
    DAY=$(echo "$commit_date" | cut -d'T' -f1)
    DAILY_COMMITS[$DAY]=$((${DAILY_COMMITS[$DAY]:-0} + 1))
  done

  # Also get commits from past 365 days for streak calculation
  PAST_YEAR=$(date -u -d '365 days ago' +%Y-%m-%dT%H:%M:%SZ 2>/dev/null || date -u -v-365d +%Y-%m-%dT%H:%M:%SZ)
  PAST_COMMITS_DATA=$(curl -s -H "Authorization: Bearer ${GITHUB_TOKEN}" \
    "${GITHUB_API}/repos/${repo}/commits?author=${USERNAME}&per_page=100&since=${PAST_YEAR}" | \
    jq -r '.[]? | .commit.author.date' 2>/dev/null)

  for commit_date in $PAST_COMMITS_DATA; do
    DAY=$(echo "$commit_date" | cut -d'T' -f1)
    DAILY_COMMITS[$DAY]=$((${DAILY_COMMITS[$DAY]:-0} + 1))
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
done | sort -rn | head -3)

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
