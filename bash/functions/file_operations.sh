#!/bin/bash

source "${BASH_SOURCE%/*}/../utils/logging_utils.sh"

build_exclude_args() {
    local -n dirs_ref=$1
    local -n files_ref=$2
    local exclude_args=()
    
    for dir in "${dirs_ref[@]}"; do
        exclude_args+=(-not -path "*/$dir/*")
    done
    
    for file in "${files_ref[@]}"; do
        exclude_args+=(-not -name "$file")
    done
    
    echo "${exclude_args[@]}"
}

collect_files() {
    local search_dir="$1"
    shift
    local -a exclude_args=("$@")
    local files=()
    
    while IFS= read -r -d $'\0' file; do
        files+=("$file")
    done < <(find "$search_dir" -type f "${exclude_args[@]}" -print0)
    
    echo "${files[@]}"
}
