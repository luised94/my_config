vimall() {
  # show usage?
  # options?
  # Use editor that is set in config.

  if [[ -z $EDITOR ]]; then
    echo "[ERROR] EDITOR variable not set."
    echo "[ERROR] Please assign manually."
    return 1

  fi

  local search_exclude_dirs=(
    ".git"
    "node_modules"
    "build"
    "dist"
    "renv"
    ".venv"
  )

  local search_exclude_files=(
    "*.log"
    "*repository_aggregate.md"
    "*.tmp"
    "*.bak"
    "*.swp"
    "*.gitignore"
    "*.Rprofile"
    "*renv.lock"
  )

  local expressions=()
  # Add directory exclusions
  local first=true
  for dir in "${search_exclude_dirs[@]}"; do
    if [[ "$first" == true ]]; then
        expressions+=("-path" "\"*/${dir}/*\"")
        first=false

    else
        expressions+=("-o" "-path" "\"*/${dir}/*\"")

    fi

  done

  # Add file exclusions
  for file in "${search_exclude_files[@]}"; do
    expressions+=("-o" "-name" "\"${file}\"")

  done

  local exclude_args=$(printf '%s ' "${expressions[@]}")

  if ! mapfile -t files < <(
    set -x
    eval "find . \( ${exclude_args[@]} \) -prune -o -type f -printf '%T@ %p\n'" 2>/dev/null |
    sort -rn | \
    cut -d' ' -f2- | \
    tr -d '\r'
    set +x
  ); then
    printf "[ERROR] Failed to collect files"
    return 1

  fi

  if [ ${#files[@]} -eq 0 ]; then
    printf "[ERROR] No files found to edit.\n"
    return 1

  fi

  echo "[INFO] Opening ${#files[@]} files in $EDITOR"
  eval "$EDITOR" "${files[@]}"

}

vimpattern() {
  local pattern=$1

  if [[ -z $pattern ]]; then
    echo "[ERROR] Provide search string as first argument."
    return 1

  fi

  if [[ -z $EDITOR ]]; then
    echo "[ERROR] EDITOR variable not set."
    echo "[ERROR] Please assign manually."
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
      pritnf "[ERROR] Failed to search files.\n"
      return 1

  fi

  if [ ${#files[@]} -eq 0 ]; then
    printf "[ERROR] No files found to edit.\n"
    return 1

  fi

  echo "[INFO] Opening ${#files[@]} files in $EDITOR"
  eval "$EDITOR" "${files[@]}"

}

vimconflict() {

  if [[ -z $EDITOR ]]; then
    echo "[ERROR] EDITOR variable not set."
    echo "[ERROR] Please assign manually."
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
    printf "[ERROR] Failed to collect conflicted files.\n"
    return 1
  fi

  if [ ${#files[@]} -eq 0 ]; then
    printf "[ERROR] No files found to edit.\n"
    return 1

  fi

  echo "[INFO] Opening ${#files[@]} files in $EDITOR"
  eval "$EDITOR" "${files[@]}"

}

vimmodified() {

  if [[ -z $EDITOR ]]; then
    echo "[ERROR] EDITOR variable not set."
    echo "[ERROR] Please assign manually."
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
    echo " [ERROR] Failed to collect modified files"
    return 1

  fi

  if [ ${#files[@]} -eq 0 ]; then
    printf "[ERROR] No files found to edit.\n"
    return 1

  fi

  echo "[INFO] Opening ${#files[@]} files in $EDITOR"
  eval "$EDITOR" "${files[@]}"

}
