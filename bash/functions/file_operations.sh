#!/bin/bash

[[ -z "$_BASH_UTILS_INITIALIZED" ]] && source "${BASH_SOURCE%/*}/../init.sh"

# Editor preferences
DEFAULT_EDITORS=(
    "nvim"
    "vim"
)

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
        #set -x
        eval "find \"${args["directory"]}\" \( ${exclude_args[@]} \) -prune -o -type f -printf '%T@ %p\n'" 2>/dev/null |
        sort -rn | \
        cut -d' ' -f2- | \
        tr -d '\r'
        #set +x
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
