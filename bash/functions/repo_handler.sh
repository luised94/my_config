#!/bin/bash

source "../config/repository_config.sh"

function find_git_root() {
    local start_dir="${1:-.}"
    
    log_info "Finding Git repository root"
    
    if ! command -v git >/dev/null 2>&1; then
        log_warning "Git not available, using current directory"
        echo "$start_dir"
        return 0
    }
    
    local root_dir
    if ! root_dir=$(git -C "$start_dir" rev-parse --show-toplevel 2>/dev/null); then
        log_warning "Not in a Git repository, using current directory"
        echo "$start_dir"
        return 0
    }
    
    echo "$root_dir"
}

function find_readme() {
    local repo_root="$1"
    local readme_name="${REPO_CONFIG[README_NAME]}"
    
    log_info "Searching for README in: $repo_root"
    
    local readme_path="$repo_root/$readme_name"
    if [ ! -f "$readme_path" ]; then
        log_error "README not found: $readme_path"
        return 1
    }
    
    echo "$readme_path"
}

function resolve_path() {
    local path="$1"
    local repo_root="$2"
    
    # Convert relative to absolute paths
    if [[ "$path" != /* ]]; then
        path="$repo_root/$path"
    fi
    
    # Normalize path
    echo "$(cd "$(dirname "$path")" && pwd)/$(basename "$path")"
}
