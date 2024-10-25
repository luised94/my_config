# Tree configuration
# Do not source directly - use init.sh

# Tree visualization defaults
DEFAULT_TREE_MAX_DEPTH=""
DEFAULT_TREE_ENTRY_LIMIT=""
DEFAULT_TREE_USE_COLOR=1
DEFAULT_TREE_FULL_PATHS=0

# Default exclude patterns
DEFAULT_TREE_EXCLUDE_DIRS=(
    ".git"
    "node_modules"
    "build"
    "dist"
    "renv"
    ".venv"
)

DEFAULT_TREE_EXCLUDE_FILES=(
    "*.log"
    "*.tmp"
    "*.bak"
    "*.swp"
    ".gitignore"
    ".Rprofile"
)

# Tree command options
TREE_OPTIONS=(
    "h|help:Show this help message"
    "d|max-depth:Maximum directory depth (requires value)"
    "e|exclude:Exclude pattern (requires value)"
    "s|summary:Show only directory summary counts"
    "l|limit:Limit entries per directory (requires value)"
    "n|no-color:Disable color output"
    "f|full-paths:Show full paths instead of relative"
)

# Examples for usage message
TREE_USAGE_EXAMPLES=(
    "ctree"
    "ctree -d 3 -e node_modules"
    "ctree -s ~/projects"
    "ctree -l 10 -f"
)
