#!/bin/bash

[[ -z "$_BASH_UTILS_INITIALIZED" ]] && source "${BASH_SOURCE%/*}/../init.sh"

build_tree_command() {
    local -n args_ref=$1
    local tree_cmd="tree"
    
    [[ ${args_ref["no-color"]} != 1 ]] && tree_cmd+=" -C"
    [[ -n "${args_ref["max-depth"]}" ]] && tree_cmd+=" -L ${args_ref["max-depth"]}"
    [[ ${args_ref["full-paths"]} == 1 ]] && tree_cmd+=" -f"
    tree_cmd+=" --noreport"
    
    echo "$tree_cmd"
}

process_tree_output() {
    local tree_cmd="$1"
    local summary_only="$2"
    local entry_limit="$3"
    local dir="$4"
    
    if ((summary_only)); then
        log_info "Generating directory summary for: $dir"
        eval "$tree_cmd '$dir'" | awk '
            BEGIN { dirs=0; files=0; }
            /^[³ÃÀ].*\/$/ { dirs++ }
            /^[³ÃÀ].*[^\/]$/ { files++ }
            END {
                print "Directories:", dirs
                print "Files:", files
                print "Total:", dirs + files
            }'
    else
        log_info "Generating condensed tree view for: $dir"
        eval "$tree_cmd '$dir'" | awk -v limit="$entry_limit" '
            function print_buffered() {
                if (count > 0) {
                    if (limit == "" || count <= limit) {
                        for (i = 1; i <= count; i++) {
                            print buffer[i]
                        }
                    } else {
                        for (i = 1; i <= limit - 1; i++) {
                            print buffer[i]
                        }
                        print "ÃÄÄ ... and " (count - limit + 1) " more items"
                    }
                }
                count = 0
            }
            {
                if ($0 ~ /^[ ³ÃÀ]/) {
                    buffer[++count] = $0
                } else {
                    print_buffered()
                    print $0
                }
            }
            END {
                print_buffered()
            }' | sed '
                /^$/N;/^\n$/D
                s/ÃÄÄ /ÃÄ/g
                s/ÀÄÄ /ÀÄ/g
                s/³   /³ /g'
    fi
}

ctree() {
    local -A args=(
        ["directory"]="."
        ["max-depth"]="$DEFAULT_TREE_MAX_DEPTH"
        ["limit"]="$DEFAULT_TREE_ENTRY_LIMIT"
        ["no-color"]=$((1-DEFAULT_TREE_USE_COLOR))
        ["full-paths"]="$DEFAULT_TREE_FULL_PATHS"
        ["summary"]=0
    )

    # Parse options
    if ! parse_options TREE_OPTIONS args "$@"; then
        generate_usage TREE_OPTIONS "ctree"
        return 1
    }

    # Show help if requested
    if [[ ${args["help"]} == 1 ]]; then
        generate_usage TREE_OPTIONS "ctree"
        return 0
    }

    # Validate directory
    if [[ ! -d "${args["directory"]}" ]]; then
        log_error "Directory '${args["directory"]}' does not exist"
        return 1
    }

    # Check for tree command
    if ! command -v tree >/dev/null 2>&1; then
        log_error "'tree' command not found"
        return 1
    }

    # Build tree command
    local tree_cmd=$(build_tree_command args)
    
    # Process output
    process_tree_output "$tree_cmd" "${args["summary"]}" "${args["limit"]}" "${args["directory"]}"
}
