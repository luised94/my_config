#!/bin/bash

[[ -z "$_BASH_UTILS_INITIALIZED" ]] && source "${BASH_SOURCE%/*}/../init.sh"

# Test initialization
test_initialization() {
    local errors=0

    log_info "Starting configuration tests..."

    # Test configuration loading
    local required_configs=(
        "DEFAULT_EDITORS"
        "DEFAULT_SEARCH_EXCLUDE_DIRS"
        "BASIC_ALIASES"
        "GIT_ALIASES"
        "ENV_VARS"
    )

    for var in "${required_configs[@]}"; do
        if [[ -z "${!var}" ]]; then
            log_error "Configuration variable $var not set"
            ((errors++))
        else
            log_info "û Configuration $var loaded"
        fi
    done

    # Test function availability
    local required_functions=(
        "log_info"
        "log_error"
        "detect_editor"
        "count_string"
        "vim_all"
        "setup_prompt"
        "setup_aliases"
        "setup_environment"
    )

    for func in "${required_functions[@]}"; do
        if ! declare -F "$func" >/dev/null; then
            log_error "Function $func not available"
            ((errors++))
        else
            log_info "û Function $func available"
        fi
    done

    # Test path variables
    local required_paths=(
        "BASH_UTILS_CONFIG_DIR"
        "BASH_UTILS_FUNCTIONS_DIR"
        "BASH_UTILS_SCRIPTS_DIR"
    )

    for path_var in "${required_paths[@]}"; do
        if [[ ! -d "${!path_var}" ]]; then
            log_error "Path ${!path_var} does not exist"
            ((errors++))
        else
            log_info "û Path ${!path_var} exists"
        fi
    done

    # Test basic functionality
    if command -v nvim >/dev/null 2>&1 || command -v vim >/dev/null 2>&1; then
        log_info "û Editor available"
    else
        log_error "No suitable editor found"
        ((errors++))
    fi

    if ((errors > 0)); then
        log_error "Tests completed with $errors errors"
    else
        log_info "All tests passed successfully"
    fi

    return $errors
}

# Test specific functionality
test_search_functionality() {
    log_info "Testing search functionality..."
    
    # Create temporary test directory
    local test_dir=$(mktemp -d)
    trap 'rm -rf "$test_dir"' EXIT

    # Create test files
    echo "test content" > "$test_dir/test1.txt"
    echo "different content" > "$test_dir/test2.txt"
    mkdir "$test_dir/node_modules"
    echo "should be excluded" > "$test_dir/node_modules/excluded.txt"

    # Test count_string
    local result=$(count_string -q "test" "$test_dir")
    if [[ "$result" -eq 1 ]]; then
        log_info "û Search functionality working"
        return 0
    else
        log_error "Search functionality failed"
        return 1
    fi
}

# Test editor functionality
test_editor_functionality() {
    log_info "Testing editor functionality..."
    
    # Test editor detection
    local editor=$(detect_editor DEFAULT_EDITORS)
    if [[ -n "$editor" ]]; then
        log_info "û Editor detection working"
        return 0
    else
        log_error "Editor detection failed"
        return 1
    fi
}

# Main test runner
main() {
    local exit_code=0

    # Run all tests
    test_initialization
    exit_code=$((exit_code + $?))

    test_search_functionality
    exit_code=$((exit_code + $?))

    test_editor_functionality
    exit_code=$((exit_code + $?))

    if ((exit_code == 0)); then
        log_info "All tests completed successfully"
    else
        log_error "Tests completed with $exit_code errors"
    fi

    return $exit_code
}
test_tree_functionality() {
    log_info "Testing tree functionality..."
    
    # Test basic tree command
    if ! command -v tree >/dev/null 2>&1; then
        log_error "Tree command not available"
        return 1
    fi

    # Create test directory structure
    local test_dir=$(mktemp -d)
    mkdir -p "$test_dir/dir1/subdir1"
    mkdir -p "$test_dir/dir2"
    touch "$test_dir/dir1/file1.txt"
    touch "$test_dir/dir2/file2.txt"

    # Test ctree basic functionality
    if ! ctree -d 1 "$test_dir" >/dev/null 2>&1; then
        log_error "Basic ctree functionality failed"
        rm -rf "$test_dir"
        return 1
    fi

    # Test summary mode
    if ! ctree -s "$test_dir" | grep -q "Directories:"; then
        log_error "Summary mode failed"
        rm -rf "$test_dir"
        return 1
    fi

    rm -rf "$test_dir"
    log_info "Tree functionality tests passed"
    return 0
}
# Run tests if script is executed directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
