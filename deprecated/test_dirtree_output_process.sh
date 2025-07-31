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
    
    if [ ${#exclude_patterns[@]} -gt 0 ]; then
        # Start exclusion group
        cmd+=("\(")
        
        for pattern in "${exclude_patterns[@]}"; do
            # Exclude matching paths and names
            cmd+=("! -path \"*/$pattern/*\" ! -name \"$pattern\"")
        done
        
        # Close exclusion group
        cmd+=("\)")
    fi
    
    echo "${cmd[@]}"
}

test_process_output() {
    local target=$1
    local max_depth=$2
    local include_files=$3
    local exclusions="$4"
    
    declare -a exclude_patterns
    if [[ -n "$exclusions" ]]; then
        exclude_patterns=($exclusions)
    fi
    
    echo "Test case: target=$target, max_depth=$max_depth, include_files=$include_files, exclusions=$exclusions"
    local find_cmd=$(build_find_command "$target" "$max_depth" "$include_files")
    echo "Generated find command: $find_cmd"
    
    # Process output
    {
        printf "Directory Tree for: %s\n" "$target"
        printf "Generated on: %s\n" "$(date '+%Y-%m-%d %H:%M:%S')"
        printf "Configuration: depth=%s, files=%s\n" "$max_depth" "$include_files"
        printf "Find Command: %s\n" "$find_cmd"
        printf "%s\n\n" "========================================================================================================="
        
        # Execute find command directly with proper quoting
        find "$target" -mindepth 1 -maxdepth "$max_depth" \
            $(if [[ "$include_files" = false ]]; then echo "-type d"; fi) \
            $(if [ ${#exclude_patterns[@]} -gt 0 ]; then
                printf '( '
                for pattern in "${exclude_patterns[@]}"; do
                    printf '! -path "*/%s/*" ! -name "%s" ' "$pattern" "$pattern"
                done
                printf ')'
            fi) | \
        awk -v base="$target" '
            BEGIN { skip_base = 0 }
            {
                if ($0 == ".") { 
                    print $0
                    next 
                }
                
                if ($0 == base) next
                
                rel_path = substr($0, length(base) + 2)
                split(rel_path, parts, "/")
                depth = length(parts)
                
                indent = ""
                for (i = 1; i < depth; i++) {
                    indent = indent "|  "
                }
                
                if (depth > 0) {
                    indent = indent "+- "
                }
                
                print indent parts[length(parts)]
            }'
    }
    echo ""
}






























































# Test process_output with various scenarios
echo "Testing process_output..."
echo "==========================="
test_process_output "." 3 false
test_process_output "." 3 true
test_process_output "." 2 false
test_process_output "." 2 true
test_process_output "." 5 false "nvim-linux64 .git"
test_process_output "." 5 true "node_modules vendor library"
test_process_output "." 3 false ".git backup"
test_process_output "." 3 true "nvim-linux64 node_modules"
test_process_output "." 1 false
test_process_output "." 1 true
test_process_output "." 4 false "vendor library"
test_process_output "." 4 true "backup .git"
