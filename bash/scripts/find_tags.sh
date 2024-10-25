#!/bin/bash

[[ -z "$_BASH_UTILS_INITIALIZED" ]] && source "${BASH_SOURCE%/*}/../init.sh"

# Main tag search function
find_tags() {
    local -A args=(
        ["tag"]="${FILE_DEFAULTS[DEFAULT_TAG]}"
        ["directory"]="."
        ["extensions"]="${FILE_DEFAULTS[EXTENSIONS]}"
    )

    # Parse options
    if ! parse_options TAG_SEARCH_OPTIONS args "$@"; then
        generate_usage TAG_SEARCH_OPTIONS "find_tags"
        return 1
    }

    # Show help if requested
    if [[ ${args["help"]} == 1 ]]; then
        generate_usage TAG_SEARCH_OPTIONS "find_tags"
        return 0
    }

    # Find repository root and resolve paths
    local repo_root=$(find_git_root)
    local readme_path=$(find_readme "$repo_root") || exit 1
    local directory=$(resolve_path "${args["directory"]}" "$repo_root")
    
    # Validate tag against README
    local valid_tags=$(extract_tags "$readme_path")
    validate_tag "${args["tag"]}" "$valid_tags" || true  # Continue even if tag not found
    
    # Convert extensions string to array
    local IFS=',' read -r -a extensions <<< "${args["extensions"]}"
    
    # Build and execute search
    local find_cmd=$(build_find_command "$directory" "${extensions[@]}")
    local results=$(search_tags "$directory" "${args["tag"]}" "$find_cmd")
    
    if [ -n "$results" ]; then
        echo "$results"
        local count=$(echo "$results" | wc -l)
        log_info "Found $count instance(s) of #${args["tag"]}"
    fi
}

# Run if script is executed directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    find_tags "$@"
fi
