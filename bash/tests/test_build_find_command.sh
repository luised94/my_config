build_find_command() {
    local target=$1
    local max_depth=$2
    local include_files=$3
    local -a cmd=()
    
    # Start with base command
    cmd+=("$target")
    cmd+=("-mindepth" "1" "-maxdepth" "$max_depth")
    
    # Add type restriction if files are not included
    [[ "$include_files" = false ]] && cmd+=("-type" "d")
    
    # Start exclusion group
    cmd+=("(")
    
    for pattern in "${exclude_patterns[@]}"; do
        # Exclude matching paths and names
        cmd+=("! -path \"*/$pattern/*\" ! -name \"$pattern\"")
    done
    
    # Close exclusion group
    cmd+=(")")
    
    echo "${cmd[@]}"
}

test_build_find_command() {
    local target=$1
    local max_depth=$2
    local include_files=$3
    local exclusions="$4"
    
    declare -a exclude_patterns
    if [[ -n "$exclusions" ]]; then
        exclude_patterns=($exclusions)
    fi
    
    echo "Test case: target=$target, max_depth=$max_depth, include_files=$include_files, exclusions=$exclusions"
    local cmd=$(build_find_command "$target" "$max_depth" "$include_files")
    echo "Generated command: $cmd"
    echo ""
}

# Test build_find_command with various scenarios
echo "Testing build_find_command..."
echo "============================="
test_build_find_command "." 3 false
test_build_find_command "." 3 true
test_build_find_command "/path/to/target" 2 false
test_build_find_command "/path/to/target" 2 true
test_build_find_command "." 5 false "nvim-linux64 .git"
test_build_find_command "." 5 true "node_modules vendor library"
test_build_find_command "/home/user/my_config" 3 false ".git backup"
test_build_find_command "/home/user/my_config" 3 true "nvim-linux64 node_modules"
test_build_find_command "." 1 false
test_build_find_command "." 1 true
test_build_find_command "/path/to/target" 4 false "vendor library"
test_build_find_command "/path/to/target" 4 true "backup .git"
