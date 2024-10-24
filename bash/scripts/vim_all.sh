#!/bin/bash

source "${BASH_SOURCE%/*}/../config/editor_config.sh"
source "${BASH_SOURCE%/*}/../functions/editor_utils.sh"
source "${BASH_SOURCE%/*}/../functions/file_operations.sh"
source "${BASH_SOURCE%/*}/../functions/options_parser.sh"
source "${BASH_SOURCE%/*}/../utils/logging_utils.sh"

vim_all() {
    local -A args=(
        ["directory"]="."
        ["limit"]="$DEFAULT_FILE_WARNING_THRESHOLD"
        ["force"]=0
    )

    # Parse options
    if ! parse_options EDITOR_OPTIONS args "$@"; then
        generate_usage EDITOR_OPTIONS "vim_all"
        return 1
    fi

    # Show help if requested
    if [[ ${args["help"]} == 1 ]]; then
        generate_usage EDITOR_OPTIONS "vim_all"
        return 0
    }

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
    local exclude_args=($(build_exclude_args DEFAULT_EXCLUDE_DIRS DEFAULT_EXCLUDE_FILES))
    
    # Collect files
    local files=($(collect_files "${args["directory"]}" "${exclude_args[@]}"))
    
    # Check if files were found
    if [ ${#files[@]} -eq 0 ]; then
        log_warning "No files found to edit."
        return 1
    fi

    # Confirm large file counts
    if [ ${#files[@]} -gt "${args["limit"]}" ] && [ ${args["force"]} -ne 1 ]; then
        log_warning "Found ${#files[@]} files. Are you sure you want to open all of them? (y/N)"
        read -r confirm
        if [[ $confirm != [yY] ]]; then
            log_info "Operation cancelled."
            return 0
        fi
    }

    log_info "Opening ${#files[@]} files in $editor"
    eval "$editor" "${files[@]}"
}
