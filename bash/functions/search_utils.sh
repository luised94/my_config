#!/bin/bash

[[ -z "$_BASH_UTILS_INITIALIZED" ]] && source "${BASH_SOURCE%/*}/../init.sh"

count_string() {
    local search_string="$1"
    local search_dir="${2:-.}"
    local -A args=(
        ["verbose"]="$DEFAULT_SEARCH_VERBOSE"
        ["quiet"]="$DEFAULT_SEARCH_QUIET"
    )

    # Parse options using the common parser
    if ! parse_options SEARCH_OPTIONS args "$@"; then
        generate_usage SEARCH_OPTIONS "count_string"
        return 1
    fi

    # Show help if requested
    if [[ ${args["help"]} == 1 ]]; then
        generate_usage SEARCH_OPTIONS "count_string"
        return 0
    fi

    # Rest of your count_string function...
    # (Updated to use logging functions and configuration)
}
