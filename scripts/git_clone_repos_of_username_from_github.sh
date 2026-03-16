#!/bin/bash
# git_download_repos_from_username.sh
# Clone missing repos from a GitHub user account.
# Does not access private repos. Must use API key for that.
# NOTE: GitHub API caps at 100 repos per page. If you exceed 100 repos,
#       pagination via the Link response header is required.
# Date: 2026-03-03
# Version: 2.0.0
set -euo pipefail

# ------------------------------------------------------------------------------
usage() {
  printf "Usage: %s [-u username] [-h]\n\n" "$(basename "$0")"
  printf "Clone missing repos from a GitHub user account.\n\n"
  printf "Options:\n"
  printf "  -u username  GitHub username (default: luised94)\n"
  printf "  -h, --help   Show this help message\n"
  exit 0
}
# ------------------------------------------------------------------------------

# --- Parse arguments ---
USERNAME="luised94"

while (( $# > 0 )); do
  case "$1" in
    -h|--help) usage ;;
    -u)
      [[ -z "${2:-}" ]] && { echo "Error: -u requires a username" >&2; exit 1; }
      USERNAME="$2"; shift 2 ;;
    *)
      echo "Error: Unknown option: $1" >&2
      echo "Run '$(basename "$0") -h' for usage." >&2
      exit 1 ;;
  esac
done

echo "========== Start: ${BASH_SOURCE[0]} =========="

if ! command -v git >/dev/null 2>&1; then
  echo "Error: Git is not installed" >&2
  exit 1
fi

if ! command -v jq >/dev/null 2>&1; then
  echo "Error: jq is not installed (apt install jq / brew install jq)" >&2
  exit 1
fi

REPOSITORIES_ROOT="$HOME/personal_repos"
# Set to "https" or "ssh"
CLONE_PROTOCOL="https"

echo "--- Script parameters ---"
echo "ROOT DIRECTORY: ${REPOSITORIES_ROOT}"
echo "Username: ${USERNAME}"
echo "Protocol: ${CLONE_PROTOCOL}"
echo "-------------------------"

# --- Fetch repo list from GitHub API ---
api_response=$(curl -sf "https://api.github.com/users/$USERNAME/repos?per_page=100") || {
  echo "Error: Failed to fetch repos from GitHub API (network issue or rate limit)" >&2
  exit 1
}

mapfile -t git_repositories < <(printf '%s' "$api_response" | jq -r '.[].name')

if (( ${#git_repositories[@]} == 0 )); then
  echo "No repositories found for user $USERNAME"
  exit 0
fi

# --- Identify locally present repos (main worktrees only, not linked worktrees) ---
declare -A repos_downloaded=()

for dir in "$REPOSITORIES_ROOT"/*/; do
  [[ ! -d "$dir" ]] && continue
  dir="${dir%/}"

  # Skip non-git directories
  git -C "$dir" rev-parse --git-dir >/dev/null 2>&1 || continue

  # Skip linked worktrees - only count main worktrees as "downloaded"
  local_git_dir=$(git -C "$dir" rev-parse --git-dir 2>/dev/null)
  if [[ "$local_git_dir" != ".git" && "$local_git_dir" != "$dir/.git" ]]; then
    continue
  fi

  repo_name="$(basename "$dir")"
  repos_downloaded["$repo_name"]=1
done

echo "-------------------------"
echo "Repos on GitHub: ${#git_repositories[@]}"
printf '  %s\n' "${git_repositories[@]}"
echo "-------------------------"
echo "Repos already cloned: ${#repos_downloaded[@]}"
printf '  %s\n' "${!repos_downloaded[@]}"
echo "-------------------------"

# --- Clone missing repos ---
clone_count=0

for repo in "${git_repositories[@]}"; do
  if [[ -n "${repos_downloaded[$repo]+x}" ]]; then
    continue
  fi

  if [[ "$CLONE_PROTOCOL" == "ssh" ]]; then
    repo_url="git@github.com:${USERNAME}/${repo}.git"
  else
    repo_url="https://github.com/${USERNAME}/${repo}.git"
  fi

  echo "Cloning: $repo"
  echo "  $repo_url -> ${REPOSITORIES_ROOT}/${repo}"

  if git clone "$repo_url" "${REPOSITORIES_ROOT}/${repo}"; then
    clone_count=$((clone_count + 1))
  else
    echo "Error: Failed to clone $repo" >&2
  fi

  echo "-------------------------"
done

# --- Summary ---
if (( clone_count == 0 )); then
  echo "All repos already cloned."
else
  echo "Cloned $clone_count new repo(s)."
fi

echo "========== End: ${BASH_SOURCE[0]} =========="
