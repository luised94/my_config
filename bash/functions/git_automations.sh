#!/bin/bash

[[ -z "$_BASH_UTILS_INITIALIZED" ]] && source "${BASH_SOURCE%/*}/../init.sh"

validate_dir_is_git_repo() {
    if ! git rev-parse --is-inside-work-tree > /dev/null 2>&1; then
        echo "${OUTPUT_SYMBOLS[ERROR]}This script must be run from a git repository."
        exit 1
    fi
    return 0
}

sync_all_branches() {
  validate_dir_is_git_repo

  echo "${OUTPUT_SYMBOLS[START]}Syncing all remote branches"

  # Fetch all remotes and prune stale references
  git fetch --all --prune

  # Iterate through each remote
  for remote in $(git remote); do
    # Iterate through remote branches for the current remote
    for branch in $(git branch -r | grep "^$remote/"); do
      # Extract the branch name without the remote prefix
      branch_name=$(echo "$branch" | sed "s/^$remote\///")

      # Check if a local branch with the same name exists
      if ! git show-ref --verify --quiet "refs/heads/$branch_name"; then
        # Create a local tracking branch and checkout
        git checkout --track "$branch" # Simplified creation and checkout
        echo "${OUTPUT_SYMBOLS[PROCESSING]}Created and checked out local branch '$branch_name' tracking '$branch'"
      else
        # Checkout the existing local branch
        git checkout "$branch_name"

        # Check if there are upstream changes (optional)
        if [[ $(git rev-list HEAD...@{upstream} --count) -gt 0 ]]; then
          # Pull changes only if there are upstream changes
          git pull --ff-only "$remote" "$branch_name"
          if [[ $? -ne 0 ]]; then
            echo "${OUTPUT_SYMBOLS[WARNING]}Pull failed for '$branch_name'. Local changes might exist. Consider stashing or committing."
          else
              echo "${OUTPUT_SYMBOLS[SUCCESS]}Updated local branch '$branch_name' from '$branch'"
          fi
        else
          echo "${OUTPUT_SYMBOLS[INFO]}Local branch '$branch_name' is up-to-date."
        fi
      fi
    done
  done

  echo "${OUTPUT_SYMBOLS[SUCCESS]}Finished updating local branches."
}
