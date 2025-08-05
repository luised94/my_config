#!/bin/bash
# setup_tmux_sessions.sh
# Create tmux sessions for directories in REPOSITORIES_ROOT.
# Each directory is assumed to be a worktree for a particular repository.
# The session has a defined structure and can be modified.
# for names to appear complete: set-option -g status-left-length 60
# Attach to the session
# tmux attach-session -t "$session_name"
# Switch sessions
# Ctrl+B s
# Ctrl+B ( OR Ctrl+B )
# switch-client -t <session_name>
# tmux attach -t <session_name>
# tmux kill-session -t <session_name>
# tmux kill-server

# Prerequisites
# Requires tmux
echo "========== Start: ${BASH_SOURCE[0]} =========="
if ! command -v tmux >/dev/null 2>&1; then
  echo "Tmux is not installed" >&2
  return 1
fi

REPOSITORIES_ROOT="$HOME/personal_repos"
IGNORE_REPOS=("main-project" "legacy-repo" "exercises")
#IGNORE_REPOS=("main-project" "legacy-repo" "exercises")
echo "Ignore repos: ${IGNORE_REPOS[@]}"

# In your loop
SUCCESS_COUNT=0
TOTAL_COUNT=0

if [[ ! -d $REPOSITORIES_ROOT ]]; then

  printf '[ERROR] Repository location does not exist: %s\n' "$REPOSITORIES_ROOT" >&2
  return 1

fi

shopt -s nullglob dotglob
repo_paths=( "$REPOSITORIES_ROOT"/*/ )
if (( ${#repo_paths[@]} == 0 )); then

  printf 'No repositories found under %s\n' "$REPOSITORIES_ROOT" >&2
  return 0

fi

for repo_path in "${repo_paths[@]}"; do
  TOTAL_COUNT=$((TOTAL_COUNT + 1))
  basename_path=$(basename "$repo_path")
  repo_path=${repo_path%/}
  session_name=$( echo $basename_path | sed 's/-/>/' )
  echo
  echo "--------------------------------------"
  echo "Repository name: $basename_path"
  echo "Repository path: $repo_path"
  echo "Tmux session name: $session_name"
  echo "--------------------------------------"
  #if (( $TOTAL_COUNT == 5 )); then
  #  printf "Reached count limit for testing: %s\n" "$TOTAL_COUNT" >&2
  #  break
  #fi

  # Ignore repos: mostly meant for skipping main repos
  if [[ " ${IGNORE_REPOS[@]} " =~ " ${basename_path} " ]]; then
      echo "Repo \"$basename_path\" is in IGNORE_REPOS. Skipping..."
      continue
  fi

  if tmux has-session -t "$session_name" 2>/dev/null; then
      echo "Session \"$session_name\" already exists, skipping"
      continue
  fi

  # Check directory is a repository
  if ! git -C "$repo_path" rev-parse --git-dir >/dev/null 2>&1; then
    echo "Skipping \"$basename_path\" (not a git repository)"
    continue
  fi

  echo "tmux new-session -d -s "$session_name" -c "$repo_path""
  echo "tmux rename-window -t "$session_name:0" 'editing'"
  echo "tmux new-window -t "$session_name:2" -n 'dev' -c "$repo_path""
  echo "tmux split-window -v -t "$session_name:2" -c "$repo_path""
  echo "tmux new-window -t "$session_name:3" -n 'cluster'"

  # Tmux session creation logic
  tmux new-session -d -s "$session_name" -c "$repo_path"
  #tmux rename-window -t "$session_name:0" 'editing'
  #tmux new-window -t "$session_name:2" -n 'dev' -c "$repo_path"
  #tmux split-window -v -t "$session_name:2" -c "$repo_path"
  #tmux new-window -t "$session_name:3" -n 'cluster' -c "$repo_path"

  SUCCESS_COUNT=$((SUCCESS_COUNT + 1))

done

echo
echo "Summary: $SUCCESS_COUNT/$TOTAL_COUNT repositories processed successfully"
[[ $SUCCESS_COUNT -eq $TOTAL_COUNT ]]

echo "========== End: ${BASH_SOURCE[0]} =========="
