#!/bin/bash
# git_download_repos_from_username.sh
# Download all repos from github using API.
# Uses username and set root directory
# Does not access private repos. Requires API key.
# Date: 2025-09-08
# Version: 1.0.0

echo "========== Start: ${BASH_SOURCE[0]} =========="
if ! command -v git >/dev/null 2>&1; then
  echo "Git is not installed" >&2
  return 1
fi

ROOT_DIRECTORY="$HOME/personal_repos/"
USERNAME="luised94"

echo "--- Script parameters ---"
echo "ROOT DIRECTORY: ${ROOT_DIRECTORY}"
echo "Username: ${USERNAME}"
echo "-------------------------"

mapfile -t git_repositories < <(
  curl -s "https://api.github.com/users/$USERNAME/repos?per_page=100" |
  grep "full_name" | awk -F'[/"]' '{print $5}'
)

repos_downloaded=$(find "$ROOT_DIRECTORY" -maxdepth 1 -mindepth 1 -type d | grep -v "-" | awk -F'/' '{print $NF}')
echo "-------------------------"
echo "Repos downloaded:"
printf '%s\n' "${repos_downloaded[@]}"
echo "-------------------------"

for repo in "${git_repositories[@]}"; do
  echo "Current repo: $repo"
  if [[ "${repos_downloaded[@]}" =~ "$repo" ]]; then
    echo "Repo is already downloaded."
    echo "-------------------------"
    continue
  fi
  echo "Repo is not downloaded."
  repo_url="https://github.com/$USERNAME/${repo}.git"
  echo "Repo url to clone: $repo_url"
  echo "git clone $repo_url $ROOT_DIRECTORY"
  echo "-------------------------"
done

#grep -o 'git@[^"]*' | \
#xargs -L1 git clone
