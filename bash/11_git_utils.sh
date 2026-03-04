# ==============================================================================
# GIT REPOSITORY UTILITIES
# ==============================================================================
#
# Batch operations for managing multiple git repositories under a single root
# directory, with first-class support for worktrees.
#
# DIRECTORY LAYOUT
#   $HOME/personal_repos/ (repos_root default.)
#     reponame/                  Main worktree (holds the .git directory)
#     reponame-branch_name/     Linked worktree (points back to main's .git)
#     reponame-scope-branch/    Nested worktree naming is supported
#
# WORKTREE MODEL
#   A main worktree and its linked worktrees share a single git directory.
#   All branches, stashes, and refs exist once in the shared store. Functions
#   that modify refs (prune, rebase) deduplicate via git-common-dir to avoid
#   operating on the same git database multiple times.
#
# ASSUMPTIONS
#   - All repos live as immediate subdirectories of the repos root (no nesting).
#   - The remote is always named "origin".
#   - Each repo has a primary branch named "main" or "master" (checked in that
#     order). Both are protected from deletion alongside "develop".
#   - Local-path remotes (USB, NAS) may be offline; functions detect and skip.
#   - Submodules are not traversed. Operations apply to top-level repos only.
#
# CONVENTIONS
#   - pull_all_repos auto-stashes with a tagged message ("auto-stash before
#     pull <timestamp>") so stash_report can identify and flag them.
#   - Pulls use --ff-only; diverged histories are never force-resolved.
#   - Pushes use regular push; diverged histories are reported and skipped.
#     Manual resolution with --force-with-lease is left to the user.
#   - prune_merged_branches is dry-run by default; --delete is opt-in.
#
# DEPENDENCIES
#   - git (2.36+ recommended for worktree list --porcelain and + prefix)
#   - msg_info, msg_warn, msg_error, msg_debug helpers (defined elsewhere)
#
# FUNCTION ORDER (lifecycle: inspect -> sync -> create -> mutate -> destroy)
#   status_all_repos        Read-only overview of all repos
#   stash_report            Read-only stash inventory
#   pull_all_repos          Fetch and fast-forward all repos
#   push_all_repos          Push unpushed commits
#   new_worktree            Create a linked worktree
#   rebase_worktrees_on_main  Rebase worktree branches onto main
#   prune_merged_branches   Delete fully-merged local branches
# RELATED
# ==============================================================================
# ------------------------------------------------------------------------------
# FUNCTION   : status_all_repos
# PURPOSE    : Display a compact status overview for all git repos in a directory.
# USAGE      : status_all_repos [--fetch] [directory]
# ARGS       : directory - Root containing repos (default: $HOME/personal_repos)
# FLAGS      : --fetch   - Run git fetch --prune before reporting
# RETURNS    : 0 if all repos are clean and synced, 1 otherwise
# ------------------------------------------------------------------------------
status_all_repos() {
  # --- Help ---
  if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
    printf "Usage: %s [directory]\n\n" "${FUNCNAME[0]}"
    printf "Display a compact status overview for all git repos in a directory.\n\n"
    printf "Arguments:\n"
    printf "  directory    Root containing repos (default: \$HOME/personal_repos)\n\n"
    printf "Options:\n"
    printf "  --fetch      Fetch from remotes before reporting\n"
    printf "  -h, --help   Show this help message\n"
    return 0
  fi

  # --- Parse arguments ---
  local do_fetch=false
  local repos_root=""

  while (( $# > 0 )); do
    case "$1" in
      --fetch) do_fetch=true; shift ;;
      *)       repos_root="$1"; shift ;;
    esac
  done

  repos_root="${repos_root:-$HOME/personal_repos}"

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

  # --- Table header ---
  printf "%-25s %-15s %-12s %-8s %-8s\n" "REPO" "BRANCH" "SYNC" "DIRTY" "STASH"
  printf "%-25s %-15s %-12s %-8s %-8s\n" "----" "------" "----" "-----" "-----"

  # --- Process each repository ---
  local has_issues=false
  local repo_name branch sync_status dirty_flag stash_count

  for repo_path in "${repo_paths[@]}"; do
    repo_path="${repo_path%/}"
    repo_name="$(basename "$repo_path")"

    # Skip non-git directories
    if ! git -C "$repo_path" rev-parse --git-dir >/dev/null 2>&1; then
      msg_debug "Skipping $repo_name (not a git repository)"
      continue
    fi

    # --- Branch ---
    branch=$(git -C "$repo_path" symbolic-ref --short HEAD 2>/dev/null) || branch="(detached)"

    # --- Fetch if requested ---
    if [[ "$do_fetch" == true ]]; then
      if [[ "$remote_unavailable" != true ]]; then
        git -C "$repo_path" fetch --prune --quiet 2>/dev/null || true
      fi
    fi

    # --- Sync status ---
    sync_status="-"
    local remote="origin"
    local tracking="${remote}/${branch}"
    local remote_unavailable=false
    local url
    url=$(git -C "$repo_path" remote get-url "$remote" 2>/dev/null)

    if [[ "$url" == /* || "$url" == file://* ]]; then
      [[ ! -d "${url#file://}" ]] && remote_unavailable=true
    fi

    if [[ "$remote_unavailable" == true ]]; then
      sync_status="no remote"
      has_issues=true
    elif [[ "$branch" == "(detached)" ]]; then
      sync_status="detached"
      has_issues=true
    elif git -C "$repo_path" rev-parse --verify "$tracking" >/dev/null 2>&1; then
      local ahead behind
      ahead=$(git -C "$repo_path" rev-list --count "${tracking}..HEAD" 2>/dev/null) || ahead=0
      behind=$(git -C "$repo_path" rev-list --count "HEAD..${tracking}" 2>/dev/null) || behind=0

      if (( ahead > 0 && behind > 0 )); then
        sync_status="diverged"
        has_issues=true
      elif (( ahead > 0 )); then
        sync_status="+${ahead} ahead"
        has_issues=true
      elif (( behind > 0 )); then
        sync_status="-${behind} behind"
        has_issues=true
      else
        sync_status="synced"
      fi
    else
      sync_status="no tracking"
      has_issues=true
    fi

    # --- Dirty working tree ---
    if ! git -C "$repo_path" diff-index --quiet HEAD 2>/dev/null; then
      dirty_flag="yes"
      has_issues=true
    else
      dirty_flag="-"
    fi

    # --- Stash count ---
    stash_count=$(git -C "$repo_path" stash list 2>/dev/null | wc -l)
    stash_count=$((stash_count + 0))  # trim whitespace from wc
    if (( stash_count > 0 )); then
      has_issues=true
    fi

    # --- Print row ---
    printf "%-25s %-15s %-12s %-8s %-8s\n" \
      "$repo_name" \
      "$branch" \
      "$sync_status" \
      "$dirty_flag" \
      "${stash_count:-0}"
  done

  # --- Footer ---
  printf "\n"
  if [[ "$has_issues" == true ]]; then
    msg_warn "Some repos need attention"
  else
    msg_info "All repos clean and synced"
  fi

  [[ "$has_issues" == false ]]
}

# ------------------------------------------------------------------------------
# FUNCTION   : stash_report
# PURPOSE    : Report stash entries across all git repositories in a directory.
# USAGE      : stash_report [directory]
# ARGS       : directory - Root containing repos (default: $HOME/personal_repos)
# RETURNS    : 0 if no stashes found, 1 if stashes exist
# ------------------------------------------------------------------------------
stash_report() {
  # --- Help ---
  if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
    printf "Usage: %s [directory]\n\n" "${FUNCNAME[0]}"
    printf "Report stash entries across all git repositories in a directory.\n\n"
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

  # --- Deduplicate shared git directories (worktrees) ---
  local -A seen_git_dirs=()

  # --- Process each repository ---
  local total_stashes=0
  local repos_with_stashes=0
  local auto_stash_count=0

  for repo_path in "${repo_paths[@]}"; do
    repo_path="${repo_path%/}"
    local repo_name="$(basename "$repo_path")"

    # Skip non-git directories
    if ! git -C "$repo_path" rev-parse --git-dir >/dev/null 2>&1; then
      continue
    fi

    # Deduplicate worktrees
    local git_dir
    git_dir=$(git -C "$repo_path" rev-parse --path-format=absolute --git-common-dir 2>/dev/null) \
      || git_dir=$(git -C "$repo_path" rev-parse --git-dir 2>/dev/null)

    if [[ -n "${seen_git_dirs[$git_dir]+x}" ]]; then
      continue
    fi
    seen_git_dirs[$git_dir]="$repo_name"

    # Resolve display name for worktree families
    local display_name="$repo_name"
    local main_wt_path
    main_wt_path=$(git -C "$repo_path" worktree list --porcelain 2>/dev/null \
      | awk 'NR==1 && /^worktree /{print $2}')
    if [[ -n "$main_wt_path" && "$main_wt_path" != "$repo_path" ]]; then
      display_name="$(basename "$main_wt_path") (via $repo_name)"
    fi

    # Read stash entries
    local stash_entries
    stash_entries=$(git -C "$repo_path" stash list 2>/dev/null)
    [[ -z "$stash_entries" ]] && continue

    local count
    count=$(printf '%s\n' "$stash_entries" | wc -l)
    count=$((count + 0))

    repos_with_stashes=$((repos_with_stashes + 1))
    total_stashes=$((total_stashes + count))

    msg_info "$display_name - $count stash(es):"

    while IFS= read -r entry; do
      # entry format: stash@{N}: WIP on branch: <hash> <message>
      #           or: stash@{N}: On branch: <message>
      local stash_ref="${entry%%:*}"
      local stash_rest="${entry#*: }"

      # Extract age from stash ref
      local stash_date
      stash_date=$(git -C "$repo_path" log -1 --format="%ar" "$stash_ref" 2>/dev/null)

      # Flag auto-stashes from pull_all_repos
      local auto_flag=""
      if [[ "$entry" == *"auto-stash before pull"* ]]; then
        auto_flag=" [auto]"
        auto_stash_count=$((auto_stash_count + 1))
      fi

      msg_info "  $stash_ref  ($stash_date)${auto_flag}"
      msg_info "    $stash_rest"
    done <<< "$stash_entries"
  done

  # --- Summary ---
  printf "\n"
  if (( total_stashes == 0 )); then
    msg_info "No stashes found"
    return 0
  fi

  msg_info "$total_stashes stash(es) across $repos_with_stashes repo(s)"
  if (( auto_stash_count > 0 )); then
    msg_warn "$auto_stash_count auto-stash(es) from pull_all_repos"
  fi

  return 1
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

    # Check if origin is available. Deals with repos with local origins (like a USB)
    remote_unavailable=false
    remote="origin"
    url=$(git -C "$repo_path" remote get-url "$remote" 2>/dev/null)
    
    if [[ "$url" == /* || "$url" == file://* ]]; then
      [[ ! -d "${url#file://}" ]] && remote_unavailable=true
    fi

    if [[ "$remote_unavailable" == true ]]; then
      msg_warn "Remote unavailable: ${repo_path##*/}"
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

# ------------------------------------------------------------------------------
# FUNCTION   : push_all_repos
# PURPOSE    : Push local commits for all git repositories in a directory.
# USAGE      : push_all_repos [directory]
# ARGS       : directory - Root containing repos (default: $HOME/personal_repos)
# RETURNS    : 0 if all repos pushed successfully, 1 otherwise
# ------------------------------------------------------------------------------
push_all_repos() {
  # --- Help ---
  if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
    printf "Usage: %s [directory]\n\n" "${FUNCNAME[0]}"
    printf "Push local commits for all git repositories in a directory.\n\n"
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

  # --- Identify repos with unpushed commits ---
  local pushable_repos=()
  local diverged_repos=()
  local dirty_repos=()
  local repo_name

  for repo_path in "${repo_paths[@]}"; do
    repo_path="${repo_path%/}"
    repo_name="$(basename "$repo_path")"

    # Skip non-git directories
    if ! git -C "$repo_path" rev-parse --git-dir >/dev/null 2>&1; then
      msg_debug "Skipping $repo_name (not a git repository)"
      continue
    fi

    # Check if origin is available
    local remote_unavailable=false
    local remote="origin"
    local url
    url=$(git -C "$repo_path" remote get-url "$remote" 2>/dev/null)

    if [[ "$url" == /* || "$url" == file://* ]]; then
      [[ ! -d "${url#file://}" ]] && remote_unavailable=true
    fi

    if [[ "$remote_unavailable" == true ]]; then
      msg_warn "Remote unavailable: $repo_name"
      continue
    fi

    # Warn about dirty working tree (staged or unstaged changes)
    if ! git -C "$repo_path" diff-index --quiet HEAD 2>/dev/null; then
      dirty_repos+=("$repo_name")
    elif [[ -n "$(git -C "$repo_path" diff --cached --name-only 2>/dev/null)" ]]; then
      # diff-index catches both, but just in case: check staged explicitly
      dirty_repos+=("$repo_name")
    fi

    # Determine current branch and its tracking ref
    local branch
    branch=$(git -C "$repo_path" symbolic-ref --short HEAD 2>/dev/null) || continue
    local tracking="${remote}/${branch}"

    # Skip if no remote tracking branch exists
    if ! git -C "$repo_path" rev-parse --verify "$tracking" >/dev/null 2>&1; then
      msg_debug "Skipping $repo_name (no tracking branch: $tracking)"
      continue
    fi

    local ahead behind
    ahead=$(git -C "$repo_path" rev-list --count "${tracking}..HEAD" 2>/dev/null) || continue
    behind=$(git -C "$repo_path" rev-list --count "HEAD..${tracking}" 2>/dev/null) || continue

    if (( ahead > 0 && behind > 0 )); then
      # History has diverged - likely an amend or rebase
      diverged_repos+=("$repo_name")
    elif (( ahead > 0 )); then
      pushable_repos+=("$repo_path")
    fi
  done

  # --- Report diverged repos (do NOT auto-force-push) ---
  if (( ${#diverged_repos[@]} > 0 )); then
    msg_warn "${#diverged_repos[@]} repo(s) have diverged history (amend/rebase?) - skipping:"
    for name in "${diverged_repos[@]}"; do
      msg_warn "  $name  (resolve manually with: git push --force-with-lease)"
    done
  fi

  # --- Report dirty working trees ---
  if (( ${#dirty_repos[@]} > 0 )); then
    msg_warn "${#dirty_repos[@]} repo(s) have uncommitted changes (won't be pushed):"
    for name in "${dirty_repos[@]}"; do
      msg_warn "  $name"
    done
  fi

  # --- Early exit if nothing to push ---
  if (( ${#pushable_repos[@]} == 0 )); then
    msg_info "Nothing to push - all repos are up to date"
    (( ${#diverged_repos[@]} == 0 ))
  fi

  msg_info "Found ${#pushable_repos[@]} repo(s) with unpushed commits"

  # --- Push each repository ---
  local success_count=0
  local fail_count=0
  local total_count=${#pushable_repos[@]}

  for repo_path in "${pushable_repos[@]}"; do
    repo_name="$(basename "$repo_path")"
    msg_info "Pushing: $repo_name"

    if git -C "$repo_path" push; then
      success_count=$((success_count + 1))
    else
      msg_error "Push failed for $repo_name"
      fail_count=$((fail_count + 1))
    fi
  done

  # --- Summary ---
  msg_info "Complete: $success_count/$total_count repos pushed"
  if (( fail_count > 0 )); then
    msg_warn "$fail_count repo(s) failed to push"
  fi

  (( fail_count == 0 && ${#diverged_repos[@]} == 0 ))
}

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
# FUNCTION   : prune_merged_branches
# PURPOSE    : Remove local branches fully merged into their repo's main branch.
# USAGE      : prune_merged_branches [--delete] [directory]
# ARGS       : directory - Root containing repos (default: $HOME/personal_repos)
# FLAGS      : --delete  - Actually delete branches (default is dry-run)
# RETURNS    : 0 if successful, 1 otherwise
# NOTE       : Does not recurse into submodules. Worktree-linked branches and
#              shared worktree repos are handled safely (see below).
# ------------------------------------------------------------------------------
prune_merged_branches() {
  # --- Help ---
  if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
    printf "Usage: %s [--delete] [directory]\n\n" "${FUNCNAME[0]}"
    printf "Remove local branches fully merged into their repo's main branch.\n\n"
    printf "Arguments:\n"
    printf "  directory    Root containing repos (default: \$HOME/personal_repos)\n\n"
    printf "Options:\n"
    printf "  --delete     Actually delete branches (default is dry-run)\n"
    printf "  -h, --help   Show this help message\n"
    return 0
  fi

  # --- Parse arguments ---
  local delete=false
  local repos_root=""

  while (( $# > 0 )); do
    case "$1" in
      --delete) delete=true; shift ;;
      *)        repos_root="$1"; shift ;;
    esac
  done

  repos_root="${repos_root:-$HOME/personal_repos}"

  # --- Validate directory ---
  if [[ ! -d "$repos_root" ]]; then
    msg_error "Repository root does not exist: $repos_root"
    return 1
  fi

  # --- Protected branch names (never pruned) ---
  local protected_branches=("main" "master" "develop")

  # --- Collect repositories ---
  shopt -s nullglob
  local repo_paths=("$repos_root"/*/)
  shopt -u nullglob

  if (( ${#repo_paths[@]} == 0 )); then
    msg_warn "No subdirectories found in $repos_root"
    return 0
  fi

  if [[ "$delete" == false ]]; then
    msg_info "Dry-run mode - pass --delete to remove branches"
  fi

  # --- Deduplicate shared git directories (worktrees of the same repo) ---
  # Multiple worktrees share a .git dir; deleting a branch in one affects all.
  # Process each unique git dir only once to avoid double-counting/deleting.
  local -A seen_git_dirs=()

  # --- Process each repository ---
  local total_prunable=0
  local total_deleted=0
  local total_worktree_skips=0
  local repo_name

  for repo_path in "${repo_paths[@]}"; do
    repo_path="${repo_path%/}"
    repo_name="$(basename "$repo_path")"

    # Skip non-git directories
    if ! git -C "$repo_path" rev-parse --git-dir >/dev/null 2>&1; then
      msg_debug "Skipping $repo_name (not a git repository)"
      continue
    fi

    # Resolve the actual git directory to deduplicate worktrees
    local git_dir
    git_dir=$(git -C "$repo_path" rev-parse --path-format=absolute --git-common-dir 2>/dev/null) \
      || git_dir=$(git -C "$repo_path" rev-parse --git-dir 2>/dev/null)

    if [[ -n "${seen_git_dirs[$git_dir]+x}" ]]; then
      msg_debug "Skipping $repo_name (shared git dir, processed via ${seen_git_dirs[$git_dir]})"
      continue
    fi

    # For worktree families, resolve the main worktree name for clearer output
    local display_name="$repo_name"
    local main_wt_path
    main_wt_path=$(git -C "$repo_path" worktree list --porcelain 2>/dev/null \
      | awk 'NR==1 && /^worktree /{print $2}')
    if [[ -n "$main_wt_path" && "$main_wt_path" != "$repo_path" ]]; then
      display_name="$(basename "$main_wt_path") (via $repo_name)"
    fi

    seen_git_dirs[$git_dir]="$repo_name"

    # Determine the main branch for this repo
    local main_branch=""
    for candidate in main master; do
      if git -C "$repo_path" rev-parse --verify "$candidate" >/dev/null 2>&1; then
        main_branch="$candidate"
        break
      fi
    done

    if [[ -z "$main_branch" ]]; then
      msg_debug "Skipping $repo_name (no main/master branch found)"
      continue
    fi

    # Current branch (never prune)
    local current_branch
    current_branch=$(git -C "$repo_path" symbolic-ref --short HEAD 2>/dev/null) || continue

    # Find merged branches
    local -a prunable=()
    local -a worktree_skipped=()

    while IFS= read -r raw_line; do
      [[ -z "$raw_line" ]] && continue

      local branch="$raw_line"
      local is_current=false
      local is_worktree=false

      # Parse git branch prefix markers
      case "$branch" in
        "* "*)  branch="${branch#\* }"; is_current=true ;;
        "+ "*)  branch="${branch#+ }";  is_worktree=true ;;
        "  "*)  branch="${branch#  }" ;;
      esac

      # Trim any remaining whitespace
      branch="${branch#"${branch%%[![:space:]]*}"}"
      [[ -z "$branch" ]] && continue

      # Skip current branch
      [[ "$is_current" == true ]] && continue

      # Skip protected branches
      local is_protected=false
      for p in "${protected_branches[@]}"; do
        [[ "$branch" == "$p" ]] && is_protected=true && break
      done
      [[ "$is_protected" == true ]] && continue

      # Skip worktree-linked branches (protected)
      if [[ "$is_worktree" == true ]]; then
        worktree_skipped+=("$branch")
        total_worktree_skips=$((total_worktree_skips + 1))
        continue
      fi

      prunable+=("$branch")
    done < <(git -C "$repo_path" branch --merged "$main_branch" 2>/dev/null)

    # Report worktree-protected branches
    if (( ${#worktree_skipped[@]} > 0 )); then
      msg_info "$display_name - ${#worktree_skipped[@]} worktree branch(es) protected:"
      for branch in "${worktree_skipped[@]}"; do
        msg_debug "  $branch (worktree)"
      done
    fi

    (( ${#prunable[@]} == 0 )) && continue

    msg_info "$display_name - ${#prunable[@]} merged branch(es):"

    for branch in "${prunable[@]}"; do
      if [[ "$delete" == true ]]; then
        if git -C "$repo_path" branch -d "$branch" >/dev/null 2>&1; then
          msg_info "  deleted: $branch"
          total_deleted=$((total_deleted + 1))
        else
          msg_error "  failed to delete: $branch"
        fi
      else
        msg_info "  $branch"
      fi

      total_prunable=$((total_prunable + 1))
    done
  done

  # --- Summary ---
  printf "\n"
  if [[ "$delete" == true ]]; then
    msg_info "Deleted $total_deleted branch(es)"
  else
    msg_info "Found $total_prunable prunable branch(es)"
  fi

  if (( total_worktree_skips > 0 )); then
    msg_info "$total_worktree_skips branch(es) protected (linked to worktrees)"
  fi

  return 0
}
