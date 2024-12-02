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
