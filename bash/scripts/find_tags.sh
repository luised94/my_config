#!/bin/bash

set -euo pipefail

source "../functions/repo_handler.sh"
source "../functions/tag_processor.sh"

function show_usage() {
    cat << EOF
Usage: $(basename "$0") [OPTIONS]
Searches for tagged comments in source files

Options:
    --tag TAG               Tag to search for (default: ${FILE_DEFAULTS[DEFAULT_TAG]})
    --directory DIR         Search directory (default: current directory)
    --file-extensions EXTS  Comma-separated list of extensions
    -h, --help             Show this help message

Example:
    $(basename "$0") --tag TODO --directory src --file-extensions sh,R,py
EOF
}

function main() {
    local tag="${FILE_DEFAULTS[DEFAULT_TAG]}"
    local directory="."
    local extensions=("${FILE_DEFAULTS[EXTENSIONS[@]}")
    
    while [[ $# -gt 0 ]]; do
        case $1 in
            --tag) tag="$2"; shift 2 ;;
            --directory) directory="$2"; shift 2 ;;
            --file-extensions) IFS=',' read -r -a extensions <<< "$2"; shift 2 ;;
            -h|--help) show_usage; exit 0 ;;
            *) log_error "Unknown option: $1"; show_usage; exit 1 ;;
        esac
    done
    
    # Find repository root and resolve paths
    local repo_root=$(find_git_root)
    local readme_path=$(find_readme "$repo_root") || exit 1
    directory=$(resolve_path "$directory" "$repo_root")
    
    # Validate tag against README
    local valid_tags=$(extract_tags "$readme_path")
    validate_tag "$tag" "$valid_tags" || true  # Continue even if tag not found
    
    # Build and execute search
    local find_cmd=$(build_find_command "$directory" "${extensions[@]}")
    local results=$(search_tags "$directory" "$tag" "$find_cmd")
    
    if [ -n "$results" ]; then
        echo "$results"
        local count=$(echo "$results" | wc -l)
        log_info "Found $count instance(s) of #$tag"
    fi
}

main "$@"
