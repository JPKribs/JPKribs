#!/bin/bash

# Fetch real GitHub activity statistics.
#
# Commits, current-year commits, and streaks come from the GraphQL
# contributionsCollection API — the same data behind the green contribution
# graph. That deduplicates forks automatically, counts org contributions
# (e.g. jellyfin/Swiftfin), and resets the year boundary correctly. The old
# approach looped over /users/<me>/repos and counted commits per repo, which
# double/triple-counted any commit that also lived in a fork (Swiftfin,
# jellyfin-sdk-swift, jellyfin.org) and silently undercounted org work.
#
# Pull requests / issues / comments still use the cross-repo search API, and
# language bytes still come from the REST languages endpoint.

USERNAME="JPKribs"
GITHUB_API="https://api.github.com"
GRAPHQL_API="https://api.github.com/graphql"

# Prefer a dedicated stats PAT if one is provided, otherwise the workflow token.
TOKEN="${STATS_TOKEN:-${GITHUB_TOKEN}}"

CURRENT_YEAR=$(date -u +%Y)

# Portable YYYY-MM-DD -> UTC epoch seconds (GNU date or BSD/macOS date).
to_epoch() {
  if command -v gdate >/dev/null 2>&1; then
    gdate -u -d "$1" +%s
  else
    date -u -d "$1" +%s 2>/dev/null || date -u -j -f "%Y-%m-%d" "$1" +%s
  fi
}

# ---------------------------------------------------------------------------
# Commits + streaks via GraphQL contributionsCollection
# ---------------------------------------------------------------------------

# contributionsCollection accepts at most a one-year window, so we query once
# per calendar year from account creation to now and accumulate.
gql_contrib() {
  local from="$1" to="$2"
  curl -s -H "Authorization: Bearer ${TOKEN}" -H "Content-Type: application/json" \
    -X POST "${GRAPHQL_API}" \
    -d "{\"query\":\"query(\$login:String!,\$from:DateTime!,\$to:DateTime!){user(login:\$login){contributionsCollection(from:\$from,to:\$to){totalCommitContributions contributionCalendar{weeks{contributionDays{date contributionCount}}}}}}\",\"variables\":{\"login\":\"${USERNAME}\",\"from\":\"${from}\",\"to\":\"${to}\"}}"
}

echo "Resolving account creation date..." >&2
CREATED=$(curl -s -H "Authorization: Bearer ${TOKEN}" "${GITHUB_API}/users/${USERNAME}" | jq -r '.created_at // empty')
START_YEAR="${CREATED:0:4}"
if ! [[ "$START_YEAR" =~ ^[0-9]{4}$ ]]; then
  START_YEAR=$CURRENT_YEAR
fi

TOTAL_COMMITS=0
YEAR_COMMITS=0
DAYS_FILE=$(mktemp)

echo "Fetching contribution data ${START_YEAR}..${CURRENT_YEAR}..." >&2
for (( Y=START_YEAR; Y<=CURRENT_YEAR; Y++ )); do
  FROM="${Y}-01-01T00:00:00Z"
  if [ "$Y" -eq "$CURRENT_YEAR" ]; then
    TO="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
  else
    TO="${Y}-12-31T23:59:59Z"
  fi

  RESP=$(gql_contrib "$FROM" "$TO")
  CC=$(echo "$RESP" | jq -r '.data.user.contributionsCollection.totalCommitContributions // 0' 2>/dev/null)
  if [[ "$CC" =~ ^[0-9]+$ ]]; then
    TOTAL_COMMITS=$((TOTAL_COMMITS + CC))
    if [ "$Y" -eq "$CURRENT_YEAR" ]; then
      YEAR_COMMITS=$CC
    fi
    echo "  $Y: $CC commit contributions" >&2
  fi

  # Append "date count" rows for streak computation.
  echo "$RESP" | jq -r '.data.user.contributionsCollection.contributionCalendar.weeks[]?.contributionDays[]? | "\(.date) \(.contributionCount)"' 2>/dev/null >> "$DAYS_FILE"
done

# Longest run of consecutive active days (best streak), plus the run that ends
# today/yesterday (current streak).
ACTIVE=$(awk '$2+0 > 0 {print $1}' "$DAYS_FILE" | sort -u)

BEST_STREAK=0
CURRENT_STREAK=0
RUN=0
PREV_EPOCH=0
LAST_EPOCH=0
LAST_RUN=0
for d in $ACTIVE; do
  e=$(to_epoch "$d")
  if [ "$PREV_EPOCH" -ne 0 ] && [ $((e - PREV_EPOCH)) -eq 86400 ]; then
    RUN=$((RUN + 1))
  else
    RUN=1
  fi
  if [ "$RUN" -gt "$BEST_STREAK" ]; then BEST_STREAK=$RUN; fi
  PREV_EPOCH=$e
  LAST_EPOCH=$e
  LAST_RUN=$RUN
done

if [ "$LAST_EPOCH" -ne 0 ]; then
  TODAY_EPOCH=$(to_epoch "$(date -u +%Y-%m-%d)")
  # Current streak is live only if the latest active day is today or yesterday.
  if [ $((TODAY_EPOCH - LAST_EPOCH)) -le 86400 ]; then
    CURRENT_STREAK=$LAST_RUN
  fi
fi

rm -f "$DAYS_FILE"

# ---------------------------------------------------------------------------
# Language bytes via REST (top 4 by total bytes across repos)
# ---------------------------------------------------------------------------

declare -A LANGUAGE_BYTES

echo "Fetching repositories for language stats..." >&2
REPOS=$(curl -s -H "Authorization: Bearer ${TOKEN}" \
  "${GITHUB_API}/users/${USERNAME}/repos?per_page=100&type=all" | \
  jq -r '.[].full_name')

for repo in $REPOS; do
  REPO_LANGS=$(curl -s -H "Authorization: Bearer ${TOKEN}" \
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

if [ -z "$TOP_LANGS" ]; then
  TOP_LANGS="0 Unknown"
fi

# ---------------------------------------------------------------------------
# Community stats via search API
# ---------------------------------------------------------------------------

echo "Fetching community stats..." >&2

ISSUES_CREATED=$(curl -s -H "Authorization: Bearer ${TOKEN}" \
  "${GITHUB_API}/search/issues?q=author:${USERNAME}+type:issue" | \
  jq -r '.total_count // 0' 2>/dev/null)
TOTAL_POSTS=${ISSUES_CREATED:-0}

ISSUE_COMMENTS=$(curl -s -H "Authorization: Bearer ${TOKEN}" \
  "${GITHUB_API}/search/issues?q=commenter:${USERNAME}+-author:${USERNAME}" | \
  jq -r '.total_count // 0' 2>/dev/null)
TOTAL_REPLIES=${ISSUE_COMMENTS:-0}

PRS_CREATED=$(curl -s -H "Authorization: Bearer ${TOKEN}" \
  "${GITHUB_API}/search/issues?q=author:${USERNAME}+type:pr" | \
  jq -r '.total_count // 0' 2>/dev/null)
TOTAL_DISCUSSIONS=${PRS_CREATED:-0}

# ---------------------------------------------------------------------------
# Output (consumed via eval in the workflow)
# ---------------------------------------------------------------------------

echo "TOTAL_COMMITS=${TOTAL_COMMITS}"
echo "YEAR_COMMITS=${YEAR_COMMITS}"
echo "CURRENT_YEAR=${CURRENT_YEAR}"
echo "BEST_STREAK=${BEST_STREAK}"
echo "CURRENT_STREAK=${CURRENT_STREAK}"
echo "TOTAL_POSTS=${TOTAL_POSTS}"
echo "TOTAL_REPLIES=${TOTAL_REPLIES}"
echo "TOTAL_DISCUSSIONS=${TOTAL_DISCUSSIONS}"

echo "LANG1_LINE='$(echo "$TOP_LANGS" | sed -n '1p')'"
echo "LANG2_LINE='$(echo "$TOP_LANGS" | sed -n '2p')'"
echo "LANG3_LINE='$(echo "$TOP_LANGS" | sed -n '3p')'"
echo "LANG4_LINE='$(echo "$TOP_LANGS" | sed -n '4p')'"
