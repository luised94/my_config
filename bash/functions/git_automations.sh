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
