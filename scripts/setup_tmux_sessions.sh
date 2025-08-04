#!/bin/bash

REPOSITORY_PATH="$HOME/my_config"
echo "$REPOSITORY_PATH"
#SESSION_NAME="${REPOSITORY_PATH}_session"
SESSION_NAME="session"

tmux new-session -d -s "$SESSION_NAME" -c "$REPOSITORY_PATH"

# Name window 1 (editing)
tmux rename-window -t "$SESSION_NAME:0" 'editing'

# Create window 2 (split vertical, both panes in $REPOSITORY_PATH)
tmux new-window -t "$SESSION_NAME:2" -n 'dev' -c "$REPOSITORY_PATH"
tmux split-window -v -t "$SESSION_NAME:2" -c "$REPOSITORY_PATH"

# Create window 3 (for cluster login, placeholder)
tmux new-window -t "$SESSION_NAME:3" -n 'cluster'

# Attach to the session
#tmux attach-session -t "$SESSION_NAME"
