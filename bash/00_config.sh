#!/usr/bin/env bash
# ==============================================================================
# File: 00_config.sh
# Project: my_config
# Description: High-performance, modular shell environment configuration.
# ==============================================================================

# ------------------------------------------------------------------------------
# [MC_01_USER_PREFS]: Static lists and manual settings
# ------------------------------------------------------------------------------

# General Preferences
MC_VERBOSITY=3
MC_HIST_CONTROL="ignoreboth"
MC_HIST_SIZE=1000
MC_HIST_FILESIZE=2000
MC_COLOR_SUPPORT=1
MC_PS1='\u@\h:\w\$ '

# Arrays for Shell Management
MC_REQUIRED_PROGS=(
    "git"
    "tmux"
    "nvim"
    "fzf"
    "tput"
)

MC_DEFAULT_EDITORS=(
    "nvim"
    "vim"
)

MC_SHELL_OPTIONS=(
    "histappend"
    "checkwinsize"
)

MC_FUNCTION_FILES=(
    "logging_utils.sh"
    "file_operations.sh"
    "vim_helpers.sh"
    "view_files_in_browser.sh"
    "git_automations.sh"
    "directory_tree.sh"
)

MC_ADDITIONAL_PATHS=(
    "/opt/zig"
)

MC_ENV_VARS=(
    "BROWSER=/mnt/c/Program Files (x86)/BraveSoftware/Brave-Browser/Application/brave.exe"
    "GIT_EDITOR=nvim"
    "MANPAGER=nvim +Man!"
    "R_HOME=/usr/local/bin/R"
    "R_LIBS_USER=/opt/R/library/"
)

MC_ALIASES=(
    # --- Basic ---
    "l=ls -CF"
    "la=ls -A"
    "ll=ls -alF"
    # --- Languages ---
    "R=R --no-save"
    # --- WSL/Windows ---
    "cdwin=cd \"\$DROPBOX_PATH\""
    "explorer=explorer.exe ."
    # --- Git ---
    "ga=git add"
    "gb=git branch"
    "gc=git commit"
    "gcb=git checkout -b"
    "gco=git checkout"
    "gd=git diff"
    "gfap=git fetch --all --prune"
    "gl=git log --oneline --graph --decorate"
    "gm=git merge"
    "gmnff=git merge --no-ff"
    "gpl=git pull"
    "gps=git push"
    "grm=git rebase main"
    "gs=git status"
    "ngd=nvim < <(git diff)"
    "ngda=nvim < <(git diff HEAD)"
    "ngdc=nvim < <(git diff --cached)"
    "nglc=git diff-tree --no-commit-id --name-only -r -z HEAD | xargs -0 nvim"
    # --- Scripts & Lab ---
    "setup_tmux=~/personal_repos/my_config/scripts/tmux_setup_worktree_sessions.sh"
    "edit_bmc_configs=nvim ~/data/*Bel/documentation/*_bmc_config.R"
)

# Consolidation of Exclusion Lists
MC_EXCLUDE_DIRS=(
    ".git" "node_modules" ".next" ".nuxt" ".venv" "venv" "env" "__pycache__"
    "renv" ".Rproj.user" "build" "dist" "target" "out" "bin" "vendor" "deps"
    ".idea" ".vscode" ".cache" "tmp" "temp" "coverage"
)

MC_EXCLUDE_FILES=(
    "*.log" "*.tmp" "*.bak" "*.swp" "*.swo" "*.pyc" "*.pyo" "*.o" "*.so"
    "*.a" "*.class" ".DS_Store" "Thumbs.db" "*repository_aggregate.md"
    "*.gitignore" "*.Rprofile" "*renv.lock"
)

# ------------------------------------------------------------------------------
# [MC_02_COMPUTED_ENV]: Logic for system detection
# ------------------------------------------------------------------------------

# OS & WSL Detection
_MC_OS_TYPE=$(uname -s)
_MC_WSL_DISTRO="$WSL_DISTRO_NAME"


# WSL Specific Windows Discovery (Computed Only)
if [[ -n "$_MC_WSL_DISTRO" ]]; then
    _MC_WIN_USER=$(cmd.exe /C "echo %USERNAME%" 2>/dev/null | tr -d '\r\n')
    _MC_DROPBOX_BASE="/mnt/c/Users/${_MC_WIN_USER}/MIT Dropbox/Luis Martinez"
    [[ ! -d "$_MC_DROPBOX_BASE" ]] && _MC_DROPBOX_BASE="/mnt/c/Users/${_MC_WIN_USER}/Dropbox (MIT)"
fi

# ------------------------------------------------------------------------------
# [MC_03_COLORS]: tput logic with POSIX fallbacks
# ------------------------------------------------------------------------------

_MC_COLOR_RESET=$(tput sgr0 2>/dev/null || printf '\033[0m')

if [ -t 2 ] && [ -n "$TERM" ] && [ "$TERM" != "dumb" ]; then
    _MC_COLOR_ERROR=$(tput setaf 1 2>/dev/null || printf '\033[0;31m')
    _MC_COLOR_WARN=$(tput setaf 3 2>/dev/null || printf '\033[0;33m')
    _MC_COLOR_INFO=$(tput setaf 6 2>/dev/null || printf '\033[0;36m')
    _MC_COLOR_DEBUG=$(tput setaf 8 2>/dev/null || printf '\033[0;90m')

    # Safety check for tput validity
    if printf "%s" "$_MC_COLOR_RESET" | grep -q 'tput: unknown'; then
        _MC_COLOR_ERROR='' _MC_COLOR_WARN='' _MC_COLOR_INFO='' _MC_COLOR_DEBUG=''
    fi
else
    _MC_COLOR_ERROR='' _MC_COLOR_WARN='' _MC_COLOR_INFO='' _MC_COLOR_DEBUG=''
fi

export _MC_OS_TYPE
export _MC_WSL_DISTRO
