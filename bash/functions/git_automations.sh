#!/bin/bash

[[ -z "$_BASH_UTILS_INITIALIZED" ]] && source "${BASH_SOURCE%/*}/../init.sh"

validate_dir_is_git_repo() {
    if ! git rev-parse --is-inside-work-tree > /dev/null 2>&1; then
        echo "${OUTPUT_SYMBOLS[ERROR]}This script must be run from a git repository."
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
        echo "${OUTPUT_SYMBOLS[WARNING]}Local branch '$branch_name' has the following changes:"
        if "$staged"; then
            echo "Staged changes:"
            git diff --cached --stat
        fi
        if "$unstaged"; then
            echo "Unstaged changes:"
            git diff --stat
        fi
    else
        echo "${OUTPUT_SYMBOLS[INFO]}No changes found on branch '$branch_name'."
    fi
}

sync_all_branches() {
    local dry_run=false
    while [[ $# -gt 0 ]]; do
        case "$1" in
            -n|--dry-run)
                dry_run=true
                shift
                ;;
            *)
                break
                ;;
        esac
    done

    validate_dir_is_git_repo

    echo "${OUTPUT_SYMBOLS[START]}Syncing all remote branches (Dry Run: ${dry_run})"

    git fetch --all --prune

    for remote in $(git remote); do
        for branch in $(git branch -r | grep "^$remote/"); do
            branch_name=$(echo "$branch" | sed "s/^$remote\///")

            if ! git show-ref --verify --quiet "refs/heads/$branch_name"; then
                if "$dry_run"; then
                    echo "${OUTPUT_SYMBOLS[INFO]}(Dry Run) Would create and checkout local branch '$branch_name' tracking '$branch'"
                else
                    git checkout --track "$branch"
                    echo "${OUTPUT_SYMBOLS[PROCESSING]}Created and checked out local branch '$branch_name' tracking '$branch'"
                fi
            else
                git checkout "$branch_name"

                if has_uncommitted_changes; then
                    display_changes $branch
                    echo "${OUTPUT_SYMBOLS[ERROR]}Local branch '$branch_name' has uncommitted changes. Please commit or stash them before syncing."
                    continue # Skip to the next branch
                fi

                if [[ $(git rev-list HEAD...@{upstream} --count) -gt 0 ]]; then
                    if "$dry_run"; then
                        echo "${OUTPUT_SYMBOLS[INFO]}(Dry Run) Would pull changes for '$branch_name' from '$branch'"
                    else
                        git pull --ff-only "$remote" "$branch_name"
                        if [[ $? -ne 0 ]]; then
                            echo "${OUTPUT_SYMBOLS[WARNING]}Pull failed for '$branch_name'. Local changes might exist. Consider stashing or committing."
                        else
                            echo "${OUTPUT_SYMBOLS[SUCCESS]}Updated local branch '$branch_name' from '$branch'"
                        fi
                    fi
                else
                    echo "${OUTPUT_SYMBOLS[INFO]}Local branch '$branch_name' is up-to-date."
                fi
            fi
        done
    done

    echo "${OUTPUT_SYMBOLS[SUCCESS]}Finished updating local branches."
}
