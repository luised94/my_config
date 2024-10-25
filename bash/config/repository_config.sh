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
