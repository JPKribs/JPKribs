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
declare -A LANGUAGE_REPOS

echo "Fetching commit data..." >&2
for repo in $REPOS; do
  # Get commits from current year
  YEAR_START="${CURRENT_YEAR}-01-01T00:00:00Z"
  YEAR_COMMITS_DATA=$(curl -s -H "Authorization: Bearer ${GITHUB_TOKEN}" \
    "${GITHUB_API}/repos/${repo}/commits?author=${USERNAME}&per_page=100&since=${YEAR_START}" | \
    jq -r '.[]? | .commit.author.date' 2>/dev/null)

  for commit_date in $YEAR_COMMITS_DATA; do
    YEAR_COMMITS=$((YEAR_COMMITS + 1))
    TOTAL_COMMITS=$((TOTAL_COMMITS + 1))
    DAY=$(echo "$commit_date" | cut -d'T' -f1)
    DAILY_COMMITS[$DAY]=$((${DAILY_COMMITS[$DAY]:-0} + 1))
  done

  # Get primary language for this repo
  PRIMARY_LANG=$(curl -s -H "Authorization: Bearer ${GITHUB_TOKEN}" \
    "${GITHUB_API}/repos/${repo}" | jq -r '.language // empty' 2>/dev/null)

  if [ -n "$PRIMARY_LANG" ] && [ "$PRIMARY_LANG" != "null" ]; then
    LANGUAGE_REPOS[$PRIMARY_LANG]=$((${LANGUAGE_REPOS[$PRIMARY_LANG]:-0} + 1))
  fi
done

# Calculate best streak (consecutive days with commits)
BEST_STREAK=0
TEMP_STREAK=0

for i in {0..365}; do
  if command -v gdate >/dev/null 2>&1; then
    DAY=$(gdate -u -d "${i} days ago" +%Y-%m-%d)
  else
    DAY=$(date -u -d "${i} days ago" +%Y-%m-%d 2>/dev/null || date -u -v-${i}d +%Y-%m-%d)
  fi

  if [ "${DAILY_COMMITS[$DAY]:-0}" -gt 0 ]; then
    TEMP_STREAK=$((TEMP_STREAK + 1))
  else
    if [ "$TEMP_STREAK" -gt "$BEST_STREAK" ]; then
      BEST_STREAK=$TEMP_STREAK
    fi
    TEMP_STREAK=0
  fi
done

if [ "$TEMP_STREAK" -gt "$BEST_STREAK" ]; then
  BEST_STREAK=$TEMP_STREAK
fi

# Get top 3 languages by repo count
TOTAL_REPO_COUNT=$(echo "$REPOS" | grep -c .)
if [ "$TOTAL_REPO_COUNT" -eq 0 ]; then
  TOTAL_REPO_COUNT=1
fi

TOP_LANGS=$(for lang in "${!LANGUAGE_REPOS[@]}"; do
  count=${LANGUAGE_REPOS[$lang]}
  pct=$((count * 100 / TOTAL_REPO_COUNT))
  echo "$pct $lang"
done | sort -rn | head -3)

# If no languages found, provide defaults
if [ -z "$TOP_LANGS" ]; then
  TOP_LANGS="0 Unknown"
fi

# Fetch community stats (discussions)
echo "Fetching community stats..." >&2
TOTAL_POSTS=0
TOTAL_REPLIES=0
TOTAL_DISCUSSIONS=0

# Try to get issue/PR comments as proxy for community activity
COMMENTS=$(curl -s -H "Authorization: Bearer ${GITHUB_TOKEN}" \
  "${GITHUB_API}/search/issues?q=author:${USERNAME}+type:issue" | \
  jq -r '.total_count // 0' 2>/dev/null)
TOTAL_POSTS=${COMMENTS:-0}

PR_COMMENTS=$(curl -s -H "Authorization: Bearer ${GITHUB_TOKEN}" \
  "${GITHUB_API}/search/issues?q=commenter:${USERNAME}+type:pr" | \
  jq -r '.total_count // 0' 2>/dev/null)
TOTAL_REPLIES=${PR_COMMENTS:-0}

DISCUSSIONS=$(curl -s -H "Authorization: Bearer ${GITHUB_TOKEN}" \
  "${GITHUB_API}/search/issues?q=author:${USERNAME}+is:issue" | \
  jq -r '.total_count // 0' 2>/dev/null)
TOTAL_DISCUSSIONS=${DISCUSSIONS:-0}

# Export data for use in workflow
export TOTAL_COMMITS=${TOTAL_COMMITS}
export YEAR_COMMITS=${YEAR_COMMITS}
export CURRENT_YEAR=${CURRENT_YEAR}
export BEST_STREAK=${BEST_STREAK}
export TOTAL_POSTS=${TOTAL_POSTS}
export TOTAL_REPLIES=${TOTAL_REPLIES}
export TOTAL_DISCUSSIONS=${TOTAL_DISCUSSIONS}
export TOP_LANGS="$TOP_LANGS"
