#!/bin/bash

# Create worktree for branch at default root location
# Tests:
# new_worktree
# new_worktree potato
# new_worktree <branch_in_repo>
# new_worktree <branch_in_repo> # after first run
new_worktree() {

  # --- basic preflight check ---
  if ! git rev-parse --is-inside-work-tree >/dev/null 2>&1; then

    printf 'ERROR: not inside a git repository (cwd: %s)\n' "$(pwd)" >&2
    return 1

  fi

  local branch_name=$1
  local worktree_root=${2:-$HOME/personal_repos/}


  if [[ -z $branch_name ]]; then

    printf 'Usage: %s <branch-name> [<worktree-root>]\n' "${FUNCNAME[0]}" >&2
    return 1

  fi

  if ! git show-ref --verify --quiet "refs/heads/$branch_name"; then

    printf 'ERROR: branch "%s" does not exist\n' "$branch_name" >&2
    printf 'Create it with: git checkout -b %s\n' "$branch_name" >&2
    return 1

  fi

  # --- build destination ---
  local name_delimiter="-"
  local repository_name; repository_name=$(git rev-parse --show-toplevel | awk -F/ '{print $NF}')

  destination_path=${worktree_root}${repository_name}${name_delimiter}${branch_name}

  if [[ -e $destination_path ]]; then

    printf 'ERROR: path already exists: %s\n' "$destination_path" >&2
    return 1

  fi

  # --- create worktree ---
  mkdir -p -- "$worktree_root" || return
  printf "Creating workpath tree: %s\n" "$destination_path"
  git worktree add "${destination_path}" "${branch_name}"

}

sync_repos() {
  # Prerequisites
  if ! command -v git >/dev/null 2>&1; then
    echo "Git is not installed" >&2
    return 1
  fi

  local repositories_root=${1:-$HOME/personal_repos}
  if [[ ! -d $repositories_root ]]; then

    printf '[ERROR] Repository location does not exist: %s\n' "$repositories_root" >&2
    return 1

  fi

  # Use native glob instead of 'find': one less process, safe with spaces/new-lines, and nullglob prevents literal * when no dirs exist.
  shopt -s nullglob dotglob
  local success_count=0 total_count=0 stash_count=0
  local repo_paths=( "$repositories_root"/*/ )

  # Early exit if no sub-directories were found
  if (( ${#repo_paths[@]} == 0 )); then

      printf 'No repositories found under %s\n' "$repositories_root" >&2
      return 0

  fi

  for repo_path in "${repo_paths[@]}"; do
    repo_path=${repo_path%/}
    total_count=$((total_count + 1))
    echo
    echo "==============================="
    echo "Repository: $(basename "$repo_path")"
    echo "==============================="

    # Check directory is a repository
    if ! git -C "$repo_path" rev-parse --git-dir >/dev/null 2>&1; then

        echo "Skipping $(basename "$repo_path") (not a git repository)"
        continue

    fi

    # Stash changes if any to prevent loss
    if ! git -C "$repo_path" diff-index --quiet HEAD 2>/dev/null; then

      echo "Stashing local changes..."
      stash_count=$((stash_count + 1))
      git -C "$repo_path" stash push -u -m "wip before pull $(date -Iseconds)"

    fi

    # Pull and track success
    echo "Pulling latest changes..."
    if git -C "$repo_path" pull --ff-only; then

      success_count=$((success_count + 1))
      echo "SUCCESS!"

    else

      echo "[**FAILED**]"

    fi

  done

    echo
    echo "Summary: $success_count/$total_count repositories processed successfully"
    echo "Summary: $stash_count/$total_count repositories have stashed changes"
    [[ $success_count -eq $total_count ]]
}
##########################################
# Must be inspected and simplified greatly.
##########################################
#[[ -z "$_BASH_UTILS_INITIALIZED" ]] && source "${BASH_SOURCE%/*}/../init.sh"

# Standard output formatting symbols for CLI feedback
# Should just be the actual words. No need for output...
#declare -A OUTPUT_SYMBOLS=(
#    ["START"]="=== "    # Indicates start of operation
#    ["PROCESSING"]=">>> " # Shows ongoing process
#    ["SUCCESS"]="[+] "   # Positive completion
#    ["ERROR"]="[!] "     # Error condition
#    ["WARNING"]="[?] "   # Warning or attention needed
#    ["INFO"]="[*] "      # General information
#    ["DONE"]="=== "      # Operation completion
#)
#
#display_message() {
#    local type="$1"
#    local message="$2"
#
#    # Check if the type exists as a key in the array
#    if [[ -v "OUTPUT_SYMBOLS[$type]" ]]; then # -v checks if the variable exists
#        echo "${OUTPUT_SYMBOLS[$type]}$message"
#    else
#        # Handle the error: Provide a default message or log an error
#        echo "[UNKNOWN MESSAGE TYPE] $message (Type: $type)" >&2 # Output to stderr
#        # OR:
#        # echo "[ERROR] Invalid message type: $type" >&2
#        # return 1 # Return an error code if you want to stop execution
#    fi
#}
#
#validate_dir_is_git_repo() {
#    if ! git rev-parse --is-inside-work-tree > /dev/null 2>&1; then
#        display_message "ERROR" "This script must be run from a git repository."
#        exit 1
#    fi
#    return 0
#}
#
#has_uncommitted_changes() {
#    validate_dir_is_git_repo
#    # Check if there are any changes staged or unstaged
#    if [[ -n $(git status --porcelain) ]]; then
#        return 0 # Has uncommitted changes
#    else
#        return 1 # No uncommitted changes
#    fi
#}
#
#display_changes() {
#    validate_dir_is_git_repo
#    local branch_name="$1"
#    local staged=false
#    local unstaged=false
#
#    if [[ -n $(git diff --cached --name-status) ]]; then # check for staged
#        staged=true
#    fi
#    if [[ -n $(git diff --name-status) ]]; then # check for unstaged
#        unstaged=true
#    fi
#    
#    if "$staged" || "$unstaged"; then
#        display_message "WARNING" "Local branch '$branch_name' has the following changes:"
#        if "$staged"; then
#            echo "Staged changes:"
#            git diff --cached --stat
#        fi
#        if "$unstaged"; then
#            echo "Unstaged changes:"
#            git diff --stat
#        fi
#    else
#        display_message "INFO" "No changes found on branch '$branch_name'."
#    fi
#}
#
#is_remote_reachable() {
#    local remote="${1:-origin}"
#    local timeout_seconds="${2:-5}" # Default timeout of 5 seconds
#
#    if ! timeout "$timeout_seconds" git ls-remote --exit-code "$remote" > /dev/null 2>&1; then
#        display_message ERROR "Remote '$remote' is not reachable (timeout after $timeout_seconds seconds). Check your network connection or remote configuration."
#        return 1
#    fi
#    return 0
#}
#
#branch_exists() {
#    local branch_name="$1"
#    local remote="${2:-false}" # Default to local branch check
#    if "$remote"; then
#        git show-ref --verify --quiet "refs/remotes/origin/$branch_name"
#    else
#        git show-ref --verify --quiet "refs/heads/$branch_name"
#    fi
#}
#
#sync_all_branches() {
#    validate_dir_is_git_repo || return 1
#    is_remote_reachable || return 1
#
#    local dry_run=false
#    while [[ $# -gt 0 ]]; do
#        case "$1" in
#            -n|--dry-run)
#                dry_run=true
#                shift
#                ;;
#            *)
#                break
#                ;;
#        esac
#    done
#
#
#    display_message "START" "Syncing all remote branches (Dry Run: ${dry_run})"
#
#    git fetch --all --prune
#
#    for remote in $(git remote); do
#        for branch in $(git branch -r | grep "^$remote/"); do
#            branch_name=$(echo "$branch" | sed "s/^$remote\///")
#
#            if ! git show-ref --verify --quiet "refs/heads/$branch_name"; then
#                if "$dry_run"; then
#                    display_message "INFO" "(Dry Run) Would create and checkout local branch '$branch_name' tracking '$branch'"
#                else
#                    git checkout --track "$branch"
#                    display_message "PROCESSING" "Created and checked out local branch '$branch_name' tracking '$branch'"
#                fi
#            else
#                git checkout "$branch_name"
#
#                if has_uncommitted_changes; then
#                    display_changes $branch
#                    display_message "ERROR" "Local branch '$branch_name' has uncommitted changes. Please commit or stash them before syncing."
#                    continue # Skip to the next branch
#                fi
#
#                if [[ $(git rev-list HEAD...@{upstream} --count) -gt 0 ]]; then
#                    if "$dry_run"; then
#                        display_message "INFO" "(Dry Run) Would pull changes for '$branch_name' from '$branch'"
#                    else
#                        git pull --ff-only "$remote" "$branch_name"
#                        if [[ $? -ne 0 ]]; then
#                            display_message "WARNING" "Pull failed for '$branch_name'. Local changes might exist. Consider stashing or committing."
#                        else
#                            display_message "SUCCESS" "Updated local branch '$branch_name' from '$branch'"
#                        fi
#                    fi
#                else
#                    display_message "INFO" "Local branch '$branch_name' is up-to-date."
#                fi
#            fi
#        done
#    done
#
#    display_message "SUCCESS" "Finished updating local branches."
#}
#
#new_branch() {
#    validate_dir_is_git_repo || return 1
#    is_remote_reachable || return 1
#
#    local branch_name="$1"
#    local base_branch="${2:-main}"
#    local dry_run=false
#
#    while [[ $# -gt 0 ]]; do
#        case "$1" in
#            -n|--dry-run)
#                dry_run=true
#                shift
#                ;;
#            -b|--base)
#                base_branch="$2"
#                shift 2
#                ;;
#            *)
#                branch_name="$1"
#                shift
#                ;;
#        esac
#    done
#
#    if [[ -z "$branch_name" ]]; then
#        display_message ERROR "Usage: new_branch <branch-name> [-b base_branch] [-n|--dry-run]"
#        return 1
#    fi
#
#    if has_uncommitted_changes; then
#        display_changes "current"
#        display_message ERROR "Please commit or stash changes before creating new branch"
#        return 1
#    fi
#
#    if branch_exists "$branch_name"; then
#        display_message ERROR "Branch '$branch_name' already exists locally"
#        return 1
#    fi
#
#    if branch_exists "$branch_name" true; then
#        display_message ERROR "Branch '$branch_name' already exists remotely"
#        return 1
#    fi
#
#    if "$dry_run"; then
#        display_message INFO "Would create new branch '$branch_name' from '$base_branch'"
#        return 0
#    fi
#
#    display_message START "Creating new branch '$branch_name' from '$base_branch'"
#
#    git checkout "$base_branch" || {
#        display_message ERROR "Failed to checkout $base_branch"
#        return 1
#    }
#
#    git pull origin "$base_branch" || {
#        display_message ERROR "Failed to update $base_branch"
#        return 1
#    }
#
#    if git checkout -b "$branch_name"; then
#        if git push -u origin "$branch_name"; then
#            display_message SUCCESS "Branch '$branch_name' created and pushed to origin"
#            return 0
#        else
#            display_message ERROR "Failed to push branch '$branch_name' to origin"
#            return 1
#        fi
#    else
#        display_message ERROR "Failed to create branch '$branch_name'"
#        return 1
#    fi
#}
#
#sync_after_merge() {
#    validate_dir_is_git_repo || return 1
#    is_remote_reachable || return 1
#
#    local dry_run=false
#
#    while [[ $# -gt 0 ]]; do
#        case "$1" in
#            -n|--dry-run)
#                dry_run=true
#                shift
#                ;;
#            *)
#                break
#                ;;
#        esac
#    done
#
#    local current_branch=$(git rev-parse --abbrev-ref HEAD)
#
#    display_message START "Syncing branches after merge"
#
#    if "$dry_run"; then
#        display_message INFO "Would update main branch"
#    else
#        git checkout main || {
#            display_message ERROR "Failed to checkout main"
#            return 1
#        }
#        git pull origin main || {
#            display_message ERROR "Failed to update main"
#            git checkout "$current_branch"
#            return 1
#        }
#    fi
#
#    local branches=$(git for-each-ref --format='%(refname:short)' refs/heads/ | grep -v '^main$')
#
#    for branch in $branches; do
#        git checkout "$branch" || {
#            display_message ERROR "Failed to checkout branch '$branch'"
#            continue
#        }
#
#        if has_uncommitted_changes; then
#            display_changes "$branch"
#            display_message WARNING "Skipping '$branch' due to uncommitted changes"
#            continue
#        fi
#
#        if ! git rev-parse --quiet --verify "HEAD@{upstream}"; then
#            display_message WARNING "Skipping '$branch' because it does not track a remote branch."
#            continue
#        fi
#
#        if "$dry_run"; then
#            display_message INFO "Would rebase '$branch' on main"
#            continue
#        fi
#
#        display_message PROCESSING "Rebasing '$branch'"
#        if git rebase main; then
#            display_message SUCCESS "Rebased '$branch' on main"
#        else
#            display_message ERROR "Rebase failed for '$branch'. Aborting rebase."
#            git rebase --abort
#            return 1
#        fi
#    done
#
#    if ! "$dry_run"; then
#        git checkout "$current_branch" || {
#            display_message ERROR "Failed to return to original branch '$current_branch'"
#            return 1
#        }
#    fi
#
#    display_message DONE "Branch synchronization (without pushing) complete"
#}
#
#push_all_branches() {
#    validate_dir_is_git_repo || return 1
#    is_remote_reachable || return 1
#
#    local dry_run=false
#
#    while [[ $# -gt 0 ]]; do
#        case "$1" in
#            -n|--dry-run)
#                dry_run=true
#                shift
#                ;;
#            *)
#                break
#                ;;
#        esac
#    done
#    display_message START "Pushing all local branches to remote"
#    local current_branch=$(git rev-parse --abbrev-ref HEAD)
#    local branches=$(git for-each-ref --format='%(refname:short)' refs/heads/ | grep -v '^main$')
#    for branch in $branches; do
#        git checkout "$branch" || {
#            display_message ERROR "Failed to checkout branch '$branch'"
#            continue
#        }
#        if "$dry_run"; then
#            display_message INFO "Would push branch '$branch' to remote"
#            continue
#        fi
#        display_message PROCESSING "Pushing '$branch' to remote"
#        git push --force-with-lease origin "$branch" || {
#            display_message WARNING "Failed to push '$branch'"
#            continue
#        }
#        display_message SUCCESS "Pushed '$branch' to remote"
#    done
#    git checkout "$current_branch" || {
#            display_message ERROR "Failed to return to original branch '$current_branch'"
#            return 1
#        }
#    display_message DONE "Push complete"
#}
#
#list_merged_branches() {
#    validate_dir_is_git_repo || return 1
#    is_remote_reachable || return 1
#
#    display_message START "Finding merged branches"
#
#    local merged_branches=$(git branch --merged main | grep -v "^\*" | grep -v "main")
#
#    if [[ -z "$merged_branches" ]]; then
#        display_message INFO "No merged branches found."
#        return 0
#    fi
#
#    display_message INFO "The following branches are merged into main and could be deleted:"
#    echo "$merged_branches"
#
#    display_message DONE "Finished finding merged branches"
#    echo "$merged_branches" # Output the branches for the next function to use
#}
#
#delete_merged_branches() {
#    validate_dir_is_git_repo || return 1
#    is_remote_reachable || return 1
#
#    local dry_run=false
#    local really_force=false
#
#    while [[ $# -gt 0 ]]; do
#        case "$1" in
#            -n|--dry-run)
#                dry_run=true
#                shift
#                ;;
#            --really-force)
#                really_force=true
#                shift
#                ;;
#            *)
#                break
#                ;;
#        esac
#    done
#
#    local merged_branches="$@" # Get the branches from the previous function
#
#    if [[ -z "$merged_branches" ]]; then
#        display_message INFO "No branches provided to delete."
#        return 0
#    fi
#
#    if ! "$really_force"; then
#        display_message WARNING "You are about to delete the following branches:"
#        echo "$merged_branches"
#        read -p "Are you sure you want to proceed? (y/N) " -n 1 -r
#        echo
#        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
#            display_message INFO "Deletion cancelled."
#            return 0
#        fi
#    fi
#
#    display_message START "Deleting merged branches"
#
#    echo "$merged_branches" | while read branch; do
#        if [[ -n "$branch" ]]; then
#            if "$dry_run"; then
#                display_message INFO "Would delete branch: $branch"
#            else
#                if "$really_force"; then
#                    git branch -D "$branch"
#                    if [[ $? -eq 0 ]]; then
#                        git push origin --delete "$branch"
#                        if [[ $? -eq 0 ]]; then
#                            display_message SUCCESS "Force deleted branch: $branch"
#                        else
#                            display_message WARNING "Failed to delete remote branch: $branch. Local branch force deleted."
#                        fi
#                    else
#                        display_message WARNING "Failed to force delete local branch: $branch."
#                    fi
#                else
#                    git branch -d "$branch"
#                    if [[ $? -eq 0 ]]; then
#                        git push origin --delete "$branch"
#                        if [[ $? -eq 0 ]]; then
#                            display_message SUCCESS "Deleted branch: $branch"
#                        else
#                            display_message WARNING "Failed to delete remote branch: $branch. Local branch deleted."
#                        fi
#                    else
#                        display_message WARNING "Failed to delete local branch: $branch."
#                    fi
#                fi
#            fi
#        fi
#    done
#    display_message DONE "Deletion process finished"
#}
