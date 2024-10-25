
#!/bin/bash
echo "dir_tree.sh started."
# Define exclusion patterns (add more as needed)
exclude_patterns=(
    "nvim-linux64"
    "backup"
    "node_modules"
    "vendor"
    "library"
)

# Build the find command with exclusions
find_cmd="find -L . -maxdepth 3 -type d -not -path \"*/.*\""

# Add exclusions to find command (more efficient than grep)
for pattern in "${exclude_patterns[@]}"; do
    find_cmd+=" -not -path \"*/$pattern/*\" -not -name \"$pattern\""
done

echo "$find_cmd"
# Execute and format output
eval "$find_cmd" | awk '
BEGIN {
    prefix[""] = "";
}
{
    split($0, parts, "/");
    depth = length(parts) - 1;
    last = parts[length(parts)];
    
    # Create indentation
    indent = "";
    for (i = 1; i < depth; i++) {
        indent = indent "³   ";
    }
    
    # Add branch symbol for non-root entries
    if (depth > 0) {
        indent = indent "ÃÄÄ ";
    }
    
    # Print formatted output
    print indent last;
}' > output.txt
