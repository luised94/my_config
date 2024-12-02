#!/bin/bash

# Guard against initializing the script again. Must be run through init.sh.
[[ -z "$_BASH_UTILS_INITIALIZED" ]] && source "${BASH_SOURCE%/*}/../init.sh"

#=======================================================
# CLI Option Parser & Usage Generator
#=======================================================
# Core Components:
#   1. Option Definition Format:
#      <short_opt>|<long_opt>:<description>
#   
#   2. Pattern Elements:
#      - short_opt:    Single-letter flag (e.g., 'h')
#      - long_opt:     Full word flag (e.g., 'help')
#      - description:  Help text with optional value marker
#
# Special Markers:
#   - (requires value): Indicates option needs argument
#=======================================================

#=======================================================
# Option Parser Implementation Details
#=======================================================
# !! Option parsing logic
# Processing Flow:
#   1. Split on ':' -> extract pattern and description
#   2. Split pattern on '|' -> get short and long opts
#   3. Store components in respective variables
#
# Variable Mapping:
#   opt_pattern  = "h|help"
#   short_opt    = "h"
#   long_opt     = "help"
#   description  = "Show help message"
#=======================================================

# Constants for option parsing
readonly REQUIRES_VALUE_MARKER="(requires value)"
readonly OPTION_DELIMITER=":"
readonly OPTION_SEPARATOR="|"

###############################################################################
# Generates formatted usage information for a command-line tool
# Globals:
#   None
# Arguments:
#   $1 - Name reference to options array
#   $2 - Script/command name
#   $3 - Name reference to examples array
# Outputs:
#   Writes usage information to stdout
# Returns:
#   0 if successful, non-zero on error
###############################################################################
generate_usage() {
    # Input validation
    if [[ $# -ne 3 ]]; then
        log_error "generate_usage: Requires exactly 3 arguments"
        return 1
    fi

    local -n opts_ref=$1
    local script_name=$2
    local -n examples_ref=$3
    
    # Header
    printf "Usage: %s [OPTIONS]\n\n" "$script_name"
    #
    # Options section
    printf "Options:\n"

    local opt_def
    # !! Option parsing logic
    for opt_def in "${opts_ref[@]}"; do
        # Parse option definition
        local opt_pattern="${opt_def%%${OPTION_DELIMITER}*}"
        local short_opt="${opt_pattern%%${OPTION_SEPARATOR}*}"
        local long_opt="${opt_pattern##*${OPTION_SEPARATOR}}"
        local description="${opt_def#*${OPTION_DELIMITER}}"
        
        # Format and print option
        printf "  -%s, --%-20s %s\n" \
            "$short_opt" \
            "$long_opt" \
            "$description"
    done
    
    # Examples section (if provided)
    if [[ ${#examples_ref[@]} -gt 0 ]]; then
        printf "\nExamples:\n"
        local example
        for example in "${examples_ref[@]}"; do
            printf "  %s\n" "$example"
        done
    fi
}

###############################################################################
# Parses command-line options based on defined option patterns
# Globals:
#   None
# Arguments:
#   $1 - Name reference to options definition array
#   $2 - Name reference to arguments associative array
#   $@ - Command line arguments to parse
# Outputs:
#   Writes errors to stderr
# Returns:
#   0 if parsing successful, 1 if error
###############################################################################
parse_options() {
    # Input validation
    if [[ $# -lt 2 ]]; then
        log_error "parse_options: Requires at least 2 arguments"
        return 1
    fi

    local -n opts_ref=$1
    local -n args_ref=$2
    shift 2

    # Debug support
    [[ ${DEBUG:-0} -eq 1 ]] && set -x

    while [[ $# -gt 0 ]]; do
        local matched=0
        local current_arg="$1"

        # Handle special cases
        if [[ "$current_arg" != -* ]]; then
            # Non-option argument
            args_ref["positional"]="${args_ref["positional"]} $current_arg"
            shift
            continue
        fi

        # Process options
        local opt_def
        for opt_def in "${opts_ref[@]}"; do
            # Parse option definition
            local opt_pattern="${opt_def%%${OPTION_DELIMITER}*}"
            local short_opt="${opt_pattern%%${OPTION_SEPARATOR}*}"
            local long_opt="${opt_pattern##*${OPTION_SEPARATOR}}"
            local description="${opt_def#*${OPTION_DELIMITER}}"
            local requires_value=0
            
            # Check if option requires value
            [[ "$description" == *"${REQUIRES_VALUE_MARKER}"* ]] && requires_value=1

            # Match option
            if [[ "$current_arg" == "-$short_opt" ]] || 
               [[ "$current_arg" == "--$long_opt" ]]; then
                matched=1
                
                if ((requires_value)); then
                    # Handle options requiring values
                    if [[ -z "$2" ]] || [[ "$2" == -* ]]; then
                        log_error "Option $current_arg requires a value"
                        return 1
                    fi
                    args_ref["$long_opt"]="$2"
                    shift 2
                else
                    # Handle boolean options
                    args_ref["$long_opt"]=1
                    shift
                fi
                break
            fi
        done


        # Handle unknown options
        if ((matched == 0)); then
            log_error "Unknown option: $current_arg"
            return 1
        fi
    done

    [[ ${DEBUG:-0} -eq 1 ]] && set +x
    return 0
}

#=======================================================
# Usage Example Template
#=======================================================
# Define Options:
#   COMMAND_OPTIONS=(
#     "h|help:Show this help message"
#     "f|file:Input file path (requires value)"
#     "v|verbose:Enable verbose output"
#   )
#
# Parse Command:
#   parse_options COMMAND_OPTIONS args "$@"
#
# Result Storage:
#   args["help"]="1"      # Flag was set
#   args["file"]="input"  # Value was provided
#
# Example Usage:
#
# # Define options
# readonly COMMAND_OPTIONS=(
#     "h|help:Show this help message"
#     "f|file:Input file path (requires value)"
#     "v|verbose:Enable verbose output"
# )
#
# # Define examples
# readonly COMMAND_EXAMPLES=(
#     "command -h                  # Show help"
#     "command -f input.txt        # Process input file"
#     "command -v -f input.txt     # Process with verbose output"
# )
#
# # Initialize arguments
# declare -A args=(
#     ["file"]=""
#     ["verbose"]=0
# )
#
# # Parse options
# if ! parse_options COMMAND_OPTIONS args "$@"; then
#     generate_usage COMMAND_OPTIONS "command" COMMAND_EXAMPLES
#     exit 1
# fi
###############################################################################
