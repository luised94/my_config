#!/bin/bash

# Function: vim_all
# Purpose: Open files in neovim after excluding common dirs and files.
# Parameters: Option - Search directory, if none provided current working directory '.' is used as default.
# Return: Open all files after excluding dirs and files with particulars in neovim.
vim_all() {
    local editor
    if command -v nvim >/dev/null 2>&1; then
        editor="nvim"
    elif command -v vim >/dev/null 2>&1; then
        editor="vim"
    else
        echo "Error: Neither Neovim nor Vim is installed on this system."
        return 1
    fi

    local exclude_dirs=(".git" "node_modules" "build" "dist" "renv" ".venv")
    local exclude_files=("*.log" "*.tmp" "*.bak" "*.swp" "*.gitignore" "*renv.lock" "*.Rprofile" )
    local search_dir="${1:-.}"

    local exclude_args=()
    for dir in "${exclude_dirs[@]}"; do
        exclude_args+=(-not -path "*/$dir/*")
    done
    for file in "${exclude_files[@]}"; do
        exclude_args+=(-not -name "$file")
    done

    local files=()
    while IFS= read -r -d $'\0' file; do
        files+=("$file")
    done < <(find "$search_dir" -type f "${exclude_args[@]}" -print0)

    if [ ${#files[@]} -eq 0 ]; then
        echo "No files found to edit."
        return 1
    fi

    if [ ${#files[@]} -gt 100 ]; then
        read -p "Found ${#files[@]} files. Are you sure you want to open all of them? (y/N) " confirm
        if [[ $confirm != [yY] ]]; then
            echo "Operation cancelled."
            return 0
        fi
    fi

    eval "$editor" "${files[@]}"
}


count_string() {
    # Usage function
    usage() {
        cat << EOF
Usage: count_string [OPTIONS] <search_string> [directory]
Search for string occurrences in files with detailed reporting.

Options:
    -h, --help                 Show this help message
    -e, --exclude-dir DIR      Additional directory to exclude (can be used multiple times)
    -f, --exclude-file FILE    Additional file pattern to exclude (can be used multiple times)
    -v, --verbose             Enable verbose output
    -q, --quiet               Suppress all output except final counts
    --no-default-excludes     Don't use default exclusion patterns
    --max-depth N             Maximum directory depth to search

Examples:
    count_string "TODO" ./src
    count_string -e "tests" -e "docs" "FIXME" .
    count_string -q "deprecated" ./project
EOF
    }

    # Default configuration
    local default_exclude_dirs=(".git" "node_modules" "build" "dist" "renv" ".venv")
    local default_exclude_files=("*.md" "*.txt" "*init.sh" "*renv.lock" "*.log" "*.tmp" "*.bak" "*.swp" "*.gitignore" "*.Rprofile")
    local additional_exclude_dirs=()
    local additional_exclude_files=()
    local verbose=0
    local quiet=0
    local use_default_excludes=1
    local max_depth=""
    local search_string=""
    local search_dir="."

    # Parse options
    while [[ $# -gt 0 ]]; do
        case $1 in
            -h|--help)
                usage
                return 0
                ;;
            -e|--exclude-dir)
                if [[ -z "$2" ]]; then
                    echo "Error: --exclude-dir requires a directory argument" >&2
                    return 1
                fi
                additional_exclude_dirs+=("$2")
                shift 2
                ;;
            -f|--exclude-file)
                if [[ -z "$2" ]]; then
                    echo "Error: --exclude-file requires a file pattern argument" >&2
                    return 1
                fi
                additional_exclude_files+=("$2")
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
            --no-default-excludes)
                use_default_excludes=0
                shift
                ;;
            --max-depth)
                if [[ -z "$2" ]] || ! [[ "$2" =~ ^[0-9]+$ ]]; then
                    echo "Error: --max-depth requires a numeric argument" >&2
                    return 1
                fi
                max_depth="-maxdepth $2"
                shift 2
                ;;
            -*)
                echo "Error: Unknown option: $1" >&2
                usage
                return 1
                ;;
            *)
                if [[ -z "$search_string" ]]; then
                    search_string="$1"
                else
                    search_dir="$1"
                fi
                shift
                ;;
        esac
    done

    # Validate required arguments
    if [[ -z "$search_string" ]]; then
        echo "Error: Search string is required" >&2
        usage
        return 1
    fi

    # Validate directory
    if [[ ! -d "$search_dir" ]]; then
        echo "Error: Directory '$search_dir' does not exist" >&2
        return 1
    fi

    # Build exclude arguments
    local exclude_args=()
    
    if ((use_default_excludes)); then
        for dir in "${default_exclude_dirs[@]}"; do
            exclude_args+=(-not -path "*/${dir}/*")
        done
        for file in "${default_exclude_files[@]}"; do
            exclude_args+=(-not -name "${file}")
        done
    fi

    for dir in "${additional_exclude_dirs[@]}"; do
        exclude_args+=(-not -path "*/${dir}/*")
    done
    for file in "${additional_exclude_files[@]}"; do
        exclude_args+=(-not -name "${file}")
    done

    # Temporary files for results
    local tmp_dir=$(mktemp -d)
    local files_with="$tmp_dir/with.txt"
    local files_without="$tmp_dir/without.txt"
    trap 'rm -rf "$tmp_dir"' EXIT

    # Execute find command with proper error handling
    if ((verbose)); then
        echo "Executing find command..."
        echo "find $search_dir $max_depth -type f ${exclude_args[@]}"
    fi

    # Find and categorize files
    find "$search_dir" $max_depth -type f "${exclude_args[@]}" -print0 2>/dev/null | \
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
    if ((! quiet)); then
        echo "Searching for: '$search_string' in $search_dir"
        echo "----------------------------------------"
        
        echo -e "\nFiles containing the string:"
        if [[ -s "$files_with" ]]; then
            sed 's/^/  /' "$files_with"
        else
            echo "  None found"
        fi
        
        echo -e "\nFiles missing the string:"
        if [[ -s "$files_without" ]]; then
            sed 's/^/  /' "$files_without"
        else
            echo "  None found"
        fi
        
        echo -e "\nSummary:"
        echo "  Files containing string: $count_with"
        echo "  Files missing string: $count_without"
        echo "  Total files checked: $total"
    else
        echo "$count_with"
    fi

    return 0
}
