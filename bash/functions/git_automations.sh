#!/bin/bash

[[ -z "$_BASH_UTILS_INITIALIZED" ]] && source "${BASH_SOURCE%/*}/../init.sh"

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

    display_message "START" "Syncing all remote branches (Dry Run: ${dry_run})"

    git fetch --all --prune

    for remote in $(git remote); do
        for branch in $(git branch -r | grep "^$remote/"); do
            branch_name=$(echo "$branch" | sed "s/^$remote\///")

            if ! git show-ref --verify --quiet "refs/heads/$branch_name"; then
                if "$dry_run"; then
                    display_message "INFO" "(Dry Run) Would create and checkout local branch '$branch_name' tracking '$branch'"
                else
                    git checkout --track "$branch"
                    display_message "PROCESSING" "Created and checked out local branch '$branch_name' tracking '$branch'"
                fi
            else
                git checkout "$branch_name"

                if has_uncommitted_changes; then
                    display_changes $branch
                    display_message "ERROR" "Local branch '$branch_name' has uncommitted changes. Please commit or stash them before syncing."
                    continue # Skip to the next branch
                fi

                if [[ $(git rev-list HEAD...@{upstream} --count) -gt 0 ]]; then
                    if "$dry_run"; then
                        display_message "INFO" "(Dry Run) Would pull changes for '$branch_name' from '$branch'"
                    else
                        git pull --ff-only "$remote" "$branch_name"
                        if [[ $? -ne 0 ]]; then
                            display_message "WARNING" "Pull failed for '$branch_name'. Local changes might exist. Consider stashing or committing."
                        else
                            display_message "SUCCESS" "Updated local branch '$branch_name' from '$branch'"
                        fi
                    fi
                else
                    display_message "INFO" "Local branch '$branch_name' is up-to-date."
                fi
            fi
        done
    done

    display_message "SUCCESS" "Finished updating local branches."
}

new_branch() {
    validate_dir_is_git_repo || return 1
    is_remote_reachable || return 1

    local branch_name="$1"
    local base_branch="${2:-main}"
    local dry_run=false

    while [[ $# -gt 0 ]]; do
        case "$1" in
            -n|--dry-run)
                dry_run=true
                shift
                ;;
            -b|--base)
                base_branch="$2"
                shift 2
                ;;
            *)
                branch_name="$1"
                shift
                ;;
        esac
    done

    if [[ -z "$branch_name" ]]; then
        display_message ERROR "Usage: new_branch <branch-name> [-b base_branch] [-n|--dry-run]"
        return 1
    fi

    if has_uncommitted_changes; then
        display_changes "current"
        display_message ERROR "Please commit or stash changes before creating new branch"
        return 1
    fi

    if branch_exists "$branch_name"; then
        display_message ERROR "Branch '$branch_name' already exists locally"
        return 1
    fi

    if branch_exists "$branch_name" true; then
        display_message ERROR "Branch '$branch_name' already exists remotely"
        return 1
    fi

    if "$dry_run"; then
        display_message INFO "Would create new branch '$branch_name' from '$base_branch'"
        return 0
    fi

    display_message START "Creating new branch '$branch_name' from '$base_branch'"

    git checkout "$base_branch" || {
        display_message ERROR "Failed to checkout $base_branch"
        return 1
    }

    git pull origin "$base_branch" || {
        display_message ERROR "Failed to update $base_branch"
        return 1
    }

    if git checkout -b "$branch_name"; then
        if git push -u origin "$branch_name"; then
            display_message SUCCESS "Branch '$branch_name' created and pushed to origin"
            return 0
        else
            display_message ERROR "Failed to push branch '$branch_name' to origin"
            return 1
        fi
    else
        display_message ERROR "Failed to create branch '$branch_name'"
        return 1
    fi
}
