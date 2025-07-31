#!/bin/bash
# =============================================================
# Consolidated Environment and PATH Settings Configuration File
# =============================================================
# This file assigns environment variables, including the PATH settings.
# The file is meant to be sourced in init.sh which is sourced by bashrc.
# References:
# - Bash PATH best practices [1]
# - How to set environment variables permanently [5]
# - Processing modular configuration files [12]
# =============================================================

# Define environment variables in key=value string format
# The expression is run via export.
declare -a ENV_VARS=(
  "GIT_EDITOR=nvim"
  "R_HOME=/usr/local/bin/R"
  "R_LIBS_USER=~/R/library/"
  "MANPAGER=nvim +Man!"
)

# Export each of the environment variables.
for env in "${ENV_VARS[@]}"; do
  export "$env"
done

# Define browsers ----------
declare -a BROWSERS=(
    "/mnt/c/Program Files/BraveSoftware/Brave-Browser/Application/brave.exe"
    "/mnt/c/Program Files (x86)/BraveSoftware/Brave-Browser/Application/brave.exe"
)

for browser in "${BROWSERS[@]}"; do
    if [ -f "$browser" ]; then
        #log_debug "Setting browser to: "$browser""
        export BROWSER="$browser"
        break
    fi
    echo "[WARNING] No broswer in BROWSERS variable has been found."
done

# Fallback if no browser was found
if [ -z "$BROWSER" ]; then
    if command -v wslview &> /dev/null; then
        echo "[WARNING] Setting wslview as default."
        export BROWSER="wslview"
    # Final fallback - use echo to let the user know
    else
        echo "No suitable browser found. Please install one or add its path to BROWSERS array."
    fi
fi

# Additional PATH -------------

# Define additional directories to add to the PATH.
declare -a ADDITIONAL_PATHS=(
  "~/node-v22.5.1-linux-x64/bin"
)

# Iterate over each additional path.
for p in "${ADDITIONAL_PATHS[@]}"; do
    # Expand '~' to the full home directory path.
    expanded_path="${p/#\~/$HOME}"
    # Check if the directory exists.
    if [ -d "$expanded_path" ]; then
        # Append the directory if it is not already in PATH.
        case ":$PATH:" in
            *":$expanded_path:"*) ;;  # Already in PATH.
            *) PATH="$PATH:$expanded_path";;
        esac
    fi
done

# Export the updated PATH variable.
# echo "Current PATH: $PATH"
export PATH

# History settings -------------
HISTCONTROL=ignoreboth
HISTSIZE=1000
HISTFILESIZE=2000

# Shell options ----------
SHELL_OPTIONS=(
    "histappend"
    "checkwinsize"
)

# Color support ----------
COLOR_SUPPORT=1
GCC_COLORS='error=01;31:warning=01;35:note=01;36:caret=01;32:locus=01:quote=01'

# Search configuration ----------
# Default exclusion patterns
DEFAULT_SEARCH_EXCLUDE_DIRS=(
    ".git"
    "node_modules"
    "build"
    "dist"
    "renv"
    ".venv"
)

DEFAULT_SEARCH_EXCLUDE_FILES=(
    "*.log"
    "*repository_aggregate.md"
    "*.tmp"
    "*.bak"
    "*.swp"
    "*.gitignore"
    "*.Rprofile"
    "*renv.lock"
)

# Search options
#SEARCH_OPTIONS=(
#    "h|help:Show this help message"
#    "e|exclude-dir:Additional directory to exclude (requires value)"
#    "f|exclude-file:Additional file pattern to exclude (requires value)"
#    "v|verbose:Enable verbose output"
#    "q|quiet:Suppress all output except final counts"
#    "d|max-depth:Maximum directory depth to search (requires value)"
#)
#
#
#
#AGGREGATE_REPOSITORY_USAGE="
#Usage: aggregate_repository [options] \"commit message\"
#
#Options:
#  -d|--max-depth N    Maximum directory depth to search
#  -e|--exclude-dir    Additional directory to exclude
#  -f|--exclude-file   Additional file pattern to exclude
#  -v|--verbose        Enable verbose output
#  -q|--quiet         Suppress all output except final counts
#"
## Search defaults
#DEFAULT_SEARCH_VERBOSE=0
#DEFAULT_SEARCH_QUIET=0
#
## Advanced search configuration
#declare -A SEARCH_CONFIG=(
#    ["MAX_RESULTS"]="1000"
#    ["CONTEXT_LINES"]="0"
#    ["COLORED_OUTPUT"]="true"
#)
#
## Grep styling
#declare -A GREP_STYLES=(
#    ["MATCH_COLOR"]="01;31"  # Bold red
#    ["LINE_COLOR"]="01;90"   # Bold gray
#    ["FILE_COLOR"]="01;36"   # Bold cyan
#)
# Editor configuration
# Do not source directly - use init.sh

# Editor preferences
DEFAULT_EDITORS=(
    "nvim"
    "vim"
)

# Editor options
EDITOR_OPTIONS=(
    "h|help:Show this help message"
    "e|editor:Specify editor to use (requires value)"
    "d|directory:Specify search directory (requires value)"
    "f|force:Skip confirmation for large file counts"
    "l|limit:Set file count warning threshold (requires value)"
    "m|mode:Specify sort mode: modified, conflicts, search (requires value)"
    "p|pattern:Search pattern for search mode (requires value)"
)

EDITOR_USAGE_EXAMPLES=(
    "vim_all                                  # Open files in current directory sorted by modification time"
    "vim_all -d ./src                         # Open files from specific directory"
    "vim_all -e nvim                          # Use specific editor (nvim)"
    "vim_all -m conflicts                     # Open files with Git conflicts"
    "vim_all -m modified                      # Open Git modified/staged files"
    "vim_all -m search -p 'TODO'              # Open files containing 'TODO'"
    "vim_all -f -m modified                   # Force open modified files (skip confirmation)"
    "vim_all -l 50                            # Set custom file limit warning threshold"
)

# Default settings
DEFAULT_FILE_WARNING_THRESHOLD=100
