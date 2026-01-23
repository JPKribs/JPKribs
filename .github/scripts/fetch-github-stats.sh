#!/bin/bash

# Fetch real GitHub activity statistics

USERNAME="JPKribs"
GITHUB_API="https://api.github.com"
CURRENT_YEAR=$(date +%Y)

# Fetch all user repos
echo "Fetching repositories..." >&2
REPOS=$(curl -s -H "Authorization: token ${GITHUB_TOKEN}" \
  "${GITHUB_API}/users/${USERNAME}/repos?per_page=100&type=all" | \
  jq -r '.[].full_name')

# Calculate total commits and yearly commits
TOTAL_COMMITS=0
YEAR_COMMITS=0
declare -A DAILY_COMMITS
declare -A LANGUAGE_REPOS

echo "Fetching commit data..." >&2
for repo in $REPOS; do
  # Get all commits by user (for total)
  ALL_COMMITS=$(curl -s -H "Authorization: token ${GITHUB_TOKEN}" \
    "${GITHUB_API}/repos/${repo}/commits?author=${USERNAME}&per_page=100" | \
    jq -r 'length')
  TOTAL_COMMITS=$((TOTAL_COMMITS + ALL_COMMITS))

  # Get commits from current year
  YEAR_START="${CURRENT_YEAR}-01-01T00:00:00Z"
  YEAR_COMMITS_DATA=$(curl -s -H "Authorization: token ${GITHUB_TOKEN}" \
    "${GITHUB_API}/repos/${repo}/commits?author=${USERNAME}&per_page=100&since=${YEAR_START}" | \
    jq -r '.[] | .commit.author.date')

  for commit_date in $YEAR_COMMITS_DATA; do
    YEAR_COMMITS=$((YEAR_COMMITS + 1))
    DAY=$(echo "$commit_date" | cut -d'T' -f1)
    DAILY_COMMITS[$DAY]=$((${DAILY_COMMITS[$DAY]:-0} + 1))
  done

  # Get primary language for this repo
  PRIMARY_LANG=$(curl -s -H "Authorization: token ${GITHUB_TOKEN}" \
    "${GITHUB_API}/repos/${repo}" | jq -r '.language')

  if [ -n "$PRIMARY_LANG" ] && [ "$PRIMARY_LANG" != "null" ]; then
    LANGUAGE_REPOS[$PRIMARY_LANG]=$((${LANGUAGE_REPOS[$PRIMARY_LANG]:-0} + 1))
  fi
done

# Calculate best streak (consecutive days with commits)
BEST_STREAK=0
TEMP_STREAK=0

for i in {0..365}; do
  DAY=$(date -u -v-${i}d +%Y-%m-%d 2>/dev/null || date -u -d "${i} days ago" +%Y-%m-%d)
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
TOP_LANGS=$(for lang in "${!LANGUAGE_REPOS[@]}"; do
  count=${LANGUAGE_REPOS[$lang]}
  total_repos=$(echo "$REPOS" | wc -l)
  pct=$((count * 100 / total_repos))
  echo "$pct $lang"
done | sort -rn | head -3)

# Fetch community stats (discussions)
echo "Fetching community stats..." >&2
# Note: This requires GraphQL API for discussions
# For now, we'll use placeholder values
TOTAL_POSTS=0
TOTAL_REPLIES=0
TOTAL_DISCUSSIONS=0

# Try to get issue/PR comments as proxy for community activity
COMMENTS=$(curl -s -H "Authorization: token ${GITHUB_TOKEN}" \
  "${GITHUB_API}/search/issues?q=author:${USERNAME}+type:issue" | \
  jq -r '.total_count')
TOTAL_POSTS=${COMMENTS:-0}

PR_COMMENTS=$(curl -s -H "Authorization: token ${GITHUB_TOKEN}" \
  "${GITHUB_API}/search/issues?q=commenter:${USERNAME}+type:pr" | \
  jq -r '.total_count')
TOTAL_REPLIES=${PR_COMMENTS:-0}

DISCUSSIONS=$(curl -s -H "Authorization: token ${GITHUB_TOKEN}" \
  "${GITHUB_API}/search/issues?q=author:${USERNAME}+is:issue" | \
  jq -r '.total_count')
TOTAL_DISCUSSIONS=${DISCUSSIONS:-0}

# Export data for use in workflow
echo "TOTAL_COMMITS=${TOTAL_COMMITS}"
echo "YEAR_COMMITS=${YEAR_COMMITS}"
echo "CURRENT_YEAR=${CURRENT_YEAR}"
echo "BEST_STREAK=${BEST_STREAK}"
echo "TOTAL_POSTS=${TOTAL_POSTS}"
echo "TOTAL_REPLIES=${TOTAL_REPLIES}"
echo "TOTAL_DISCUSSIONS=${TOTAL_DISCUSSIONS}"
echo "TOP_LANGS<<EOF"
echo "$TOP_LANGS"
echo "EOF"
