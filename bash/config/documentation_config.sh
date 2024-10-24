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
