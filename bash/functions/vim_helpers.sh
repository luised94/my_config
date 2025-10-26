
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

vim_all() {

}
