# ~/.bashrc: executed by bash(1) for non-login shells.
# If not running interactively, don't do anything
case $- in
  *i*) ;;
    *) return;;
esac
set -o vi # Set vi mode

# MC_ROOT: root directory for sourced bash config files
# When in a tmux session named my_config>BRANCH, uses the worktree path
# ~/personal_repos/my_config-BRANCH/bash if it exists, otherwise falls
# back to the main repo. This allows testing bashrc changes in worktrees.
# TMUX Worktree Root Discovery
if [[ -n "$TMUX" ]]; then
    _MC_TMUX_SESSION=$(tmux display-message -p '#S' 2>/dev/null)

    if [[ "$_MC_TMUX_SESSION" =~ ^my_config\>(.*) ]]; then
        _MC_BRANCH=${BASH_REMATCH[1]}
        _MC_POSSIBLE_ROOT="$HOME/personal_repos/my_config-${_MC_BRANCH}"

        if [[ -d "$_MC_POSSIBLE_ROOT" ]]; then
            MC_ROOT="$_MC_POSSIBLE_ROOT"

        fi

    fi

fi

# Cleanup of trailing slashes for the root
MC_ROOT="${MC_ROOT:-$HOME/personal_repos/my_config}"
MC_ROOT="${MC_ROOT%/}"

if [[ ! -d "$MC_ROOT" && $- == *i* ]]; then
  printf "[ERROR] BASH_UTILS_ROOT does not exist: %s\n" "$MC_ROOT" >&2

fi

export MC_ROOT

# We loop through files in the 'core' directory numbered 00-03
for _file in "${MC_ROOT}"/bash/[0-9][0-9]_*.sh; do
    if [[ -r "$_file" ]]; then
        if ! source "$_file"; then
            # Use raw printf here because the logger might not be loaded yet
            printf "[ERROR] MC Framework failed to source: %s\n" "$_file" >&2
        fi
    fi
done

# Device specific settings.
[[ -f ~/.mc_local ]] && source ~/.mc_local

# Finalize and Report
if [[ $(type -t msg_info) == "function" ]]; then
    # We found the new framework!
    if [[ "$MC_ROOT" == *"-${_MC_BRANCH}" ]]; then
        msg_info "MC Environment: Worktree [$_MC_BRANCH] active."
    else
        msg_info "MC Environment: Main branch active."
    fi
else
    # Fallback for sessions that don't have the new files yet
    # printf "[NOTICE] MC Framework not loaded (using legacy/main)\n"
    : # Do nothing silently
fi

# Clean up local discovery variables
unset _MC_TMUX_SESSION _MC_BRANCH _MC_POSSIBLE_ROOT _file

# Switch to home directory if not in Tmux
if [ -z "$TMUX" ]; then
  cd "$HOME"

fi
