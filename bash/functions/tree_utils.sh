#!/bin/bash

[[ -z "$_BASH_UTILS_INITIALIZED" ]] && source "${BASH_SOURCE%/*}/../init.sh"

ctree() {
    local -A args=(
        ["directory"]="."
        ["max-depth"]="$DEFAULT_TREE_MAX_DEPTH"
        ["limit"]="$DEFAULT_TREE_ENTRY_LIMIT"
        ["no-color"]=$((1-DEFAULT_TREE_USE_COLOR))
        ["full-paths"]="$DEFAULT_TREE_FULL_PATHS"
        ["summary"]=0
    )

    if ! parse_options TREE_OPTIONS args "$@"; then
        generate_usage TREE_OPTIONS "ctree" TREE_USAGE_EXAMPLES
        return 1
    fi

    if [[ ${args["help"]} == 1 ]]; then
        generate_usage TREE_OPTIONS "ctree" TREE_USAGE_EXAMPLES
        return 0
    fi

    if [[ ! -d "${args["directory"]}" ]]; then
        log_error "Directory '${args["directory"]}' does not exist"
        return 1
    fi

    if ! command -v tree >/dev/null 2>&1; then
        log_error "'tree' command not found"
        return 1
    fi

    local tree_cmd="tree"
    [[ ${args["no-color"]} != 1 ]] && tree_cmd+=" -C"
    [[ -n "${args["max-depth"]}" ]] && tree_cmd+=" -L ${args["max-depth"]}"
    [[ ${args["full-paths"]} == 1 ]] && tree_cmd+=" -f"
    tree_cmd+=" --noreport"

    if ((args["summary"])); then
        eval "$tree_cmd '${args["directory"]}'" | awk '
            BEGIN { dirs=0; files=0; }
            /^[³ÃÀ].*\/$/ { dirs++ }
            /^[³ÃÀ].*[^\/]$/ { files++ }
            END {
                print "Directories:", dirs
                print "Files:", files
                print "Total:", dirs + files
            }'
    else
        eval "$tree_cmd '${args["directory"]}'" | awk -v limit="${args["limit"]}" '
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

export -f ctree
