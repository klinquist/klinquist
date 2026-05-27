#!/usr/bin/env bash
set -euo pipefail

readme="${1:-README.md}"
owner="${GITHUB_OWNER:-klinquist}"
marker=" **Updated recently**"

if ! command -v curl >/dev/null 2>&1; then
  echo "curl is required" >&2
  exit 1
fi

if ! command -v jq >/dev/null 2>&1; then
  echo "jq is required" >&2
  exit 1
fi

if [[ ! -f "$readme" ]]; then
  echo "README not found: $readme" >&2
  exit 1
fi

if command -v gdate >/dev/null 2>&1; then
  cutoff="$(gdate -u -d '6 months ago' '+%Y-%m-%dT%H:%M:%SZ')"
elif date -u -v-6m '+%Y-%m-%dT%H:%M:%SZ' >/dev/null 2>&1; then
  cutoff="$(date -u -v-6m '+%Y-%m-%dT%H:%M:%SZ')"
else
  cutoff="$(date -u -d '6 months ago' '+%Y-%m-%dT%H:%M:%SZ')"
fi

repos_json="$(mktemp)"
updated_readme="$(mktemp)"
trap 'rm -f "$repos_json" "$updated_readme"' EXIT

if command -v gh >/dev/null 2>&1 &&
  gh repo list "$owner" --limit 200 --json name,pushedAt >/dev/null 2>&1; then
  gh repo list "$owner" --limit 200 --json name,pushedAt |
    jq '[.[] | {name: .name, pushed_at: .pushedAt}]' > "$repos_json"
else
  curl -fsSL "https://api.github.com/users/${owner}/repos?per_page=100&sort=updated" > "$repos_json"
fi

extra_repos_for_line() {
  local line="$1"

  case "$line" in
    *"motorlogbook.com"*) printf '%s\n' "motorlogbook.com" ;;
    *"caltrain-companion"*) printf '%s\n' "caltraincompanion" "caltraincompanion.com" "Caltrain-Next-Stop" ;;
    *"caltrain.live"*) printf '%s\n' "caltrain-live" "caltrainNotify" ;;
    *"potaparkpics.com"*) printf '%s\n' "potaparkpics.com" ;;
    *"offline-spotter"*) printf '%s\n' "OfflineSpotterApp" "offlinespotter.com" ;;
    *"mountainroads.com"*) printf '%s\n' "mountainroads.com" ;;
    *"chp-info.com"*) printf '%s\n' "chp-info.com" ;;
    *"potahunter.com"*) printf '%s\n' "potahunter.com" ;;
  esac
}

repo_recent() {
  local repo="$1"

  jq -e --arg repo "$repo" --arg cutoff "$cutoff" '
    any(.[]; .name == $repo and (.pushed_at // "") >= $cutoff)
  ' "$repos_json" >/dev/null
}

while IFS= read -r line || [[ -n "$line" ]]; do
  clean_line="$(
    printf '%s\n' "$line" |
      sed \
        -e 's/ \*\*GitHub commits recently\*\*//g' \
        -e 's/ \*\*Recently updated\*\*//g' \
        -e 's/ \*\*Updated recently\*\*//g'
  )"

  if [[ "$clean_line" == "- "* ]]; then
    repos="$(
      {
        printf '%s\n' "$clean_line" |
          grep -Eo "https://github.com/${owner}/[A-Za-z0-9._-]+" |
          sed -E "s#https://github.com/${owner}/##" || true
        extra_repos_for_line "$clean_line"
      } | sort -u
    )"

    recent=false
    for repo in $repos; do
      if repo_recent "$repo"; then
        recent=true
        break
      fi
    done

    if [[ "$recent" == true ]]; then
      clean_line="$(printf '%s\n' "$clean_line" | sed "s/: /${marker}: /")"
    fi
  fi

  printf '%s\n' "$clean_line" >> "$updated_readme"
done < "$readme"

mv "$updated_readme" "$readme"
trap - EXIT
rm -f "$repos_json"
