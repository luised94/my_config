#!/bin/bash

# Guard against multiple inclusion
[[ -n "$_BASH_UTILS_INITIALIZED" ]] && return
readonly _BASH_UTILS_INITIALIZED=1

# Base directory detection
readonly BASH_UTILS_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Logging setup
if [[ -z "$LOG_LEVEL" ]]; then
    export LOG_LEVEL="INFO"
fi

# Configuration files
readonly CONFIG_FILES=(
    "editor_config.sh"
    "output_print_symbols.sh"
    "search_config.sh"
)


# Function files
# Missing file (typo or deletion) should output [ERROR] Required function file not found:
readonly FUNCTION_FILES=(
    "logging_utils.sh"
    "options_parser.sh"  # Must be early in the list
    "option_validation.sh"  # Must be early in the list
    "editor_utils.sh"
    "file_operations.sh"
    "formatted_display_helpers.sh"
    "view_files_in_browser.sh"
    "git_automations_helpers.sh"
    "git_automations.sh"
    "directory_tree.sh"
    "prompt_utils.sh"
    "repo_handler.sh"
    "search_utils.sh"
    "tag_processor.sh"
)


# Initialize logging first
source "${BASH_UTILS_ROOT}/functions/logging_utils.sh"

# Load configurations
for config in "${CONFIG_FILES[@]}"; do
    if [[ -f "${BASH_UTILS_ROOT}/config/${config}" ]]; then
        source "${BASH_UTILS_ROOT}/config/${config}"
    else
        log_error "Required configuration file not found: ${config}"
        return 1
    fi
done

# Load function files
for func in "${FUNCTION_FILES[@]}"; do
    if [[ -f "${BASH_UTILS_ROOT}/functions/${func}" ]]; then
        source "${BASH_UTILS_ROOT}/functions/${func}"
    else
        log_error "Required function file not found: ${func}"
        return 1
    fi
done

# Export common variables
export BASH_UTILS_CONFIG_DIR="${BASH_UTILS_ROOT}/config"
export BASH_UTILS_FUNCTIONS_DIR="${BASH_UTILS_ROOT}/functions"
export BASH_UTILS_SCRIPTS_DIR="${BASH_UTILS_ROOT}/scripts"

log_info "Bash utilities initialized successfully"
