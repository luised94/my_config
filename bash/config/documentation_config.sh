#!/bin/bash

# Add to existing or create new configuration
declare -A DOC_CONFIG=(
    ["README_PATH"]="$HOME/lab_utils/README.md"
    ["TAG_SECTION"]="## TAGS"
    ["DEFAULT_TAG"]="TODO"
    ["MAX_DEPTH"]="-1"  # No limit
)

declare -A FILE_PATTERNS=(
    ["DEFAULT_EXTENSIONS"]=("sh" "R" "py")
    ["IGNORE_DIRS"]=(".git" "node_modules" "build")
)

declare -A GREP_STYLES=(
    ["MATCH_COLOR"]="01;31"  # Bold red
    ["LINE_COLOR"]="01;90"   # Bold gray
    ["FILE_COLOR"]="01;36"   # Bold cyan
)

declare -A REPO_CONFIG=(
    ["README_NAME"]="README.md"
    ["TAG_SECTION"]="## TAGS"
    ["DEFAULT_DEPTH"]=1
)

declare -A FILE_DEFAULTS=(
    ["EXTENSIONS"]=("sh" "R" "py")
    ["DEFAULT_TAG"]="TODO"
)

declare -A SEARCH_CONFIG=(
    ["MAX_RESULTS"]=1000
    ["CONTEXT_LINES"]=0
    ["COLORED_OUTPUT"]=true
)

# Tree visualization defaults
DEFAULT_TREE_MAX_DEPTH=""
DEFAULT_TREE_ENTRY_LIMIT=""
DEFAULT_TREE_USE_COLOR=1
DEFAULT_TREE_FULL_PATHS=0

# Default exclude patterns for tree visualization
DEFAULT_TREE_EXCLUDE_PATTERNS=(
    "node_modules"
    "*.pyc"
    "*.tmp"
    ".git"
)

# Visual formatting
TREE_COMPACT_SYMBOLS=(
    "ÃÄ"
    "ÀÄ"
    "³ "
)
