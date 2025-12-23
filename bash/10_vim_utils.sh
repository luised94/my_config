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
    printf "=== Current Configuration ===\n"
    printf "EDITOR:              %s\n" "${EDITOR:-<not set>}"
    printf "MC_VIMALL_FILE_LIMIT:   %s\n\n" "${MC_VIMALL_FILE_LIMIT:-150}"

    cat << 'EOF'
Usage: vimall [OPTIONS]

Opens all files in the current directory tree in $EDITOR, sorted by modification time.

Options:
  -f, --force    Skip confirmation prompt for large file counts
  -h, --help     Show this help message

Environment Variables:
  EDITOR              Editor to use (required)
  MC_VIMALL_FILE_LIMIT   File count that triggers confirmation (default: 150)
  MC_EXCLUDE_DIRS Directories to exclude (array)
  MC_EXCLUDE_FILES File patterns to exclude (array)

Examples:
  vimall                        # Open all files with confirmation if > 150
  vimall -f                     # Open all files without confirmation
  MC_VIMALL_FILE_LIMIT=50 vimall   # Lower confirmation threshold
EOF

    printf "=== end vimall help ===\n"
    return 0

  fi
  local force=0
  if [[ "$1" == "-f" ]] || [[ "$1" == "--force" ]]; then
    force=1
    shift
  fi

  local file_limit=${MC_VIMALL_FILE_LIMIT:-150} # How many files will trigger confirmation?

  # Validate EDITOR
  if [[ -z $EDITOR ]]; then
      printf "[ERROR] EDITOR variable not set.\n" >&2
      return 1

  fi

  # Validate EDITOR is executable

  # Use module-level arrays, or minimal fallback if somehow undefined
  local exclude_dirs=("${MC_EXCLUDE_DIRS[@]}")
  local exclude_files=("${MC_EXCLUDE_FILES[@]}")

  if [[ ${#exclude_dirs[@]} -eq 0 ]]; then
      # Minimal fallback (should never happen if file sourced properly)
      exclude_dirs=(".git" "node_modules")
  fi

  if [[ ${#exclude_files[@]} -eq 0 ]]; then
      # Minimal fallback (should never happen if file sourced properly)
      exclude_files=("*.log" "*.bak")
  fi

  # Build find command using arrays
  local find_args=()

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

  if ! mapfile -t files < <(
    find . \( "${find_args[@]}" \) -prune -o -type f -printf '%T@ %p\n' 2>/dev/null |
    sort -rn | \
    cut -d' ' -f2- | \
    tr -d '\r'
  ); then
    printf "[ERROR] Failed to collect files" >&2
    return 1

  fi

  local number_of_files=${#files[@]}
  if [ $number_of_files -eq 0 ]; then
    printf "[ERROR] No files found to edit.\n" >&2
    return 1

  fi

  if [[ $number_of_files -gt $file_limit ]] && [[ $force -eq 0 ]]; then
    printf "[WARNING] Found $number_of_files. Are you sure you want to open all of them? (y/N)"
    read -r confirm
    if [[ $confirm != [yY] ]]; then
      printf "Operation cancelled."
      return 0

    fi

  fi 

  printf "[INFO] Opening %d files in %s\n" "$number_of_files" "$EDITOR"
  "$EDITOR" "${files[@]}"

}

vimpattern() {
  local pattern=$1

  if [[ -z $pattern ]]; then
    printf "[ERROR] Provide search string as first argument." >&2
    return 1

  fi

  # Validate EDITOR
  if [[ -z $EDITOR ]]; then
      printf "[ERROR] EDITOR variable not set.\n" >&2
      return 1

  fi

  if ! command -v git &>/dev/null; then
      printf "[ERROR] git is not installed\n" >&2
      return 1

  fi

  if ! git rev-parse --is-inside-work-tree &>/dev/null; then
      printf "[ERROR] Not inside a git repository\n" >&2
      return 1

  fi


  if ! mapfile -t files < <(git grep -l "${pattern}"); then
      pritnf "[ERROR] Failed to search files.\n" >&2
      return 1

  fi

  if [ ${#files[@]} -eq 0 ]; then
    printf "[ERROR] No files found to edit.\n" >&2
    return 1

  fi

  printf "[INFO] Opening ${#files[@]} files in $EDITOR"
  "$EDITOR" "${files[@]}"

}

vimconflict() {

  # Validate EDITOR
  if [[ -z $EDITOR ]]; then
      printf "[ERROR] EDITOR variable not set.\n" >&2
      return 1

  fi

  if ! command -v git &>/dev/null; then
      printf "[ERROR] git is not installed\n" >&2
      return 1

  fi

  if ! git rev-parse --is-inside-work-tree &>/dev/null; then
      printf "[ERROR] Not inside a git repository\n" >&2
      return 1

  fi

  if ! mapfile -t files < <(
    git diff --name-only --diff-filter=U
    ); then
    printf "[ERROR] Failed to collect conflicted files.\n" >&2
    return 1

  fi

  if [ ${#files[@]} -eq 0 ]; then
    printf "[ERROR] No files found to edit.\n" >&2
    return 1

  fi

  printf "[INFO] Opening ${#files[@]} files in $EDITOR"
  "$EDITOR" "${files[@]}"

}

vimmodified() {

  # Validate EDITOR
  if [[ -z $EDITOR ]]; then
      printf "[ERROR] EDITOR variable not set.\n" >&2
      return 1

  fi

  if ! command -v git &>/dev/null; then
      printf "[ERROR] git is not installed\n" >&2
      return 1

  fi

  if ! git rev-parse --is-inside-work-tree &>/dev/null; then
      printf "[ERROR] Not inside a git repository\n" >&2
      return 1

  fi

  if ! mapfile -t files < <(
    git status --porcelain | sed 's/^...//'
    ); then
    printf " [ERROR] Failed to collect modified files" >&2
    return 1

  fi

  if [ ${#files[@]} -eq 0 ]; then
    printf "[ERROR] No files found to edit.\n" >&2
    return 1

  fi

  printf "[INFO] Opening ${#files[@]} files in $EDITOR"
  "$EDITOR" "${files[@]}"

}
