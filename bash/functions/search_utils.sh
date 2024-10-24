#!/bin/bash

[[ -z "$_BASH_UTILS_INITIALIZED" ]] && source "${BASH_SOURCE%/*}/../init.sh"

count_string() {
    local -A args=(
        ["verbose"]="$DEFAULT_SEARCH_VERBOSE"
        ["quiet"]="$DEFAULT_SEARCH_QUIET"
        ["directory"]="."
    )

    # Parse options
    if ! parse_options SEARCH_OPTIONS args "$@"; then
        generate_usage SEARCH_OPTIONS "count_string"
        return 1
    fi

    # Show help if requested
    if [[ ${args["help"]} == 1 ]]; then
        generate_usage SEARCH_OPTIONS "count_string"
        return 0
    fi

    local search_string="${args["positional"]}"
    if [[ -z "$search_string" ]]; then
        log_error "Search string is required"
        return 1
    fi

    # Build exclude arguments
    local exclude_args=($(build_exclude_args DEFAULT_SEARCH_EXCLUDE_DIRS DEFAULT_SEARCH_EXCLUDE_FILES))
    
    # Create temporary files for results
    local tmp_dir=$(mktemp -d)
    local files_with="$tmp_dir/with.txt"
    local files_without="$tmp_dir/without.txt"
    trap 'rm -rf "$tmp_dir"' EXIT

    # Find and categorize files
    if ((args["verbose"])); then
        log_info "Searching for files containing: '$search_string'"
    fi

    find "${args["directory"]}" ${args["max-depth"]:+-maxdepth ${args["max-depth"]}} \
        -type f "${exclude_args[@]}" -print0 2>/dev/null | \
        while IFS= read -r -d $'\0' file; do
            if grep -q "$search_string" "$file" 2>/dev/null; then
                echo "$file" >> "$files_with"
            else
                echo "$file" >> "$files_without"
            fi
        done

    # Count results
    local count_with=$(wc -l < "$files_with" || echo 0)
    local count_without=$(wc -l < "$files_without" || echo 0)
    local total=$((count_with + count_without))

    # Output results
    if ((! args["quiet"])); then
        log_info "Files containing the string:"
        if [[ -s "$files_with" ]]; then
            sed 's/^/  /' "$files_with"
        else
            echo "  None found"
        fi
        
        log_info "Files missing the string:"
        if [[ -s "$files_without" ]]; then
            sed 's/^/  /' "$files_without"
        else
            echo "  None found"
        fi
        
        log_info "Summary:"
        echo "  Files containing string: $count_with"
        echo "  Files missing string: $count_without"
        echo "  Total files checked: $total"
    else
        echo "$count_with"
    fi
}
