#!/bin/bash

FILES_TO_TEST=(
  "00_config.sh"
  "10_message.sh"
)

# Set the appropriate root directory.
if [[ -n "$TMUX" ]]; then
  _session=$(tmux display-message -p '#S')

  if [[ "$_session" =~ ^my_config\>(.*) ]]; then
    _branch=${BASH_REMATCH[1]}
    _possible_root="$HOME/personal_repos/my_config-${_branch}/bash"

    if [[ -d "$_possible_root" ]]; then
      BASH_UTILS_ROOT="$_possible_root"
    elif [[ $- == *i* ]]; then # Only warn if the shell is interactive
      printf "[WARN] Worktree config not found: %s\n" "$_possible_root" >&2
    fi

  fi

  unset _session _branch _possible_root

fi

# Set default and clean up trailing slashes
BASH_UTILS_ROOT="${BASH_UTILS_ROOT:-$HOME/personal_repos/my_config/bash}"
BASH_UTILS_ROOT="${BASH_UTILS_ROOT%/}"

if [[ ! -d "$BASH_UTILS_ROOT" && $- == *i* ]]; then
  printf "[ERROR] BASH_UTILS_ROOT does not exist: %s\n" "$BASH_UTILS_ROOT" >&2

fi

echo "BASH ROOT: $BASH_UTILS_ROOT"

for file in "${FILES_TO_TEST[@]}"; do
  echo "Sourcing $file"
  filepath="$BASH_UTILS_ROOT/$file"

  if [[ ! -f $filepath ]]; then
    echo "File $filepath does not exist."
    exit 1

  fi

  if ! source "$filepath"; then
    printf "[ERROR] Failed to source %s (exit code: %s)" "${filepath}" "$?" >&2
    continue

  fi

  echo "Sourced $file !"

done

echo "DONE!"
