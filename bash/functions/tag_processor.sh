#!/bin/bash

function extract_tags() {
    local readme_file="$1"
    local tag_section="${REPO_CONFIG[TAG_SECTION]}"
    
    log_info "Extracting tags from README"
    
    sed -n "/${tag_section}/,/^#/p" "$readme_file" | 
        grep -v "#" | 
        grep ":" | 
        sed '/^[[:space:]]*$/d' | 
        sed 's/:.*//' | 
        tr '\n' ' '
}

function validate_tag() {
    local tag="$1"
    local valid_tags="$2"
    
    if [[ ! " ${valid_tags} " =~ [[:space:]]${tag}[[:space:]] ]]; then
        log_warning "Tag '$tag' not found in README"
        log_info "Valid tags: $valid_tags"
        return 1
    }
    
    return 0
}

function build_find_command() {
    local directory="$1"
    local -a extensions=("${@:2}")
    
    local cmd="find \"$directory\" -type f \\( "
    local first=true
    
    for ext in "${extensions[@]}"; do
        if [ "$first" = true ]; then
            cmd+="-name \"*.${ext}\""
            first=false
        else
            cmd+=" -o -name \"*.${ext}\""
        fi
    done
    
    cmd+=" \\)"
    echo "$cmd"
}

function search_tags() {
    local directory="$1"
    local tag="$2"
    local find_cmd="$3"
    
    log_info "Searching for #$tag in $directory"
    
    local results
    if ! results=$(eval "$find_cmd -print0" | 
                  xargs -0 grep -Hn "^#$tag" 2>/dev/null); then
        log_warning "No instances of #$tag found"
        return 1
    }
    
    echo "$results"
}
