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
    "*.tmp"
    "*.bak"
    "*.swp"
    "*.gitignore"
    "*.Rprofile"
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
