#!/bin/bash

# Default values
max_depth=3
output_file="dir_tree_output.txt"
tree_chars=("|-" "|  " "+-")  # Standard ASCII characters
include_files=false

# Function to display usage
usage() {
    cat << EOF
Usage: $(basename "$0") [OPTIONS]

Generate a tree-like directory structure output while excluding specified patterns.

Options:
    -d, --depth NUM       Maximum depth to traverse (default: 3)
    -o, --output FILE     Output file (default: output.txt)
    -e, --exclude PAT     Exclude pattern (can be used multiple times)
    -f, --files           Include files in the output
    -h, --help            Show this help message

Example:
    $(basename "$0") -d 4 -o mydir.txt -e "node_modules" -e "vendor" -f
EOF
    exit 1
}

# Function to handle errors
error() {
    echo "Error: $1" >&2
    exit 1
}

# Initialize empty array for exclude patterns
declare -a exclude_patterns

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        -d|--depth)
            [[ -n $2 ]] || error "Depth argument required"
            max_depth=$2
            shift 2
            ;;
        -o|--output)
            [[ -n $2 ]] || error "Output file argument required"
            output_file=$2
            shift 2
            ;;
        -e|--exclude)
            [[ -n $2 ]] || error "Exclude pattern argument required"
            exclude_patterns+=("$2")
            shift 2
            ;;
        -f|--files)
            include_files=true
            shift
            ;;
        -h|--help)
            usage
            ;;
        *)
            error "Unknown option: $1"
            ;;
    esac
done

# Add default exclusions if none specified
if [ ${#exclude_patterns[@]} -eq 0 ]; then
    exclude_patterns=(
        "nvim-linux64"
        "backup"
        "node_modules"
        "vendor"
        "library"
    )
fi

# Build the find command with exclusions
find_cmd="find -L . -maxdepth $max_depth"

if [ "$include_files" = false ]; then
    find_cmd+=" -type d"
fi

find_cmd+=" -not -path \"*/.*\""

# Add exclusions to find command
for pattern in "${exclude_patterns[@]}"; do
    find_cmd+=" -not -path \"*$pattern*\" -not -name \"$pattern\""
done

# Execute and format output
eval "$find_cmd" | awk -v output_file="$output_file" -v include_files="$include_files" '
BEGIN {
    prefix[""] = "";
}
{
    split($0, parts, "/");
    depth = length(parts) - 1;
    last = parts[length(parts)];

    # Create indentation using standard ASCII
    indent = "";
    for (i = 1; i < depth; i++) {
        indent = indent "|  ";
    }

    # Add branch symbol for non-root entries
    if (depth > 0) {
        indent = indent "+- ";
    }

    # Print formatted output
    if (include_files || system("test -d \"" $0 "\"") == 0) {
        print indent last;
    }
}' > "$output_file"

# Check if output file was created successfully
if [ $? -eq 0 ] && [ -f "$output_file" ]; then
    echo "Directory structure has been saved to $output_file"
else
    error "Failed to create output file"
fi
