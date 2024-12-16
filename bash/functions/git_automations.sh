#!/bin/bash

[[ -z "$_BASH_UTILS_INITIALIZED" ]] && source "${BASH_SOURCE%/*}/../init.sh"

sync_all_branches() {
    validate_dir_is_git_repo || return 1
    is_remote_reachable || return 1

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

sync_after_merge() {
    validate_dir_is_git_repo || return 1
    is_remote_reachable || return 1

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

    local current_branch=$(git rev-parse --abbrev-ref HEAD)

    display_message START "Syncing branches after merge"

    if "$dry_run"; then
        display_message INFO "Would update main branch"
    else
        git checkout main || {
            display_message ERROR "Failed to checkout main"
            return 1
        }
        git pull origin main || {
            display_message ERROR "Failed to update main"
            git checkout "$current_branch"
            return 1
        }
    fi

    local branches=$(git for-each-ref --format='%(refname:short)' refs/heads/ | grep -v '^main$')

    for branch in $branches; do
        git checkout "$branch" || {
            display_message ERROR "Failed to checkout branch '$branch'"
            continue
        }

        if has_uncommitted_changes; then
            display_changes "$branch"
            display_message WARNING "Skipping '$branch' due to uncommitted changes"
            continue
        fi

        if ! git rev-parse --quiet --verify "HEAD@{upstream}"; then
            display_message WARNING "Skipping '$branch' because it does not track a remote branch."
            continue
        fi

        if "$dry_run"; then
            display_message INFO "Would rebase '$branch' on main"
            continue
        fi

        display_message PROCESSING "Rebasing '$branch'"
        if git rebase main; then
            display_message SUCCESS "Rebased '$branch' on main"
        else
            display_message ERROR "Rebase failed for '$branch'. Aborting rebase."
            git rebase --abort
            return 1
        fi
    done

    if ! "$dry_run"; then
        git checkout "$current_branch" || {
            display_message ERROR "Failed to return to original branch '$current_branch'"
            return 1
        }
    fi

    display_message DONE "Branch synchronization (without pushing) complete"
}

push_all_branches() {
    validate_dir_is_git_repo || return 1
    is_remote_reachable || return 1

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
    display_message START "Pushing all local branches to remote"
    local current_branch=$(git rev-parse --abbrev-ref HEAD)
    local branches=$(git for-each-ref --format='%(refname:short)' refs/heads/ | grep -v '^main$')
    for branch in $branches; do
        git checkout "$branch" || {
            display_message ERROR "Failed to checkout branch '$branch'"
            continue
        }
        if "$dry_run"; then
            display_message INFO "Would push branch '$branch' to remote"
            continue
        fi
        display_message PROCESSING "Pushing '$branch' to remote"
        git push --force-with-lease origin "$branch" || {
            display_message WARNING "Failed to push '$branch'"
            continue
        }
        display_message SUCCESS "Pushed '$branch' to remote"
    done
    git checkout "$current_branch" || {
            display_message ERROR "Failed to return to original branch '$current_branch'"
            return 1
        }
    display_message DONE "Push complete"
}

list_merged_branches() {
    validate_dir_is_git_repo || return 1
    is_remote_reachable || return 1

    display_message START "Finding merged branches"

    local merged_branches=$(git branch --merged main | grep -v "^\*" | grep -v "main")

    if [[ -z "$merged_branches" ]]; then
        display_message INFO "No merged branches found."
        return 0
    fi

    display_message INFO "The following branches are merged into main and could be deleted:"
    echo "$merged_branches"

    display_message DONE "Finished finding merged branches"
    echo "$merged_branches" # Output the branches for the next function to use
}

delete_merged_branches() {
    validate_dir_is_git_repo || return 1
    is_remote_reachable || return 1

    local dry_run=false
    local really_force=false

    while [[ $# -gt 0 ]]; do
        case "$1" in
            -n|--dry-run)
                dry_run=true
                shift
                ;;
            --really-force)
                really_force=true
                shift
                ;;
            *)
                break
                ;;
        esac
    done

    local merged_branches="$@" # Get the branches from the previous function

    if [[ -z "$merged_branches" ]]; then
        display_message INFO "No branches provided to delete."
        return 0
    fi

    if ! "$really_force"; then
        display_message WARNING "You are about to delete the following branches:"
        echo "$merged_branches"
        read -p "Are you sure you want to proceed? (y/N) " -n 1 -r
        echo
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            display_message INFO "Deletion cancelled."
            return 0
        fi
    fi

    display_message START "Deleting merged branches"

    echo "$merged_branches" | while read branch; do
        if [[ -n "$branch" ]]; then
            if "$dry_run"; then
                display_message INFO "Would delete branch: $branch"
            else
                if "$really_force"; then
                    git branch -D "$branch"
                    if [[ $? -eq 0 ]]; then
                        git push origin --delete "$branch"
                        if [[ $? -eq 0 ]]; then
                            display_message SUCCESS "Force deleted branch: $branch"
                        else
                            display_message WARNING "Failed to delete remote branch: $branch. Local branch force deleted."
                        fi
                    else
                        display_message WARNING "Failed to force delete local branch: $branch."
                    fi
                else
                    git branch -d "$branch"
                    if [[ $? -eq 0 ]]; then
                        git push origin --delete "$branch"
                        if [[ $? -eq 0 ]]; then
                            display_message SUCCESS "Deleted branch: $branch"
                        else
                            display_message WARNING "Failed to delete remote branch: $branch. Local branch deleted."
                        fi
                    else
                        display_message WARNING "Failed to delete local branch: $branch."
                    fi
                fi
            fi
        fi
    done
    display_message DONE "Deletion process finished"
}
