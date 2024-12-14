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
    git fetch --all --prune
    
    git branch -r | grep -v '\->' | sed 's/origin\///' | while read branch; do
        if ! git show-ref --verify --quiet refs/heads/"$branch"; then
            echo "${OUTPUT_SYMBOLS[PROCESSING]}Creating local branch for $branch"
            git branch --track "$branch" origin/"$branch"
        fi
    done
    
    git pull --all
    echo "${OUTPUT_SYMBOLS[SUCCESS]}All branches synced"
}
