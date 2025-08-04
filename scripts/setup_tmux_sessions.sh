#!/bin/bash
# setup_tmux_sessions.sh
# Create tmux sessions for directories in REPOSITORIES_ROOT.
# Each directory is assumed to be a worktree for a particular repository.
# The session has a defined structure and can be modified.

# Prerequisites
# Requires tmux
echo "======================================"
if ! command -v tmux >/dev/null 2>&1; then
  echo "Tmux is not installed" >&2
  return 1
fi

REPOSITORIES_ROOT="$HOME/personal_repos"
SUCCESS_COUNT=0
TOTAL_COUNT=0

if [[ ! -d $REPOSITORIES_ROOT ]]; then

  printf '[ERROR] Repository location does not exist: %s\n' "$REPOSITORIES_ROOT" >&2
  return 1

fi

shopt -s nullglob dotglob
for repo_path in "$REPOSITORIES_ROOT"/*/; do
  basename_path=$(basename "$repo_path")
  repo_path=${repo_path%/}
  echo
  echo "--------------------------------------"
  echo "Repository name: $basename_path"
  echo "Repository path: $repo_path"
  echo "--------------------------------------"

  TOTAL_COUNT=$((TOTAL_COUNT + 1))

  # Check directory is a repository
  if ! git -C "$repo_path" rev-parse --git-dir >/dev/null 2>&1; then
    echo "Skipping $basename_path (not a git repository)"
    continue
  fi

done

echo
echo "Summary: $SUCCESS_COUNT/$TOTAL_COUNT repositories processed successfully"
[[ $SUCCESS_COUNT -eq $TOTAL_COUNT ]]

echo "======================================"

#SESSION_NAME="${REPOSITORIES_ROOT}_session"
SESSION_NAME="session"

#tmux new-session -d -s "$SESSION_NAME" -c "$REPOSITORIES_ROOT"
#
## Name window 1 (editing)
#tmux rename-window -t "$SESSION_NAME:0" 'editing'
#
## Create window 2 (split vertical, both panes in $REPOSITORIES_ROOT)
#tmux new-window -t "$SESSION_NAME:2" -n 'dev' -c "$REPOSITORIES_ROOT"
#tmux split-window -v -t "$SESSION_NAME:2" -c "$REPOSITORIES_ROOT"
#
## Create window 3 (for cluster login, placeholder)
#tmux new-window -t "$SESSION_NAME:3" -n 'cluster'

# Attach to the session
#tmux attach-session -t "$SESSION_NAME"
