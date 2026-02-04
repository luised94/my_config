#!/bin/bash
# ------------------------------------------------------------------------------
# TITLE      : MC Vim Utilities (10_vim_utils.sh)
# PURPOSE    : Clean, procedural utilities for file management.
# DEPENDENCIES: 03_message.sh, sourced by bashrc.
# DATE: 2025-12-23
# ------------------------------------------------------------------------------

# --- Manual Troubleshooting Helper ---
_mc_vim_utils_health() {
    local status=0

    # 1. Check Messaging Engine (The only dependency we MUST check with printf)
    if [[ "$(type -t msg_info)" != "function" ]]; then
        printf "[CRITICAL] MC Messaging engine (msg_info) not found. Check 03_message.sh\n" >&2
        status=1
    fi

    # 2. Check Global Config Variables
    # Using ${var+x} to check if defined, regardless of value
    if [[ -z ${MC_EXCLUDE_DIRS+x} ]]; then
        printf "[ERROR] MC_EXCLUDE_DIRS is not defined. Check 00_config.sh\n" >&2
        status=1
    fi

    if [[ -z ${MC_EXCLUDE_FILES+x} ]]; then
        printf "[ERROR] MC_EXCLUDE_FILES is not defined. Check 00_config.sh\n" >&2
        status=1
    fi

    # 3. Check System Variables
    if [[ -z "$EDITOR" ]]; then
        printf "[ERROR] EDITOR variable is not set.\n" >&2
        status=1
    fi

    if ! command -v "$EDITOR" &>/dev/null; then
        printf "[ERROR] EDITOR '%s' not found or not executable.\n" "$EDITOR" >&2
        status=1

    fi

    # 4. Check git availability.
    if ! command -v git >/dev/null 2>&1; then
        printf "[ERROR] Git command not found in PATH.\n"
        status=1

    fi

    return $status
}

# --- Private Helper for Find Arguments ---
# This ensures vimall, vimreverse, and vimstale all behave the same way.
_mc_vim_get_exclude_args() {
    # Check if variables exist
    if [[ -z ${MC_EXCLUDE_DIRS+x} ]] || [[ -z ${MC_EXCLUDE_FILES+x} ]]; then
        return 0
    fi

    local args=()
    for dir in "${MC_EXCLUDE_DIRS[@]}"; do
        args+=(-path "*/${dir}/*" -o)
    done

    for file in "${MC_EXCLUDE_FILES[@]}"; do
        args+=(-name "${file}" -o)
    done

    # Remove trailing -o
    if [[ ${#args[@]} -gt 0 ]]; then
        unset 'args[-1]'
        printf "%s\n" "${args[@]}"
    fi
}

_vimall_usage() {
  cat <<EOF
Usage: vimall [OPTIONS]

Opens files in tree, sorted by time, respecting MC_EXCLUDE arrays.

Options:
  -f, --force      Skip confirmation prompt
  -h, --help       Show this help message

Environment variables:
  MC_VIMALL_FILE_LIMIT  Configured Limit (${MC_VIMALL_FILE_LIMIT:-150})
  EDITOR                Current Editor (${EDITOR})
  Exclusion criteria: See MC_EXCLUDE_DIRS and MC_EXCLUDE_FILES
EOF
}

vimall() {

  while [[ $# -gt 0 ]]; do
    case "$1" in
      -h|--help)
        _vimall_usage
        return 0
        ;;
      -f|--force)
        force=1
        shift
        ;;
      -*)
        msg_error "Unknown option: $1"
        return 1
        ;;
      *)
        msg_error "Unexpected argument: $1"
        return 1
        ;;
    esac
  done

  mapfile -t find_excludes < <(_mc_vim_get_exclude_args)

  mapfile -t files < <(
    find . \( "${find_excludes[@]}" \) -prune -o -type f -printf '%T@ %p\n' 2>/dev/null |
    sort -rn | \
    cut -d' ' -f2- | \
    tr -d '\r'
  )

  local number_of_files=${#files[@]}
  msg_debug "Files found: $number_of_files"

  if [ $number_of_files -eq 0 ]; then
    msg_error "No files found to open."
    return 1

  fi

  if [[ $number_of_files -gt $file_limit ]] && [[ $force -eq 0 ]]; then
    msg_warn "Found ${#files[@]} files. Open all? (y/N)"
    read -r confirm
    if [[ $confirm != [yY] ]]; then
      msg_info "Operation cancelled by user."
      return 0

    fi

  fi

  msg_info "Opening ${#files[@]} files in $EDITOR..."
  "$EDITOR" "${files[@]}"

}

vimpattern() {
  if [[ "$1" == "-h" ]] || [[ "$1" == "--help" ]]; then
    printf "Usage: vimpattern [SEARCH_STRING]\n"
    printf "Searches the Git index for files containing the string and opens them.\n"
    return 0
  fi

  local pattern=$1

  # Check if empty or only whitespace
  if [[ -z "${pattern// }" ]]; then
      msg_error "Search pattern cannot be empty or only whitespace."
      return 1
  fi

  if ! _is_git_repo; then
    msg_error "This command requires a git repository."
    return 1
  fi

  mapfile -t files < <(git grep -l "${pattern}")

  msg_debug "Pattern: $pattern | Count: ${#files[@]}"

  if [ ${#files[@]} -eq 0 ]; then
    msg_error "No files found to open."
    return 1

  fi

  msg_info "Opening ${#files[@]} files in $EDITOR"
  "$EDITOR" "${files[@]}"

}

vimconflict() {
  if [[ "$1" == "-h" ]] || [[ "$1" == "--help" ]]; then
    printf "Usage: vimconflict\n"
    printf "Opens all files currently in a 'Unmerged' (conflict) state.\n"
    return 0
  fi

  if ! _is_git_repo; then
    msg_error "This command requires a git repository."
    return 1
  fi

  mapfile -t files < <(
    git diff --name-only --diff-filter=U
  )

  if [ ${#files[@]} -eq 0 ]; then
    msg_error "No files found to open."
    return 1

  fi

  msg_info "Opening ${#files[@]} files in $EDITOR"
  "$EDITOR" "${files[@]}"

}

vimmodified() {
  if [[ "$1" == "-h" ]] || [[ "$1" == "--help" ]]; then
    printf "Usage: vimmodified\n"
    printf "Opens all files changed in the working tree and index.\n"
    return 0
  fi

  if ! _is_git_repo; then
    msg_error "This command requires a git repository."
    return 1
  fi

  mapfile -t files < <(
    git ls-files -m --others --exclude-standard
    #git status --porcelain | sed 's/^...//'
  )

  if [ ${#files[@]} -eq 0 ]; then
    msg_error "No files found to open."
    return 1

  fi

  msg_info "Opening ${#files[@]} files in $EDITOR"
  "$EDITOR" "${files[@]}"

}

vimstale() {
    if [[ "$1" == "-h" ]] || [[ "$1" == "--help" ]]; then
        printf "Usage: vimstale [DAYS]\n"
        printf "Opens files that have not been modified in X days (default: 30).\n"
        return 0
    fi

    local days="${1:-30}"
    local files=()

    mapfile -t find_excludes < <(_mc_vim_get_exclude_args)

    msg_info "Searching for files untouched for $days+ days..."

    # Gather files older than X days
    mapfile -t files < <(
        find . \( "${find_excludes[@]}" \) -prune -o -type f -mtime +"$days" -print 2>/dev/null
    )

    msg_debug "Stale count: ${#files[@]}"

    if [[ ${#files[@]} -eq 0 ]]; then
        msg_info "No stale files found."
        return 0
    fi

    msg_warn "Found ${#files[@]} stale files. Open them? (y/N)"
    read -r confirm
    if [[ "$confirm" == "y" ]] || [[ "$confirm" == "Y" ]]; then
        "$EDITOR" "${files[@]}"
    fi
}

vimreverse() {
    if [[ "$1" == "-h" ]] || [[ "$1" == "--help" ]]; then
        printf "Usage: vimreverse [COUNT]\n"
        printf "Opens the X oldest files in the current tree (default: 10).\n"
        return 0
    fi

    local count="${1:-10}"
    local files=()

    mapfile -t find_excludes < <(_mc_vim_get_exclude_args)

    msg_info "Collecting the $count oldest files..."

    # Sort by time (oldest first) and take the top N
    mapfile -t files < <(
        find . \( "${find_excludes[@]}" \) -prune -o -type f -printf '%T+ %p\n' 2>/dev/null |
        sort |
        cut -d' ' -f2-
    )

    if [[ ${#files[@]} -eq 0 ]]; then
        msg_error "No files found."
        return 1
    fi

    msg_debug "Opening oldest files: ${files[*]}"
    "$EDITOR" "${files[@]}"
}

vimdiff() {
    if [[ "$1" == "-h" ]] || [[ "$1" == "--help" ]]; then
        printf "Usage: vimdiff [TARGET]\n"
        printf "Opens files that differ between current state and TARGET.\n"
        printf "TARGET can be a branch (main), a commit, or a tag.\n"
        printf "Default TARGET: main\n"
        return 0
    fi

    if ! _is_git_repo; then
        msg_error "This command requires a git repository."
        return 1
    fi

    local target="${1:-main}"

    # Validation: Does the target exist in Git?
    if ! git rev-parse --verify "$target" >/dev/null 2>&1; then
        msg_error "Invalid target: '$target' is not a valid branch, commit, or tag."
        return 1
    fi

    msg_info "Checking differences against '$target'..."

    mapfile -t files < <(git diff --name-only "$target")

    if [[ ${#files[@]} -eq 0 ]]; then
        msg_info "No differences found against $target."
        return 0
    fi

    msg_debug "Changed files: ${files[*]}"
    msg_info "Opening ${#files[@]} changed files..."
    "$EDITOR" "${files[@]}"
}
