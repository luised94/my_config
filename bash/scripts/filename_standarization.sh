#!/bin/bash
set -eo pipefail
shopt -s nullglob nocasematch

# Helper functions (kept for core utilities)
log() {
    printf "[%s] %s\n" "$(date +%H:%M:%S)" "$*" >&2
}

debug() {
    [[ "$DEBUG" == true ]] && log "DEBUG: $*"
}

show_help() {
    cat <<EOF
Filename Standardization Script

Usage: ${0##*/} [OPTIONS] [DIRECTORIES...]

Options:
  --apply          Execute changes (disable dry-run)
  -d, --debug      Show detailed processing info
  -h, --help       Display this message

Default behavior: dry-run mode showing proposed changes
EOF
}

# Argument parsing logic moved inline
DEBUG="${DEBUG:-true}"
DRY_RUN=true
declare -a TARGET_DIRS=()

while (($# > 0)); do
    case "$1" in
        --apply) DRY_RUN=false ;;
        -d|--no-debug) DEBUG=false ;;
        -h|--help) show_help; exit 0 ;;
        --) shift; TARGET_DIRS+=("$@"); break ;;
        *) TARGET_DIRS+=("$1") ;;
    esac
    shift
done
[[ ${#TARGET_DIRS[@]} -eq 0 ]] && TARGET_DIRS=(".")

debug "Target directories: ${TARGET_DIRS[*]}"
debug "Dry run mode: $DRY_RUN"

# Main processing flow
found_files=()
for dir in "${TARGET_DIRS[@]}"; do
    debug "Scanning directory: $dir"
    while IFS= read -r -d $'\0' file; do
        found_files+=("$file")
    done < <(find "$dir" -type f \( \
        -regex '.*[A-Z].*' -o \
        -name '*[[:space:]]*' \
    \) ! -name '.*' -print0)
done

debug "Found ${#found_files[@]} candidate files"
[[ ${#found_files[@]} -eq 0 ]] && { log "No target files found"; exit 0; }

# Process files and collect changes
changes=()
for orig_path in "${found_files[@]}"; do
    debug "Processing file: '$orig_path'"
    
    dir_name=$(dirname "$orig_path")
    file_name=$(basename -- "$orig_path")
    extension="${file_name##*.}"
    [[ "$file_name" == "$extension" ]] && extension=""
    date_part=""

    # Date prefix handling
    if [[ "$file_name" =~ ^([0-9]{8}_) ]]; then
        date_part="${BASH_REMATCH[1]}"
        file_name="${file_name:9}"
    fi

    debug "Date part: '$date_part' | Base name: '$file_name' | Ext: '$extension'"

    # Name conversion logic (inline snake_case)
    main_name="${file_name%.*}"
    converted_name=$(sed -E '
        s/([a-z0-9])([A-Z])/\1_\2/g;
        s/([A-Z]+)([A-Z][a-z])/\1_\2/g;
        s/[[:space:]]+/_/g;
        s/[_\.]+/_/g;
        s/^_//;
        s/_$//' <<<"$main_name" | tr '[:upper:]' '[:lower:]')
    new_main="$converted_name"
    new_ext=$(sed -E '
        s/([a-z0-9])([A-Z])/\1_\2/g;
        s/([A-Z]+)([A-Z][a-z])/\1_\2/g;
        s/[[:space:]]+/_/g;
        s/[_\.]+/_/g;
        s/^_//;
        s/_$//' <<<"$extension" | tr '[:upper:]' '[:lower:]')

    # Construct new filename
    new_name="${date_part}${new_main}"
    [[ -n "$new_ext" ]] && new_name+=".$new_ext"

    # Duplicate handling
    counter=1
    while [[ -e "$dir_name/$new_name" && "$dir_name/$new_name" != "$orig_path" ]]; do
        debug "Collision detected, trying: $new_name"
        new_name="${date_part}${new_main}_$((counter++))"
        [[ -n "$new_ext" ]] && new_name+=".$new_ext"
    done

    changes+=("$orig_path|$dir_name/$new_name")
done

# Change display/execution logic
if [[ "$DRY_RUN" == true ]]; then
    printf "\n%-60s  %s\n" "Original Path" "Proposed New Path"
    printf "%s\n" "--------------------------------------------------------------------------------"
    for change in "${changes[@]}"; do
        IFS='|' read -r orig new <<<"$change"
        [[ "$orig" == "$new" ]] && continue
        printf "%-60s  %s\n" "$orig" "$new"
    done
    log "Dry run complete. To apply changes, use: $0 --apply"
else
    count=0
    for change in "${changes[@]}"; do
        IFS='|' read -r orig new <<<"$change"
        [[ "$orig" == "$new" ]] && continue
        debug "Renaming: '$orig'  '$new'"
        mv --no-clobber -- "$orig" "$new"
        ((count++))
    done
    log "Renamed $count files"
fi
