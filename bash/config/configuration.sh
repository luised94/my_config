# Path configurations
ADDITIONAL_PATHS=(
    "~/node-v22.5.1-linux-x64/bin"
)

# Environment variables
ENV_VARS=(
    "GIT_EDITOR=nvim"
    "R_HOME=/usr/local/bin/R"
    "R_LIBS_USER=~/R/library/"
    "BROWSER=/mnt/c/Program Files (x86)/BraveSoftware/Brave-Browser/Application/brave.exe"
)

# Shell configuration settings
# Do not source directly - use init.sh

# History settings
HISTCONTROL=ignoreboth
HISTSIZE=1000
HISTFILESIZE=2000

# Shell options
SHELL_OPTIONS=(
    "histappend"
    "checkwinsize"
)

# Color support
COLOR_SUPPORT=1
GCC_COLORS='error=01;31:warning=01;35:note=01;36:caret=01;32:locus=01:quote=01'

# Environment variables
ENV_VARS=(
    "GIT_EDITOR=nvim"
    "R_HOME=/usr/local/bin/R"
    "R_LIBS_USER=~/R/library/"
    "BROWSER=/mnt/c/Program Files (x86)/BraveSoftware/Brave-Browser/Application/brave.exe"
    "MANPAGER=col -b | nvim +Man! -"
)

# Additional paths
ADDITIONAL_PATHS=(
    "~/node-v22.5.1-linux-x64/bin"
)
# Standard aliases
BASIC_ALIASES=(
    "ll=ls -alF"
    "la=ls -A"
    "l=ls -CF"
    "R=R --no-save"
    "explorer=explorer.exe ."
)

# Git aliases
GIT_ALIASES=(
    "gs=git status"
    "gd=git diff"
    "ogd=nvim < <(git diff)"
    "ogdc=nvim < <(git diff --cached)"
    "ogda=nvim < <(git diff HEAD)"
    "ga=git add"
    "gb=git branch"
    "gm=git merge"
    "gmnff=git merge --no-ff"
    "gc=git commit"
    "gco=git checkout"
    "gcb=git checkout -b"
    "grm=git rebase main"
    "gps=git push"
    "gpl=git pull"
    "gl=git log --oneline --graph --decorate"
    "gfap=git fetch --all --prune"
    "gitstart=git fetch --all --prune && git status && git pull && git rebase main && echo [X] Git workspace ready for coding!'"
    "syncall=sync_all_branches"
)

LABUTILS_ALIASES=(
    "edit_bmc_configs=nvim ~/data/*Bel/documentation/*_bmc_config.R ~/lab_utils/core_scripts/template_bmc_config.R ~/lab_utils/core_scripts/bmc_config.R"
)

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
# Search configuration
# Do not source directly - use init.sh

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
SEARCH_OPTIONS=(
    "h|help:Show this help message"
    "e|exclude-dir:Additional directory to exclude (requires value)"
    "f|exclude-file:Additional file pattern to exclude (requires value)"
    "v|verbose:Enable verbose output"
    "q|quiet:Suppress all output except final counts"
    "d|max-depth:Maximum directory depth to search (requires value)"
)



AGGREGATE_REPOSITORY_USAGE="
Usage: aggregate_repository [options] \"commit message\"

Options:
  -d|--max-depth N    Maximum directory depth to search
  -e|--exclude-dir    Additional directory to exclude
  -f|--exclude-file   Additional file pattern to exclude
  -v|--verbose        Enable verbose output
  -q|--quiet         Suppress all output except final counts
"
# Search defaults
DEFAULT_SEARCH_VERBOSE=0
DEFAULT_SEARCH_QUIET=0

# Advanced search configuration
declare -A SEARCH_CONFIG=(
    ["MAX_RESULTS"]="1000"
    ["CONTEXT_LINES"]="0"
    ["COLORED_OUTPUT"]="true"
)

# Grep styling
declare -A GREP_STYLES=(
    ["MATCH_COLOR"]="01;31"  # Bold red
    ["LINE_COLOR"]="01;90"   # Bold gray
    ["FILE_COLOR"]="01;36"   # Bold cyan
)
# Repository configuration
# Do not source directly - use init.sh

# Repository settings
declare -A REPO_CONFIG=(
    ["README_NAME"]="README.md"
    ["TAG_SECTION"]="## TAGS"
    ["DEFAULT_DEPTH"]="1"
)

# File defaults
declare -A FILE_DEFAULTS=(
    ["EXTENSIONS"]="sh R py"
    ["DEFAULT_TAG"]="TODO"
)

# File patterns
declare -A FILE_PATTERNS=(
    ["DEFAULT_EXTENSIONS"]="sh R py"
    ["IGNORE_DIRS"]="git node_modules build"
)
#!/bin/bash

# Standard output formatting symbols for CLI feedback
declare -A OUTPUT_SYMBOLS=(
    ["START"]="=== "    # Indicates start of operation
    ["PROCESSING"]=">>> " # Shows ongoing process
    ["SUCCESS"]="[+] "   # Positive completion
    ["ERROR"]="[!] "     # Error condition
    ["WARNING"]="[?] "   # Warning or attention needed
    ["INFO"]="[*] "      # General information
    ["DONE"]="=== "      # Operation completion
)
