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

vimall() {

  if [[ "$1" == "-h" ]] || [[ "$1" == "--help" ]]; then
    printf "Usage: vimall [OPTIONS]\n"
    printf "Opens files in tree, sorted by time, respecting MC_EXCLUDE arrays.\n\n"
    printf "Options:\n"
    printf "%s\n" "-f, --force    Skip confirmation prompt"
    printf "%s\n" "-h, --help     Show help message"
    printf "Environment variables:\n"
    printf "  Configured Limit: %s\n" "${MC_VIMALL_FILE_LIMIT:-150}"
    printf "  Current Editor   : %s\n" "${EDITOR}"
    printf "  Exclusion criteria: See MC_EXCLUDE_DIRS and MC_EXCLUDE_FILES\n"
    return 0
  fi

  local find_args=()
  local force=0
  local file_limit=${MC_VIMALL_FILE_LIMIT:-150} # How many files will trigger confirmation?
  local exclude_dirs=("${MC_EXCLUDE_DIRS[@]}")
  local exclude_files=("${MC_EXCLUDE_FILES[@]}")

  if [[ "$1" == "-f" ]] || [[ "$1" == "--force" ]]; then
    force=1
    shift
  fi

  # --- Build find command using arrays ---
  # Add directory exclusions
  for dir in "${exclude_dirs[@]}"; do
      find_args+=(-path "*/${dir}/*" -o)
  done

  # Add file exclusions
  for file in "${exclude_files[@]}"; do
      find_args+=(-name "${file}" -o)
  done

  # Remove trailing -o (last element) if array is not empty
  if [[ ${#find_args[@]} -gt 0 ]]; then
      unset 'find_args[-1]'
  fi

  mapfile -t files < <(
    find . \( "${find_args[@]}" \) -prune -o -type f -printf '%T@ %p\n' 2>/dev/null |
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
  local pattern=$1

  if [[ -z $pattern ]]; then
    msg_error "Provide search string as first argument."
    return 1

  fi

  if ! _is_git_repo; then
    msg_error "This command requires a git repository."
    return 1
  fi

  mapfile -t files < <(git grep -l "${pattern}")

  if [ ${#files[@]} -eq 0 ]; then
    msg_error "No files found to open."
    return 1

  fi

  msg_info "Opening ${#files[@]} files in $EDITOR"
  "$EDITOR" "${files[@]}"

}

vimconflict() {

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

  if ! _is_git_repo; then
    msg_error "This command requires a git repository."
    return 1
  fi

  mapfile -t files < <(
    git status --porcelain | sed 's/^...//'
  )

  if [ ${#files[@]} -eq 0 ]; then
    msg_error "No files found to open."
    return 1

  fi

  msg_info "Opening ${#files[@]} files in $EDITOR"
  "$EDITOR" "${files[@]}"

}
