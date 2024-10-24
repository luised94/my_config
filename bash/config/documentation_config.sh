# Documentation configuration
# Do not source directly - use init.sh

# Tree visualization defaults
DEFAULT_TREE_MAX_DEPTH=""
DEFAULT_TREE_ENTRY_LIMIT=""
DEFAULT_TREE_USE_COLOR=1
DEFAULT_TREE_FULL_PATHS=0

# Default exclude patterns
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

# Documentation paths and sections
declare -A DOC_CONFIG=(
    ["README_PATH"]="$HOME/lab_utils/README.md"
    ["TAG_SECTION"]="## TAGS"
    ["DEFAULT_TAG"]="TODO"
    ["MAX_DEPTH"]="-1"  # No limit
)
