#!/bin/bash
# vim_helpers.sh

# ============================================================================
# File and directory exclusions for vim helper functions
# These can be overridden by defining these arrays before sourcing this file
# ============================================================================
# Default exclusion directories (if not already defined)
if [[ ${#VIMALL_EXCLUDE_DIRS[@]} -eq 0 ]]; then
    VIMALL_EXCLUDE_DIRS=(
        # Version control
        ".git"

        # Node/JavaScript ecosystem
        "node_modules"
        ".next"
        ".nuxt"
        ".svelte-kit"

        # Python ecosystem
        "__pycache__"
        ".venv"
        "venv"
        "env"
        ".pytest_cache"
        ".mypy_cache"
        ".tox"
        ".ipynb_checkpoints"

        # R ecosystem
        "renv"
        ".Rproj.user"

        # Build artifacts (multi-language)
        "build"
        "dist"
        "target"
        "out"
        "bin"

        # Dependencies/vendors
        "vendor"
        "deps"

        # IDE/Editor
        ".idea"
        ".vscode"

        # Cache/temp
        ".cache"
        "tmp"
        "temp"

        # Coverage/test reports
        "coverage"
        "htmlcov"
    )

fi

# Default exclusion file patterns (if not already defined)
if [[ ${#VIMALL_EXCLUDE_FILES[@]} -eq 0 ]]; then
    VIMALL_EXCLUDE_FILES=(
        # Logs and temp files
        "*.log"
        "*.tmp"
        "*.bak"
        "*.swp"
        "*.swo"

        # Compiled/bytecode
        "*.pyc"
        "*.pyo"
        "*.o"
        "*.so"
        "*.a"
        "*.class"

        # OS files
        ".DS_Store"
        "Thumbs.db"

        # Your custom exclusions
        "*repository_aggregate.md"
        "*.gitignore"
        "*.Rprofile"
        "*renv.lock"
    )

fi

vimall() {
  # Add at top
  if [[ "$1" == "-h" ]] || [[ "$1" == "--help" ]]; then
      cat << 'EOF'
  Usage: vimall [OPTIONS]

  Opens all files in the current directory tree in EDITOR variable, sorted by modification time.

  Options:
    -f, --force    Skip confirmation prompt for large file counts
    -h, --help     Show this help message

  Environment Variables:
    EDITOR              Editor to use (required)
    VIMALL_FILE_LIMIT   File count that triggers confirmation (default: 150)
    VIMALL_EXCLUDE_DIRS Directories to exclude (array)
    VIMALL_EXCLUDE_FILES File patterns to exclude (array)

  Examples:
    vimall              # Open all files with confirmation if > 150
    vimall -f           # Open all files without confirmation
    VIMALL_FILE_LIMIT=50 vimall  # Lower confirmation threshold
EOF
  return 0

  fi

  local file_limit=${VIMALL_FILE_LIMIT:-150} # How many files will trigger confirmation?

  # Validate EDITOR
  if [[ -z $EDITOR ]]; then
      printf "[ERROR] EDITOR variable not set.\n" >&2
      return 1

  fi
  #
  # Validate EDITOR is executable
  if ! command -v "$EDITOR" &>/dev/null; then
      printf "[ERROR] EDITOR '%s' not found or not executable.\n" "$EDITOR" >&2
      return 1

  fi

  # Use module-level arrays, or minimal fallback if somehow undefined
  local exclude_dirs=("${VIMALL_EXCLUDE_DIRS[@]}")
  local exclude_files=("${VIMALL_EXCLUDE_FILES[@]}")

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

  if [ $number_of_files -gt $file_limit ]; then
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
