#!/bin/bash

[[ -z "$_BASH_UTILS_INITIALIZED" ]] && source "${BASH_SOURCE%/*}/../init.sh"

validate_dir_is_git_repo() {
    if ! git rev-parse --is-inside-work-tree > /dev/null 2>&1; then
        display_message "ERROR" "This script must be run from a git repository."
        exit 1
    fi
    return 0
}

has_uncommitted_changes() {
    validate_dir_is_git_repo
    # Check if there are any changes staged or unstaged
    if [[ -n $(git status --porcelain) ]]; then
        return 0 # Has uncommitted changes
    else
        return 1 # No uncommitted changes
    fi
}

display_changes() {
    validate_dir_is_git_repo
    local branch_name="$1"
    local staged=false
    local unstaged=false

    if [[ -n $(git diff --cached --name-status) ]]; then # check for staged
        staged=true
    fi
    if [[ -n $(git diff --name-status) ]]; then # check for unstaged
        unstaged=true
    fi
    
    if "$staged" || "$unstaged"; then
        display_message "WARNING" "Local branch '$branch_name' has the following changes:"
        if "$staged"; then
            echo "Staged changes:"
            git diff --cached --stat
        fi
        if "$unstaged"; then
            echo "Unstaged changes:"
            git diff --stat
        fi
    else
        display_message "INFO" "No changes found on branch '$branch_name'."
    fi
}

is_remote_reachable() {
    local remote="${1:-origin}" # Default to origin
    if ! git ls-remote --exit-code "$remote" > /dev/null 2>&1; then
        echo "Remote '$remote' is not reachable. Check your network connection or remote configuration."
        return 1 # Remote is not reachable
    fi
    return 0 # Remote is reachable
}

branch_exists() {
    local branch_name="$1"
    local remote="${2:-false}" # Default to local branch check
    if "$remote"; then
        git show-ref --verify --quiet "refs/remotes/origin/$branch_name"
    else
        git show-ref --verify --quiet "refs/heads/$branch_name"
    fi
}
