#!/bin/bash
# git_download_repos_from_username.sh
# Download all repos from github using API.
# Uses username and set root directory
echo "========== Start: ${BASH_SOURCE[0]} =========="
if ! command -v git >/dev/null 2>&1; then
  echo "Git is not installed" >&2
  return 1
fi

ROOT_DIRECTORY="~/personal_repos/"
USERNAME="luised94"

echo "--- Script parameters ---"
echo "ROOT DIRECTORY: ${ROOT_DIRECTORY}"
echo "Username: ${USERNAME}"
echo "-------------------------"

curl -s "https://api.github.com/users/$USERNAME/repos?per_page=100"
