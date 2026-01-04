
# ------------------------------------------------------------------------------
# FUNCTION   : new_worktree
# PURPOSE    : Create a git worktree for an existing branch.
# USAGE      : new_worktree <branch-name> [worktree-root]
# ARGS       : branch-name   - Name of an existing local branch
#              worktree-root - Directory for worktrees (default: $HOME/personal_repos)
# RETURNS    : 0 on success, 1 on error
# ------------------------------------------------------------------------------
new_worktree() {
  if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
    printf "Usage: %s <branch-name> [worktree-root]\n\n" "${FUNCNAME[0]}"
    printf "Create a git worktree for an existing branch.\n\n"
    printf "Arguments:\n"
    printf "  branch-name    Name of existing local branch\n"
    printf "  worktree-root  Directory for worktrees (default: \$HOME/personal_repos)\n\n"
    printf "Examples:\n"
    printf "  %s feature/login\n" "${FUNCNAME[0]}"
    printf "  %s bugfix/header ~/work/trees\n" "${FUNCNAME[0]}"
    return 0
  fi

  if ! _is_git_repo; then
    msg_error "Not inside a git repository"
    return 1
  fi

  local branch_name="$1"
  local worktree_root="${2:-$HOME/personal_repos}"

  if [[ -z "$branch_name" ]]; then
    msg_error "Branch name required"
    msg_info "Run '${FUNCNAME[0]} -h' for usage"
    return 1
  fi

  if ! git show-ref --verify --quiet "refs/heads/$branch_name"; then
    msg_error "Branch '$branch_name' does not exist"
    msg_info "Create it with: git checkout -b $branch_name"
    return 1
  fi

  # Build destination path
  # @ANTICIPATE: Delimiter choice may matter for parsing worktree paths later
  local repo_name
  repo_name="$(basename "$(git rev-parse --show-toplevel)")"
  local sanitized_branch="${branch_name//\//-}"
  local dest_path="${worktree_root}/${repo_name}-${sanitized_branch}"

  if [[ -e "$dest_path" ]]; then
    msg_error "Path already exists: $dest_path"
    return 1
  fi

  mkdir -p "$worktree_root" || return 1
  msg_info "Creating worktree: $dest_path"
  git worktree add "$dest_path" "$branch_name"
}

# ------------------------------------------------------------------------------
# FUNCTION   : rebase_worktrees_on_main
# PURPOSE    : Rebase all worktrees of current repository onto main branch.
# USAGE      : rebase_worktrees_on_main [worktree-root]
# ARGS       : worktree-root - Directory containing worktrees (default: $HOME/personal_repos)
# RETURNS    : 0 on success, 1 on error
# NOTES      : Expects worktree naming convention: <repo>-<branch>
# ------------------------------------------------------------------------------
rebase_worktrees_on_main() {
  if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
    printf "Usage: %s [worktree-root]\n\n" "${FUNCNAME[0]}"
    printf "Rebase all worktrees of current repository onto main.\n\n"
    printf "Arguments:\n"
    printf "  worktree-root  Directory containing worktrees (default: \$HOME/personal_repos)\n\n"
    printf "Notes:\n"
    printf "  - Must be run from within the main repository\n"
    printf "  - Expects worktree dirs named: <repo>-<branch>\n"
    printf "  - Uses --force-with-lease for safe pushes\n"
    return 0
  fi

  if ! _is_git_repo; then
    msg_error "Not inside a git repository"
    return 1
  fi

  local worktree_root="${1:-$HOME/personal_repos}"
  local current_repo
  current_repo="$(basename "$(git rev-parse --show-toplevel)")"
  local start_dir
  start_dir="$(pwd)"

  if [[ ! -d "$worktree_root" ]]; then
    msg_error "Worktree root does not exist: $worktree_root"
    return 1
  fi

  # Find worktrees matching this repo's naming pattern
  local worktree_paths
  mapfile -t worktree_paths < <(
    find "$worktree_root" -maxdepth 1 -mindepth 1 -type d -name "${current_repo}-*"
  )

  if (( ${#worktree_paths[@]} == 0 )); then
    msg_warn "No worktrees found for '$current_repo' in $worktree_root"
    return 0
  fi

  msg_info "Found ${#worktree_paths[@]} worktree(s) for $current_repo"

  local branch
  local fail_count=0

  for wt_path in "${worktree_paths[@]}"; do
    cd "$wt_path" || continue
    branch="$(git rev-parse --abbrev-ref HEAD)"

    msg_info "Rebasing: $branch"

    if git rebase main; then
      msg_info "Pushing: $branch"
      if ! git push --force-with-lease origin "$branch"; then
        msg_error "Push failed for $branch"
        fail_count=$((fail_count + 1))
      fi
    else
      msg_error "Rebase conflict in $branch - aborting"
      git rebase --abort
      fail_count=$((fail_count + 1))
    fi
  done

  cd "$start_dir" || return 1

  if (( fail_count > 0 )); then
    msg_warn "Completed with $fail_count failure(s)"
    return 1
  fi

  msg_info "All worktrees rebased successfully"
  return 0
}

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
