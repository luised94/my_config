#!/bin/bash

REPOSITORY_PATH="$HOME/my_config"
echo "$REPOSITORY_PATH"
SESSION_NAME="${REPOSITORY_PATH}_session"

tmux new-session -d -s "$SESSION_NAME" -c "$REPO_PATH"

# Name window 1 (editing)
tmux rename-window -t "$SESSION_NAME:1" 'editing'

# Create window 2 (split vertical, both panes in $REPO_PATH)
tmux new-window -t "$SESSION_NAME:2" -n 'dev' -c "$REPO_PATH"
tmux split-window -v -t "$SESSION_NAME:2" -c "$REPO_PATH"

# Create window 3 (for cluster login, placeholder)
tmux new-window -t "$SESSION_NAME:3" -n 'cluster'

# Attach to the session
tmux attach-session -t "$SESSION_NAME"
