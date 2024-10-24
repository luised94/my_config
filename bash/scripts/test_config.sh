#!/bin/bash

[[ -z "$_BASH_UTILS_INITIALIZED" ]] && source "${BASH_SOURCE%/*}/../init.sh"

# Test initialization
test_initialization() {
    local errors=0

    # Test configuration loading
    for var in DEFAULT_EDITORS DEFAULT_SEARCH_EXCLUDE_DIRS; do
        if [[ -z "${!var}" ]]; then
            log_error "Configuration variable $var not set"
            ((errors++))
        fi
    done

    # Test function availability
    for func in log_info detect_editor count_string; do
        if ! declare -F "$func" >/dev/null; then
            log_error "Function $func not available"
            ((errors++))
        fi
    done

    # Test path variables
    for path_var in BASH_UTILS_CONFIG_DIR BASH_UTILS_FUNCTIONS_DIR BASH_UTILS_SCRIPTS_DIR; do
        if [[ ! -d "${!path_var}" ]]; then
            log_error "Path ${!path_var} does not exist"
            ((errors++))
        fi
    done

    return $errors
}

# Run tests
test_initialization
