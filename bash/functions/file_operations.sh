#!/bin/bash

# Constants for option parsing
REQUIRES_VALUE_MARKER="(requires value)"
OPTION_DELIMITER=":"
OPTION_SEPARATOR="|"
# Editor preferences
DEFAULT_EDITORS=(
    "nvim"
    "vim"
)
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

#[[ -z "$_BASH_UTILS_INITIALIZED" ]] && source "${BASH_SOURCE%/*}/../init.sh"


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
# Editor options
EDITOR_OPTIONS=(
    "h|help:Show this help message"
    "e|editor:Specify editor to use (requires value)"
    "d|directory:Specify search directory (requires value)"
    "f|force:Skip confirmation for large file counts"
    "l|limit:Set file count warning threshold (requires value)"
    "m|mode:Specify sort mode: modified, conflicts, search (requires value)"
    "p|pattern:Search pattern for search mode (requires value)"
)
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

EDITOR_USAGE_EXAMPLES=(
    "vim_all                                  # Open files in current directory sorted by modification time"
    "vim_all -d ./src                         # Open files from specific directory"
    "vim_all -e nvim                          # Use specific editor (nvim)"
    "vim_all -m conflicts                     # Open files with Git conflicts"
    "vim_all -m modified                      # Open Git modified/staged files"
    "vim_all -m search -p 'TODO'              # Open files containing 'TODO'"
    "vim_all -f -m modified                   # Force open modified files (skip confirmation)"
    "vim_all -l 50                            # Set custom file limit warning threshold"
)

# Default settings
DEFAULT_FILE_WARNING_THRESHOLD=100

# Default exclusion patterns
DEFAULT_SEARCH_EXCLUDE_DIRS=(
    ".git"
    "node_modules"
    "build"
    "dist"
    "renv"
    ".venv"
)

DEFAULT_SEARCH_EXCLUDE_FILES=(
    "*.log"
    "*repository_aggregate.md"
    "*.tmp"
    "*.bak"
    "*.swp"
    "*.gitignore"
    "*.Rprofile"
    "*renv.lock"
)

# Search options
SEARCH_OPTIONS=(
    "h|help:Show this help message"
    "e|exclude-dir:Additional directory to exclude (requires value)"
    "f|exclude-file:Additional file pattern to exclude (requires value)"
    "v|verbose:Enable verbose output"
    "q|quiet:Suppress all output except final counts"
    "d|max-depth:Maximum directory depth to search (requires value)"
)

# Search defaults
DEFAULT_SEARCH_VERBOSE=0
DEFAULT_SEARCH_QUIET=0

# Advanced search configuration
declare -A SEARCH_CONFIG=(
    ["MAX_RESULTS"]="1000"
    ["CONTEXT_LINES"]="0"
    ["COLORED_OUTPUT"]="true"
)

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

build_exclude_args() {
    local -n dirs_ref=$1
    local -n files_ref=$2
    local expressions=()
    
    # Add directory exclusions
    local first=true
    for dir in "${dirs_ref[@]}"; do
        if [[ "$first" == true ]]; then
            expressions+=("-path" "\"*/${dir}/*\"")
            first=false
        else
            expressions+=("-o" "-path" "\"*/${dir}/*\"")
        fi
    done
    
    # Add file exclusions
    for file in "${files_ref[@]}"; do
        expressions+=("-o" "-name" "\"${file}\"")
    done
    
    printf '%s\n' "${expressions[@]}"
}



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

# Terrible function nesting... sigh. My bad but also early days of vibe coding
vim_all() {
    local -A args=(
        ["directory"]="."
        ["limit"]="$DEFAULT_FILE_WARNING_THRESHOLD"
        ["force"]=0
        ["mode"]="time"
        ["pattern"]=""
    )

    if ! parse_options EDITOR_OPTIONS args "$@"; then
        generate_usage EDITOR_OPTIONS "vim_all" EDITOR_USAGE_EXAMPLES
        return 1
    fi

    if [[ ${args["help"]} == 1 ]]; then
        generate_usage EDITOR_OPTIONS "vim_all" EDITOR_USAGE_EXAMPLES
        return 0
    fi

    # Detect editor
    local editor
    if [[ -n "${args["editor"]}" ]]; then
        editor="${args["editor"]}"
        if ! command -v "$editor" >/dev/null 2>&1; then
            log_error "Specified editor '$editor' not found"
            return 1
        fi
    else
        editor=$(detect_editor DEFAULT_EDITORS) || return 1
    fi

    # Build exclude arguments
    local exclude_args=($(build_exclude_args DEFAULT_SEARCH_EXCLUDE_DIRS DEFAULT_SEARCH_EXCLUDE_FILES))

    # Debug output
    #echo "Directory: ${args["directory"]}"
    #echo "Exclude args: ${exclude_args[@]}"
    
    # Construct and echo the full find command
    #find_cmd="find \"${args["directory"]}\" ${exclude_args[@]} -type f -printf '%T@ %p\n'"
    #echo "Find command: $find_cmd"

    # Collect files
    local files=()

    case "${args["mode"]}" in
        conflicts)
            if ! mapfile -t files < <(git diff --name-only --diff-filter=U); then
                log_error "Failed to collect conflicted files"
                return 1
            fi
            ;;
        modified)
            if ! mapfile -t files < <(git status --porcelain | sed 's/^...//'); then
                log_error "Failed to collect modified files"
                return 1
            fi
            ;;
        search)
            if [[ -z "${args["pattern"]}" ]]; then
                log_error "Search pattern required for search mode"
                return 1
            fi
            if ! mapfile -t files < <(git grep -l "${args["pattern"]}"); then
                log_error "Failed to search files"
                return 1
            fi
            ;;
        time|*)
            if ! mapfile -t files < <(
            set -x
            eval "find \"${args["directory"]}\" \( ${exclude_args[@]} \) -prune -o -type f -printf '%T@ %p\n'" 2>/dev/null |
            sort -rn | \
            cut -d' ' -f2- | \
            tr -d '\r'
            set +x
            ); then
              log_error "Failed to collect files"
              return 1
            fi
            ;;
    esac

    if [ ${#files[@]} -eq 0 ]; then
        log_warning "No files found to edit."
        return 1
    fi

    if [ ${#files[@]} -gt "${args["limit"]}" ] && [ ${args["force"]} -ne 1 ]; then
        log_warning "Found ${#files[@]} files. Are you sure you want to open all of them? (y/N)"
        read -r confirm
        if [[ $confirm != [yY] ]]; then
            log_info "Operation cancelled."
            return 0
        fi
    fi

    log_info "Opening ${#files[@]} files in $editor"
    eval "$editor" "${files[@]}"
}
