#!/bin/bash
# setup_tmux_sessions.sh
# Create tmux sessions for directories in REPOSITORIES_ROOT.
# Each directory is assumed to be a worktree for a particular repository.
# The session has a defined structure and can be modified.
# for names to appear complete: set-option -g status-left-length 60

# Prerequisites
# Requires tmux
echo "========== Start: ${BASH_SOURCE[0]} =========="
if ! command -v tmux >/dev/null 2>&1; then
  echo "Tmux is not installed" >&2
  return 1
fi

REPOSITORIES_ROOT="$HOME/personal_repos"

# Define repos to ignore manually
# Refer to my_config/docs/scripts_tmux.qmd | ## 2025-08-05 ### Session 2
# @QUES Use find on directories with mapfile? See git_clone_repos_from_username.sh
IGNORE_REPOS=("explorations" "lab_utils" "my_config" "exercises")


echo "--- Script parameters ---"
echo "REPOSITORIES_ROOT: ${REPOSITORIES_ROOT}"
echo "Ignore repos: "
printf '%s\n' "${IGNORE_REPOS[@]}"
echo "-------------------------"

# In your loop
SUCCESS_COUNT=0
IGNORE_COUNT=0
DUPLICATE_COUNT=0
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

  # Ignore repos: mostly meant for skipping main repos, defined manually
  # Using printf and grep for exact matching
  if printf '%s\n' "${IGNORE_REPOS[@]}" | grep -qxF "$basename_path"; then
    IGNORE_COUNT=$((IGNORE_COUNT + 1))
    echo "Repo \"$basename_path\" is in IGNORE_REPOS. Skipping..."
    continue
  fi

  if tmux has-session -t "$session_name" 2>/dev/null; then
    DUPLICATE_COUNT=$((DUPLICATE_COUNT + 1))
    echo "Session \"$session_name\" already exists, skipping"
    continue
  fi

  # Check directory is a repository
  if ! git -C "$repo_path" rev-parse --git-dir >/dev/null 2>&1; then
    echo "Skipping \"$basename_path\" (not a git repository)"
    continue
  fi


  # Tmux session creation logic
  tmux new-session -d -s "$session_name" -c "$repo_path"
  tmux rename-window -t "$session_name:0" 'editing'
  tmux new-window -t "$session_name:1" -n 'dev' -c "$repo_path"
  tmux new-window -t "$session_name:2" -n 'docs' -c "$repo_path"
  #echo "tmux split-window -v -t "$session_name:2" -c "$repo_path""

  SUCCESS_COUNT=$((SUCCESS_COUNT + 1))

done

echo
echo "Summary: $SUCCESS_COUNT/$TOTAL_COUNT repositories processed successfully"
echo "IGNORED: $IGNORE_COUNT/$TOTAL_COUNT repos ignored"
echo "DUPLICATES: $DUPLICATE_COUNT/$TOTAL_COUNT repos were duplicates"
#[[ $SUCCESS_COUNT -eq $TOTAL_COUNT ]]

echo "========== End: ${BASH_SOURCE[0]} =========="
