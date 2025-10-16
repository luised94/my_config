#!/bin/bash
# git_download_repos_from_username.sh
# Download all repos from github using API.
# Uses username and set root directory
# Does not access private repos. Must use API key for that.
# Date: 2025-09-08
# Version: 1.0.0

echo "========== Start: ${BASH_SOURCE[0]} =========="
if ! command -v git >/dev/null 2>&1; then
  echo "Git is not installed" >&2
  return 1
fi

REPOSITORIES_ROOT="$HOME/personal_repos/"
USERNAME="luised94"

echo "--- Script parameters ---"
echo "ROOT DIRECTORY: ${REPOSITORIES_ROOT}"
echo "Username: ${USERNAME}"
echo "-------------------------"

# Use API. Think the output is JSON.
# Can replace with jq
mapfile -t git_repositories < <(
  curl -s "https://api.github.com/users/$USERNAME/repos?per_page=100" |
  grep "full_name" | awk -F'[/"]' '{print $5}'
)
# Couple with curl command to clone all the repos.
#grep -o 'git@[^"]*' | \
#xargs -L1 git clone

# Search REPOSITORIES_ROOT for repos already present.
# Filter results using '-', a unique string found in worktree names.
# Take the name of the repo as the last part of the string divided by '/' separator
mapfile -t repos_downloaded < <(
  find "$REPOSITORIES_ROOT" -maxdepth 1 -mindepth 1 -type d |
  grep -v "-" |
  awk -F'/' '{print $NF}'
)

echo "-------------------------"
echo "Number of repos found: ${#git_repositories[@]}"
echo "Repos found:"
printf '%s\n' "${git_repositories[@]}"
echo "-------------------------"
echo "Number of repos already downloaded: ${#repos_downloaded[@]}"
echo "Repos downloaded:"
printf '%s\n' "${repos_downloaded[@]}"
echo "-------------------------"

# Exit if number of repo found and repo downloaded is same.
# Disable to see rest of script when you want to see results.
if [ "${#repos_downloaded[@]}" -eq "${#git_repositories[@]}" ]; then
  echo "All repos found via API are downloaded."
  echo "Exiting..."
  exit 0
fi

# For all found repos, if already downloaed, skip.
# Otherwise, clone the repo to REPOSITORIES_ROOT
for repo in "${git_repositories[@]}"; do
  echo "Current repo: $repo"
  if [[ "${repos_downloaded[@]}" =~ "$repo" ]]; then
    echo "Repo is already downloaded."
    echo "-------------------------"
    continue
  fi
  # @QUES Would it make more sense to check the directory as well?
  echo "Repo is not downloaded."
  repo_url="https://github.com/$USERNAME/${repo}.git"
  echo "Repo url to clone: $repo_url"
  echo "git clone $repo_url ${REPOSITORIES_ROOT}$repo"
  git clone $repo_url "${REPOSITORIES_ROOT}$repo"
  echo "-------------------------"
done

