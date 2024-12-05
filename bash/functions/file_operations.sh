#!/bin/bash

[[ -z "$_BASH_UTILS_INITIALIZED" ]] && source "${BASH_SOURCE%/*}/../init.sh"

build_exclude_args() {
    local -n dirs_ref=$1
    local -n files_ref=$2
    local exclude_args=()
    exclude_args=(\()

    local first=true
    
    for dir in "${dirs_ref[@]}"; do
        if [[ "$first" == true ]]; then
            exclude_args+=(-path "*/${dir}/*")
            first=false
        else
            exclude_args+=(-o -path "*/${dir}/*")
        fi
    done
    
    # Add file exclusions
    for file in "${files_ref[@]}"; do
        exclude_args+=(-o -name "${file}")
    done
    
    # Close group and add prune-or construct
    exclude_args+=(\) -prune -o)
    
    echo "${exclude_args[@]}"
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
                find "${args["directory"]}" -type f "${exclude_args[@]}" -printf '%T@ %p\n' | \
                sort -rn | \
                cut -d' ' -f2- | \
                tr -d '\r'
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

aggregate_repository() {
    local output_file="repository_aggregate.md"
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    local verbose=0
    local quiet=0
    local max_depth=""
    
    # Show usage if no arguments or help flag
    if [[ $# -eq 0 || "$1" == "-h" || "$1" == "--help" ]]; then
        echo "${AGGREGATE_REPOSITORY_USAGE}"
        return 0
    fi
    
    # Initialize arrays for exclusions
    local exclude_dirs=("${DEFAULT_SEARCH_EXCLUDE_DIRS[@]}")
    local exclude_files=("${DEFAULT_SEARCH_EXCLUDE_FILES[@]}")

    # Parse command line options
    while [[ $# -gt 0 ]]; do
        case "$1" in
            -d|--max-depth)
                max_depth="-maxdepth $2"
                shift 2
                ;;
            -e|--exclude-dir)
                exclude_dirs+=("$2")
                shift 2
                ;;
            -f|--exclude-file)
                exclude_files+=("$2")
                shift 2
                ;;
            -v|--verbose)
                verbose=1
                shift
                ;;
            -q|--quiet)
                quiet=1
                shift
                ;;
            *)
                break
                ;;
        esac
    done

    # Construct find command exclusions
    local dir_excludes=""
    for dir in "${exclude_dirs[@]}"; do
        dir_excludes="$dir_excludes -not -path '*/$dir/*'"
    done

    local file_excludes=""
    for pattern in "${exclude_files[@]}"; do
        file_excludes="$file_excludes -not -name '$pattern'"
    done

    # Create aggregate file with header
    {
        echo "# Repository Aggregation"
        echo "Generated: $timestamp"
        echo "---"
        echo
    } > "$output_file"

    # Find and process files
    local find_command="find . $max_depth -type f $dir_excludes $file_excludes"
    local file_count=0
    local total_lines=0

    while IFS= read -r file; do
        [[ "$file" == "./$output_file" ]] && continue

        [[ $verbose -eq 1 ]] && echo "Processing: $file"

        {
            echo "## File: $file"
            echo "\`\`\`${file##*.}"
            cat "$file"
            echo "\`\`\`"
            echo
        } >> "$output_file"

        ((file_count++))
        [[ $verbose -eq 1 ]] && total_lines+=$(wc -l < "$file")
    done < <(eval "$find_command" | sort)

    [[ $quiet -eq 0 ]] && {
        echo "Repository aggregation complete:"
        echo "- Files processed: $file_count"
        [[ $verbose -eq 1 ]] && echo "- Total lines: $total_lines"
        echo "- Output: $output_file"
    }
}

# Usage example:
# aggregate_repository -v -d 3 -e "tests" -f "*.csv" "Initial repository aggregation"
