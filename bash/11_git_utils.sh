
# ------------------------------------------------------------------------------
# FUNCTION   : pull_all_repos
# PURPOSE    : Pull latest changes for all git repositories in a directory.
# USAGE      : pull_all_repos [directory]
# ARGS       : directory - Root containing repos (default: $HOME/personal_repos)
# RETURNS    : 0 if all repos pulled successfully, 1 otherwise
# ------------------------------------------------------------------------------
pull_all_repos() {

  # --- Help ---
  if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
    printf "Usage: %s [directory]\n\n" "${FUNCNAME[0]}"
    printf "Pull latest changes for all git repositories in a directory.\n\n"
    printf "Arguments:\n"
    printf "  directory   Root containing repos (default: \$HOME/personal_repos)\n\n"
    printf "Options:\n"
    printf "  -h, --help  Show this help message\n"
    return 0

  fi

  local repos_root="${1:-$HOME/personal_repos}"

  # --- Validate directory ---
  if [[ ! -d "$repos_root" ]]; then
    msg_error "Repository root does not exist: $repos_root"
    return 1

  fi

  # --- Collect repositories ---
  shopt -s nullglob
  local repo_paths=("$repos_root"/*/)
  shopt -u nullglob

  if (( ${#repo_paths[@]} == 0 )); then
    msg_warn "No subdirectories found in $repos_root"
    return 0

  fi

  # --- Process each repository ---
  local success_count=0
  local stash_count=0
  local total_count=0
  local repo_name

  for repo_path in "${repo_paths[@]}"; do
    repo_path="${repo_path%/}"
    repo_name="$(basename "$repo_path")"
    total_count=$((total_count + 1))

    # Skip non-git directories
    if ! git -C "$repo_path" rev-parse --git-dir >/dev/null 2>&1; then
      msg_debug "Skipping $repo_name (not a git repository)"
      continue

    fi

    msg_info "Pulling: $repo_name"

    # Stash uncommitted changes
    if ! git -C "$repo_path" diff-index --quiet HEAD 2>/dev/null; then
      msg_warn "Stashing local changes in $repo_name"
      git -C "$repo_path" stash push -u -m "auto-stash before pull $(date -Iseconds)"
      stash_count=$((stash_count + 1))

    fi

    # Pull with fast-forward only
    if git -C "$repo_path" pull --ff-only; then
      success_count=$((success_count + 1))

    else
      msg_error "Pull failed for $repo_name"

    fi

  done

  # --- Summary ---
  msg_info "Complete: $success_count/$total_count repos pulled"
  if (( stash_count > 0 )); then
    msg_warn "$stash_count repo(s) have stashed changes"

  fi

  (( success_count == total_count ))
}
