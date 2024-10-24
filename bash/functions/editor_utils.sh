#!/bin/bash

[[ -z "$_BASH_UTILS_INITIALIZED" ]] && source "${BASH_SOURCE%/*}/../init.sh"

detect_editor() {
    local -n editors_ref=$1
    
    for editor in "${editors_ref[@]}"; do
        if command -v "$editor" >/dev/null 2>&1; then
            echo "$editor"
            return 0
        fi
    done
    
    log_error "No suitable editor found. Please install one of: ${editors_ref[*]}"
    return 1
}

validate_editor_args() {
    local dir="$1"
    local editor="$2"
    
    if [[ ! -d "$dir" ]]; then
        log_error "Directory '$dir' does not exist"
        return 1
    fi

    if ! command -v "$editor" >/dev/null 2>&1; then
        log_error "Editor '$editor' not found"
        return 1
    fi

    return 0
}
