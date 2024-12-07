
# Editor configuration
# Do not source directly - use init.sh

# Dir tree options
DIR_TREE_OPTIONS=(
    "h|help:Show this help message"
    "d|depth: NUM Maximum depth to traverse (default: 3)"
    "o|output: FILE Output file (default: output.txt)"
    "e|exclude: PAT Exclude pattern (can be used multiple times)"
    "f|files: Include files in the output"
)

DIR_TREE_USAGE_EXAMPLES=(
    "dir_tree                                  # Create the output.txt file as default."
    "dir_tree -h                                  # Show help message."
    "dir_tree -d 4                                  # Show help message."
)
