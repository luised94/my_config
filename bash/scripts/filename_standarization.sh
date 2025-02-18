#!/bin/bash
set -eo pipefail
shopt -s nullglob nocasematch

# Configuration
DEBUG="${DEBUG:-false}"
DRY_RUN=false
declare -a targets=()

show_help() {
    cat <<EOF
Filename standardization script

Usage: ${0##*/} [OPTIONS] [DIRECTORIES...]

Options:
  -d, --debug       Enable debug output
  -n, --dry-run     Show changes without modifying files
  -h, --help        Display this help message

Features:
  - Converts camelCase to snake_case
  - Handles date prefixes (YYYYMMDD_)
  - Preserves file extensions
  - Collision-resistant renaming
  - Space normalization in filenames

Default search directories: current directory
EOF
}

log() {
    printf "[%s] %s\n" "$(date +%H:%M:%S)" "$*" >&2
}

debug() {
    if [[ "$DEBUG" == true ]]; then
        log "DEBUG: $*"
    fi
}

find_target_files() {
    local dir="${1:-.}"
    debug "Scanning directory: $dir"
    
    find "$dir" -type f \( \
        -regex '.*[A-Z].*' \
        -o -name '*[[:space:]]*' \
    \) ! -name '.*'
}

convert_to_snake() {
    local input="$1"
    # Multi-stage conversion for complex cases
    sed -E -e 's/([a-z0-9])([A-Z])/\1_\2/g' \
        -e 's/([A-Z]+)([A-Z][a-z])/\1_\2/g' \
        -e 's/[[:space:]]+/_/g' \
        -e 's/\._/_/g' \
        -e 's/_+/_/g' \
        -e 's/(^_|_$)//g' <<<"$input" | tr '[:upper:]' '[:lower:]'
}

process_filename() {
    local original="$1"
    local dir="$(dirname "$original")"
    local filename="$(basename -- "$original")"
    local extension="${filename##*.}"
    
    # Preserve existing date prefix
    if [[ "$filename" =~ ^([0-9]{8}_)(.*) ]]; then
        local date_part="${BASH_REMATCH[1]}"
        local base_name="${BASH_REMATCH[2]}"
    else
        local date_part=""
        local base_name="$filename"
    fi

    # Split name and extension
    [[ "$base_name" == *.* ]] && extension="${base_name##*.}" || extension=""
    local main_name="${base_name%.*}"

    debug "Processing: $original"
    debug "Components: [date:$date_part] [name:$main_name] [ext:$extension]"

    # Convert main name and extension
    local new_main=$(convert_to_snake "$main_name")
    local new_ext=$(convert_to_snake "$extension")
    
    # Reconstruct filename
    local new_name="${date_part}${new_main}${extension:+.$new_ext}"
    debug "Initial conversion: $new_name"

    # Handle duplicates
    local counter=1
    while [[ -e "$dir/$new_name" && "$dir/$new_name" != "$original" ]]; do
        new_name="${date_part}${new_main}_$counter${extension:+.$new_ext}"
        debug "Duplicate detected, trying: $new_name"
        ((counter++))
    done

    printf "%s|%s\n" "$original" "$new_name"
}

display_changes() {
    printf "\n%-60s  %s\n" "Original Path" "Proposed New Path"
    printf "%s\n" "--------------------------------------------------------------------------------"
    while IFS='|' read -r orig new; do
        [[ "$orig" == "$new" ]] && continue  # Skip unchanged files
        printf "%-60s  %s\n" "$orig" "$new"
    done
}

main() {
    # Parse arguments
    while (($# > 0)); do
        case "$1" in
            -n|--dry-run) DRY_RUN=true; shift ;;
            -d|--debug) DEBUG=true; shift ;;
            -h|--help) show_help; exit 0 ;;
            --) shift; targets+=("$@"); break ;;
            *) targets+=("$1"); shift ;;
        esac
    done

    [[ ${#targets[@]} -eq 0 ]] && targets=(.)

    # Find target files
    local found_files=()
    for dir in "${targets[@]}"; do
        while IFS= read -r -d $'\0' file; do
            found_files+=("$file")
        done < <(find_target_files "$dir" -print0)
    done

    ((${#found_files[@]} == 0)) && {
        log "No target files found"
        exit 0
    }

    # Process files
    declare -a changes=()
    for file in "${found_files[@]}"; do
        changes+=("$(process_filename "$file")")
    done

    # Display or execute changes
    if "$DRY_RUN"; then
        printf "%s\n" "${changes[@]}" | display_changes
        log "Dry run complete - ${#changes[@]} files would be processed"
    else
        local count=0
        for change in "${changes[@]}"; do
            IFS='|' read -r orig new <<<"$change"
            [[ "$orig" == "$new" ]] && continue
            mv --no-clobber -- "$orig" "$new"
            ((count++))
            debug "Renamed: $orig  $new"
        done
        log "Operation complete - $count files processed"
    fi
}

# --- Execution Trap for Clean Debugging ---
trap 'if [[ "$?" -ne 0 ]]; then log "Error occurred in $LINENO"; fi' ERR

main "$@"
