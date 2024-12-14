#!/bin/bash

[[ -z "$_BASH_UTILS_INITIALIZED" ]] && source "${BASH_SOURCE%/*}/../init.sh"

validate_dir_is_git_repo() {
    if ! git rev-parse --is-inside-work-tree > /dev/null 2>&1; then
        echo "${OUTPUT_SYMBOLS[ERROR]}This script must be run from a git repository."
        exit 1
    fi
    return 0
}
