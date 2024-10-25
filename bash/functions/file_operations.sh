#!/bin/bash

[[ -z "$_BASH_UTILS_INITIALIZED" ]] && source "${BASH_SOURCE%/*}/../init.sh"

build_exclude_args() {
    local -n dirs_ref=$1
    local -n files_ref=$2
    local exclude_args=()
    
    for dir in "${dirs_ref[@]}"; do
        exclude_args+=(-not -path "*/${dir}/*")
    done
    
    for file in "${files_ref[@]}"; do
        exclude_args+=(-not -name "${file}")
    done
    
    echo "${exclude_args[@]}"
}

vim_all() {
    local -A args=(
        ["directory"]="."
        ["limit"]="$DEFAULT_FILE_WARNING_THRESHOLD"
        ["force"]=0
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
    while IFS= read -r -d $'\0' file; do
        files+=("$file")
    done < <(find "${args["directory"]}" -type f "${exclude_args[@]}" -print0)
    
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

#!/usr/bin/env bash

# Function to aggregate repository contents
function aggregate_repository() {
    local output_file="repository_aggregate.md"
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    local verbose=0
    local quiet=0
    local max_depth=""
    
    # Initialize arrays for exclusions
    local exclude_dirs=("${DEFAULT_SEARCH_EXCLUDE_DIRS[@]}")
    local exclude_files=("${DEFAULT_SEARCH_EXCLUDE_FILES[@]}")

    # Parse command line options
    while getopts "he:f:vqd:" opt; do
        case ${opt} in
            h)
                show_help
                return 0
                ;;
            e)
                exclude_dirs+=("$OPTARG")
                ;;
            f)
                exclude_files+=("$OPTARG")
                ;;
            v)
                verbose=1
                ;;
            q)
                quiet=1
                ;;
            d)
                max_depth="-maxdepth $OPTARG"
                ;;
            \?)
                echo "Invalid option: -$OPTARG" >&2
                return 1
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

    # Create header for aggregate file
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
        # Skip the output file itself
        [[ "$file" == "./$output_file" ]] && continue

        if [[ $verbose -eq 1 ]]; then
            echo "Processing: $file"
        fi

        # Add file header
        {
            echo "## File: $file"
            echo "\`\`\`$(get_file_extension "$file")"
            cat "$file"
            echo "\`\`\`"
            echo
        } >> "$output_file"

        ((file_count++))
        if [[ $verbose -eq 1 ]]; then
            local lines=$(wc -l < "$file")
            ((total_lines+=lines))
        fi
    done < <(eval "$find_command" | sort)

    # Print summary unless quiet mode is enabled
    if [[ $quiet -eq 0 ]]; then
        echo "Repository aggregation complete:"
        echo "- Files processed: $file_count"
        [[ $verbose -eq 1 ]] && echo "- Total lines: $total_lines"
        echo "- Output: $output_file"
    fi
}

# Helper function to get file extension for markdown code blocks
function get_file_extension() {
    local file="$1"
    local ext="${file##*.}"
    case "$ext" in
        py) echo "python" ;;
        js) echo "javascript" ;;
        sh) echo "bash" ;;
        R|r) echo "r" ;;
        md) echo "markdown" ;;
        *) echo "$ext" ;;
    esac
}

# Help message function
function show_help() {
    echo "Usage: aggregate_repository [options]"
    echo
    echo "Options:"
    for option in "${SEARCH_OPTIONS[@]}"; do
        IFS=':' read -r opt desc <<< "$option"
        printf "  -%s: %s\n" "${opt/|/, -}" "$desc"
    done
}

# Example usage:
# aggregate_repository -v -d 3 -e "tests" -f "*.csv"
