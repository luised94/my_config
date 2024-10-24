#!/bin/bash

[[ -z "$_BASH_UTILS_INITIALIZED" ]] && source "${BASH_SOURCE%/*}/../init.sh"

parse_options() {
    local -n opts_ref=$1  # Reference to options array
    local -n args_ref=$2  # Reference to arguments array
    shift 2

    while [[ $# -gt 0 ]]; do
        local matched=0
        for opt_def in "${opts_ref[@]}"; do
            local opt_pattern="${opt_def%%:*}"
            local short_opt="${opt_pattern%%|*}"
            local long_opt="${opt_pattern##*|}"
            local description="${opt_def#*:}"
            local requires_value=0
            [[ "$description" == *"(requires value)"* ]] && requires_value=1

            if [[ "$1" == "-$short_opt" ]] || [[ "$1" == "--$long_opt" ]]; then
                matched=1
                if ((requires_value)); then
                    if [[ -z "$2" ]]; then
                        log_error "Option $1 requires a value"
                        return 1
                    fi
                    args_ref["$long_opt"]="$2"
                    shift 2
                else
                    args_ref["$long_opt"]=1
                    shift
                fi
                break
            fi
        done

        if ((matched == 0)); then
            if [[ "$1" == -* ]]; then
                log_error "Unknown option: $1"
                return 1
            else
                args_ref["positional"]="${args_ref["positional"]} $1"
                shift
            fi
        fi
    done
    return 0
}

generate_usage() {
    local -n opts_ref=$1
    local script_name=$2
    
    echo "Usage: $script_name [OPTIONS]"
    echo "Options:"
    for opt_def in "${opts_ref[@]}"; do
        local opt_pattern="${opt_def%%:*}"
        local short_opt="${opt_pattern%%|*}"
        local long_opt="${opt_pattern##*|}"
        local description="${opt_def#*:}"
        printf "  -%s, --%-15s %s\n" "$short_opt" "$long_opt" "$description"
    done
}
