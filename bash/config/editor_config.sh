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

# Default settings
DEFAULT_FILE_WARNING_THRESHOLD=100
