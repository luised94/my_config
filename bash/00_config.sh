#!/usr/bin/env bash
# ==============================================================================
# File: 00_config.sh
# Project: my_config
# Description: Modular shell environment configuration.
#  Loads files in MC_ROOT/bash/ that start with two digits. All other files ignored. ==============================================================================

# ------------------------------------------------------------------------------
# SETTINGS DOCUMENTATION CONVENTION
#   A line beginning with '## ' immediately above a setting documents that
#   setting. A '# shellcheck' directive may sit between the doc line and the
#   assignment. These '##' docs are machine-readable and are surfaced by the
#   mc_config command.
# ------------------------------------------------------------------------------

# ------------------------------------------------------------------------------
# [MC_01_USER_PREFS]: Static lists and manual settings
# ------------------------------------------------------------------------------

# General Preferences
## Logging verbosity 0-5 (higher shows more): 1=error 2=warn 3=info 4=debug 5=trace.
MC_VERBOSITY=3
## Value for bash HISTCONTROL (history de-duplication policy).
# shellcheck disable=SC2034  # consumed by 01_activate.sh
MC_HIST_CONTROL="ignoreboth"
## In-memory bash history size (HISTSIZE).
# shellcheck disable=SC2034  # consumed by 01_activate.sh
MC_HIST_SIZE=1000
## On-disk bash history size (HISTFILESIZE).
# shellcheck disable=SC2034  # consumed by 01_activate.sh
MC_HIST_FILESIZE=2000
## Default interactive prompt string (PS1).
# shellcheck disable=SC2034  # consumed by 01_activate.sh
MC_PS1='\u@\h:\w\$ '
## Dropbox subpath under the Windows profile; used to build MC_DROPBOX_PATH in WSL.
# shellcheck disable=SC2034  # consumed by 02_wsl.sh
MC_DROPBOX_SUBPATH="MIT Dropbox/Luis Martinez"

# Arrays for Shell Management
# --- Required Binaries ---
# NOTE:
#  Editors (nvim, vim), browsers and wsl/windows binaries are NOT listed here because they are handled
# dynamically by MC_DEFAULT_EDITORS, MC_DEFAULT_BROWSERS in 01_activate.sh.
# WSL_DEPS are verified in 04_verify.sh.
## Programs that must be on PATH; verified by mc_verify.
# shellcheck disable=SC2034  # consumed by 04_verify.sh
MC_REQUIRED_PROGS=(
    # Core Utilities
    "git"
    "curl"
    "wget"
    "fzf"
    "tput"
)

## Preferred editors in priority order; the first one found becomes EDITOR.
# shellcheck disable=SC2034  # consumed by 01_activate.sh
MC_DEFAULT_EDITORS=("nvim" "vim" "nano" "vi")

# --- WSL Specific Dependencies ---
# WSL Specific Dependencies (Binaries or Absolute Paths)
# Only checked if running inside WSL.
# system32 binaries already added to path automatically.
## Commands/paths required under WSL; verified by mc_verify when in WSL.
# shellcheck disable=SC2034  # consumed by 04_verify.sh
MC_WSL_DEPS=(
    "cmd.exe"
    "powershell.exe"
    "wslpath"
    "clip.exe"
)

# Browsers are not in $PATH by default, so we use absolute paths.
## Preferred browsers in priority order; the first one found becomes BROWSER.
# shellcheck disable=SC2034  # consumed by 01_activate.sh
MC_DEFAULT_BROWSERS=(
    "/mnt/c/Program Files (x86)/BraveSoftware/Brave-Browser/Application/brave.exe"
    "/mnt/c/Program Files/BraveSoftware/Brave-Browser/Application/brave.exe"
    "/mnt/c/Program Files/Mozilla Firefox/firefox.exe"
    "/mnt/c/Program Files/Google/Chrome/Application/chrome.exe"
    "/mnt/c/Program Files (x86)/Microsoft/Edge/Application/msedge.exe"
)

# --- Symlink Management ---
# Format: "Source_Path:Target_Path"
# Used by 04_verify.sh to validate and bootstrap.sh to create.
# NOTE: Use $HOME instead of ~ to ensure safe expansion.
## Source:target symlink pairs validated by mc_verify (and created by bootstrap).
# shellcheck disable=SC2034  # consumed by 04_verify.sh
MC_SYMLINKS=(
    # Bash Configuration
    "$MC_ROOT/dotfiles/bashrc.sh:$HOME/.bashrc"

    # Vim Configuration
    "$MC_ROOT/dotfiles/vimrc.vim:$HOME/.vimrc"

    # Neovim Configuration
    # TODO: Verify source path below matches your repo structure
    "$MC_ROOT/nvim:$HOME/.config/nvim"
)

## shopt options enabled at shell startup.
# shellcheck disable=SC2034  # consumed by 01_activate.sh
MC_SHELL_OPTIONS=(
    "histappend"
    "checkwinsize"
)

# Extra PATH entries, appended in 01_activate.sh. An entry may use a leading ~
# to mean $HOME (expanded explicitly there); no other variable references are
# expanded, so write absolute paths or ~-relative paths only.
## Extra directories appended to PATH (a leading ~ is expanded to $HOME).
# shellcheck disable=SC2034  # consumed by 01_activate.sh
MC_ADDITIONAL_PATHS=(
    "/opt/zig"
)

## Extra environment variables exported at startup, as NAME=VALUE strings.
# shellcheck disable=SC2034  # consumed by 01_activate.sh
MC_ENV_VARS=(
    #"BROWSER=/mnt/c/Program Files (x86)/BraveSoftware/Brave-Browser/Application/brave.exe"
    "GIT_EDITOR=nvim"
    "MANPAGER=nvim +Man!"
    "R_HOME=/usr/local/bin/R"
    "R_LIBS_USER=/opt/R/library"
)

## Shell aliases defined at startup, as NAME=VALUE strings.
# shellcheck disable=SC2034  # consumed by 01_activate.sh
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
    "nld=nvim < <(git diff HEAD~1)"
    "ngdc=nvim < <(git diff --cached)"
    "nglc=git diff-tree --no-commit-id --name-only -r -z HEAD | xargs -0 nvim"
    # MC Aliases
    "vaf=vimall -f"
    # --- Scripts & Lab ---
    "setup_tmux=~/personal_repos/my_config/scripts/tmux_setup_worktree_sessions.sh"
    "edit_bmc_configs=nvim ~/data/*Bel/documentation/*_bmc_config.R"
)

# Consolidation of Exclusion Lists
## Directory names skipped by file-scanning utilities (e.g. vimall).
# shellcheck disable=SC2034  # consumed by 10_vim_utils.sh
MC_EXCLUDE_DIRS=(
    ".git" "node_modules" ".next" ".nuxt" ".venv" "venv" "env" "__pycache__"
    "renv" ".Rproj.user" "build" "dist" "target" "out" "bin" "vendor" "deps"
    ".idea" ".ruff_cache" ".vscode" ".cache" "tmp" "temp" "coverage"
)

## File glob patterns skipped by file-scanning utilities.
# shellcheck disable=SC2034  # consumed by 10_vim_utils.sh
MC_EXCLUDE_FILES=(
    "*.log" "*.pdf" "*.bib" "*.zip" "*.json" "*.db" "*.git" "*.tmp" "*.bak" "*.swp" "*.swo" "*.pyc" "*.pyo" "*.o" "*.so"
    "*.a" "*.class" ".DS_Store" "Thumbs.db" "*repository_aggregate.md"
    "*.gitignore" "*.Rprofile" "*renv.lock"
)

## Maximum number of files vimall will open at once.
# shellcheck disable=SC2034  # consumed by 10_vim_utils.sh
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
## Directory scanned for optional extension scripts.
# shellcheck disable=SC2034  # consumed by 99_extensions.sh
MC_EXTENSIONS_DIR="$HOME/.config/mc_extensions"
## Extension file types that may be loaded from the extensions dir.
# shellcheck disable=SC2034  # consumed by 99_extensions.sh
MC_EXTENSION_TYPES_ALLOWED=("sh" "lua")
_MC_SKIP_EXTENSIONS=()
_MC_SKIPPED_EXTENSIONS=()
_MC_LOADED_EXTENSIONS=()
_MC_FAILED_EXTENSIONS=()

# ------------------------------------------------------------------------------
# Exports for subshells and scripts
# ------------------------------------------------------------------------------
export MC_ROOT MC_REPOS_ROOT MC_VERBOSITY _MC_OS_TYPE _MC_WSL_DISTRO
export _MC_COLOR_RESET _MC_COLOR_ERROR _MC_COLOR_WARN _MC_COLOR_INFO _MC_COLOR_DEBUG
