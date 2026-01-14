#!/bin/bash
# ------------------------------------------------------------------------------
# SCRIPT     : tmux_setup_worktree_sessions.sh
# PURPOSE    : Create tmux sessions for git worktree directories.
# USAGE      : ./tmux_setup_worktree_sessions.sh [-r root] [-h]
# NOTES      : Skips main repos (dirs without "-"), existing sessions, non-git dirs
#              Session naming: repo-branch becomes repo>branch
# ------------------------------------------------------------------------------

# --- Help ---
if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
  printf "Usage: %s [-r root] [-h]\n\n" "${0##*/}"
  printf "Create tmux sessions for git worktree directories.\n\n"
  printf "Options:\n"
  printf "  -r ROOT   Repository root directory (default: \$HOME/personal_repos)\n"
  printf "  -h        Show this help message\n\n"
  printf "Notes:\n"
  printf "  - Skips directories without '-' (assumed to be main repos)\n"
  printf "  - Skips directories that already have tmux sessions\n"
  printf "  - Skips non-git directories\n"
  printf "  - Session name: repo-branch becomes repo>branch\n"
  exit 0
fi

# --- MC framework check ---
if ! declare -f _msg >/dev/null 2>&1; then
  echo "[WARN] MC framework not loaded, using basic output" >&2
  msg_info()  { echo "[INFO]  $*"; }
  msg_warn()  { echo "[WARN]  $*" >&2; }
  msg_error() { echo "[ERROR] $*" >&2; }
fi

# --- Configuration ---
REPOS_ROOT="${MC_REPOS_ROOT:-$HOME/personal_repos}"

# --- Parse options ---
OPTIND=1
while getopts ":r:" opt; do
  case $opt in
    r) REPOS_ROOT="$OPTARG" ;;
    :) msg_error "Option -$OPTARG requires an argument"; exit 1 ;;
    \?) msg_error "Invalid option: -$OPTARG"; exit 1 ;;
  esac
done

# --- Prerequisites ---
if ! command -v tmux >/dev/null 2>&1; then
  msg_error "tmux is not installed"
  exit 1
fi

if [[ ! -d "$REPOS_ROOT" ]]; then
  msg_error "Repository root does not exist: $REPOS_ROOT"
  exit 1
fi

# --- Find main repos to ignore (directories without "-") ---
mapfile -t IGNORE_REPOS < <(
  find "$REPOS_ROOT" -maxdepth 1 -mindepth 1 -type d |
  grep -v -- "-" |
  xargs -I{} basename {}
)

msg_info "Repository root: $REPOS_ROOT"
msg_info "Ignoring ${#IGNORE_REPOS[@]} main repo(s)"

# --- Collect directories ---
shopt -s nullglob
REPO_PATHS=("$REPOS_ROOT"/*/)
shopt -u nullglob

if (( ${#REPO_PATHS[@]} == 0 )); then
  msg_warn "No directories found in $REPOS_ROOT"
  exit 0
fi

# --- Process each directory ---
SUCCESS_COUNT=0
SKIP_COUNT=0
DUPLICATE_COUNT=0
TOTAL_COUNT=0

for repo_path in "${REPO_PATHS[@]}"; do
  repo_path="${repo_path%/}"
  repo_name="$(basename "$repo_path")"
  session_name="${repo_name/-/>}"
  TOTAL_COUNT=$((TOTAL_COUNT + 1))

  # Skip main repos
  if printf '%s\n' "${IGNORE_REPOS[@]}" | grep -qxF "$repo_name"; then
    SKIP_COUNT=$((SKIP_COUNT + 1))
    continue
  fi

  # Skip existing sessions
  if tmux has-session -t "$session_name" 2>/dev/null; then
    DUPLICATE_COUNT=$((DUPLICATE_COUNT + 1))
    continue
  fi

  # Warn and skip non-git directories
  if ! git -C "$repo_path" rev-parse --git-dir >/dev/null 2>&1; then
    msg_warn "Not a git repo: $repo_name"
    SKIP_COUNT=$((SKIP_COUNT + 1))
    continue
  fi

  # Create session with 3 windows
  tmux new-session -d -s "$session_name" -c "$repo_path"
  tmux rename-window -t "$session_name:0" 'editing'
  tmux new-window -t "$session_name:1" -n 'dev' -c "$repo_path"
  tmux new-window -t "$session_name:2" -n 'docs' -c "$repo_path"

  msg_info "Created: $session_name"
  SUCCESS_COUNT=$((SUCCESS_COUNT + 1))
done

# --- Summary ---
msg_info "Complete: $SUCCESS_COUNT created, $DUPLICATE_COUNT existing, $SKIP_COUNT skipped (of $TOTAL_COUNT)"

if (( SUCCESS_COUNT == 0 && DUPLICATE_COUNT > 0 )); then
  msg_warn "No new sessions created - all worktrees already have sessions"
fi
