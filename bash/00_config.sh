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
MC_DROPBOX_SUBPATH="MIT Dropbox/Luis Martinez"

# Arrays for Shell Management
# --- Required Binaries ---
# NOTE:
#  Editors (nvim, vim), browsers and wsl/windows binaries are NOT listed here because they are handled
# dynamically by MC_DEFAULT_EDITORS, MC_DEFAULT_BROWSERS in 01_activate.sh.
# WSL_DEPS are verified in 04_verify.sh.
MC_REQUIRED_PROGS=(
    # Core Utilities
    "git"
    "curl"
    "wget"
    "fzf"
    "tput"
    #"ripgrep"
    #"jq"

    # Languages & Runtimes
    #"python3"
    #"uv"
    #"node"
    #"npm"
    #"R"

    # Compiled Language Toolchain
    #"gcc"
    #"make"
    #"cmake"
)

MC_DEFAULT_EDITORS=("nvim" "vim" "nano" "vi")

# --- WSL Specific Dependencies ---
# WSL Specific Dependencies (Binaries or Absolute Paths)
# Only checked if running inside WSL.
# system32 binaries already added to path automatically.
MC_WSL_DEPS=(
    "cmd.exe"
    "powershell.exe"
    "wslpath"
    "clip.exe"
)

# Browsers are not in $PATH by default, so we use absolute paths.
MC_DEFAULT_BROWSERS=(
    "/mnt/c/Program Files (x86)/BraveSoftware/Brave-Browser/Application/brave.exe"
    "/mnt/c/Program Files/BraveSoftware/Brave-Browser/Application/brave.exe"
    "/mnt/c/Program Files/Mozilla Firefox/firefox.exe"
    "/mnt/c/Program Files/Google/Chrome/Application/chrome.exe"
    "/mnt/c/Program Files (x86)/Microsoft/Edge/Application/msedge.exe"
)

# --- Symlink Management ---
# Format: "Source_Path:Target_Path"
# Used by 04_verify.sh to validate and 00_bootstrap.sh (future) to create.
# NOTE: Use $HOME instead of ~ to ensure safe expansion.
MC_SYMLINKS=(
    # Bash Configuration
    "$MC_ROOT/dotfiles/bashrc.sh:$HOME/.bashrc"

    # Neovim Configuration
    # TODO: Verify source path below matches your repo structure
    "$MC_ROOT/nvim:$HOME/.config/nvim"
)

MC_SHELL_OPTIONS=(
    "histappend"
    "checkwinsize"
)

MC_ADDITIONAL_PATHS=(
    "/opt/zig"
)

MC_ENV_VARS=(
    #"BROWSER=/mnt/c/Program Files (x86)/BraveSoftware/Brave-Browser/Application/brave.exe"
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
    "cdwin=cd \"\$MC_DROPBOX_PATH\""
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
    "*.log" "*.git" "*.tmp" "*.bak" "*.swp" "*.swo" "*.pyc" "*.pyo" "*.o" "*.so"
    "*.a" "*.class" ".DS_Store" "Thumbs.db" "*repository_aggregate.md"
    "*.gitignore" "*.Rprofile" "*renv.lock"
)

MC_VIMALL_FILE_LIMIT=150
# ------------------------------------------------------------------------------
# [MC_02_COMPUTED_ENV]: Logic for system detection
# ------------------------------------------------------------------------------

# OS & WSL Detection
_MC_OS_TYPE=$(uname -s)
_MC_WSL_DISTRO="$WSL_DISTRO_NAME"

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

# ------------------------------------------------------------------------------
# [MC_99_EXTENSIONS]: Extensions configurations
# ------------------------------------------------------------------------------
MC_EXTENSIONS_DIR="$HOME/.config/mc_extensions/"
_MC_SKIPPED_EXTENSIONS=()
_MC_LOADED_EXTENSIONS=()
_MC_FAILED_EXTENSIONS=()

# ------------------------------------------------------------------------------
# Exports for subshells and scripts
# ------------------------------------------------------------------------------
export MC_ROOT MC_REPOS_ROOT MC_VERBOSITY _MC_OS_TYPE _MC_WSL_DISTRO
export _MC_COLOR_RESET _MC_COLOR_ERROR _MC_COLOR_WARN _MC_COLOR_INFO _MC_COLOR_DEBUG
