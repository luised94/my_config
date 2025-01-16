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

dirtree() {
    # Initialize variables
    local max_depth=3
    local output_file="dir_tree_output.txt"
    local include_files=false
    local target
    declare -a exclude_patterns
    
    # Parse arguments
    while getopts ":d:o:e:fh" opt; do
        case $opt in
            d) max_depth=$OPTARG ;;
            o) output_file=$OPTARG ;;
            e) exclude_patterns+=("$OPTARG") ;;
            f) include_files=true ;;
            h)
                echo -e "\nUsage: dirtree [-d depth] [-o output] [-e exclude] [-f] [-h] directory
Options:
    -d, --depth NUM    Maximum depth to traverse [default: 3]
    -o, --output FILE  Output file [default: dir_tree_output.txt]
    -e, --exclude PAT  Exclude pattern (can be used multiple times)
    -f, --files       Include files in output
    -h, --help        Show this help message\n"
                return 0
                ;;
        esac
    done
    shift $((OPTIND-1))
    
    # Target directory validation
    target="${1:-$(pwd)}"
    target="${target%/}"  # Remove trailing slash
    if [[ ! -d "$target" ]]; then
        echo -e "Invalid directory: $target"
        return 1
    fi
    
    # Default exclusions
    if [ ${#exclude_patterns[@]} -eq 0 ]; then
        exclude_patterns=(
            "nvim-linux64"
            "backup"
            "node_modules"
            "vendor"
            "library"
            ".git"
        )
    fi
    
    # Build find command arguments
    local find_args=("$target" "-mindepth" "1" "-maxdepth" "$max_depth")
    if [ ${#exclude_patterns[@]} -gt 0 ]; then
        find_args+=("\(")
        for pattern in "${exclude_patterns[@]}"; do
            find_args+=("-path" "*/$pattern" "-prune" "-o")
        done
        find_args+=("\)" "-false" "-o")
    fi
    if [[ "$include_files" = false ]]; then
        find_args+=("-type" "d")
    fi
    
    # Process output
    {
        printf "Directory Tree for: %s\n" "$target"
        printf "Generated on: %s\n" "$(date '+%Y-%m-%d %H:%M:%S')"
        printf "Configuration: depth=%s, files=%s\n" "$max_depth" "$include_files"
        printf "Find Command: %s\n" "${find_args[*]}"
        printf "%s\n\n" "========================================================================================================="
        
        find "${find_args[@]}" | \
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
    } > "$output_file"
    
    echo -e "\n[û] Tree generated successfully"
    echo -e "========================================================================================================="
    echo -e "Output saved to: $output_file"
    echo -e "=========================================================================================================\n"

    # Offer to display the result
    echo -e "[?] Would you like to view the output? (y/n)"
    read -r response
    if [[ $response =~ ^[Yy]$ ]]; then
        less "$output_file"
    fi
}
#dirtree() {
#    # Initialize variables
#    local max_depth=3
#    local output_file="dir_tree_output.txt"
#    local include_files=false
#    local target
#    declare -a exclude_patterns
#    
#    # Color definitions
#    local RED='\033[0;31m'
#    local GREEN='\033[0;32m'
#    local BLUE='\033[0;34m'
#    local YELLOW='\033[1;33m'
#    local NC='\033[0m'
#    local BOLD='\033[1m'
#    
#    # Parse arguments
#    while getopts ":d:o:e:fh" opt; do
#        case $opt in
#            d) max_depth=$OPTARG ;;
#            o) output_file=$OPTARG ;;
#            e) exclude_patterns+=("$OPTARG") ;;
#            f) include_files=true ;;
#            h)
#                echo -e "\nUsage: dirtree [-d depth] [-o output] [-e exclude] [-f] [-h] directory
#Options:
#    -d, --depth NUM    Maximum depth to traverse [default: 3]
#    -o, --output FILE  Output file [default: dir_tree_output.txt]
#    -e, --exclude PAT  Exclude pattern (can be used multiple times)
#    -f, --files       Include files in output
#    -h, --help        Show this help message\n"
#                return 0
#                ;;
#        esac
#    done
#    shift $((OPTIND-1))
#    
#    # Target directory validation
#    target="${1:-$(pwd)}"
#    target="${target%/}"  # Remove trailing slash
#    if [[ ! -d "$target" ]]; then
#        echo -e "${RED}[ERROR] Invalid directory: $target${NC}"
#        return 1
#    fi
#    
#    # Default exclusions
#    if [ ${#exclude_patterns[@]} -eq 0 ]; then
#        exclude_patterns=(
#            "nvim-linux64"
#            "backup"
#            "node_modules"
#            "vendor"
#            "library"
#            ".git"
#        )
#    fi
#    
#    local width=$(tput cols)
#    local separator=$(printf '%*s' "$width" '' | tr ' ' '=')
#    
#    # Display header
#    echo -e "\n${BOLD}${separator}${NC}"
#    printf "${BOLD}>> Directory Tree Generator - Target: ${BLUE}%s${NC}\n" "$target"
#    echo -e "${BOLD}${separator}${NC}"
#    
#    # Display configuration
#    echo -e "\n${BOLD}[*] Configuration:${NC}"
#    echo -e "   Max Depth: ${GREEN}$max_depth${NC}"
#    echo -e "   Include Files: ${GREEN}$include_files${NC}"
#    echo -e "   Output File: ${GREEN}$output_file${NC}"
#    echo -e "   Exclusions: ${GREEN}${exclude_patterns[*]}${NC}"
#    
#    # Process output
#    {
#        printf "Directory Tree for: %s\n" "$target"
#        printf "Generated on: %s\n" "$(date '+%Y-%m-%d %H:%M:%S')"
#        printf "Configuration: depth=%s, files=%s\n" "$max_depth" "$include_files"
#        local find_cmd="find \"$target\" -mindepth 1 -maxdepth \"$max_depth\""
#        if [[ "$include_files" = false ]]; then
#            find_cmd+=" -type d"
#        fi
#        if [ ${#exclude_patterns[@]} -gt 0 ]; then
#            find_cmd+=" ("
#            for pattern in "${exclude_patterns[@]}"; do
#                find_cmd+=" ! -path \"*/$pattern/*\" ! -name \"$pattern\""
#            done
#            find_cmd+=" )"
#        fi
#        printf "Find Command: %s\n" "$find_cmd"
#        printf "%s\n\n" "========================================================================================================="
#        
#        # Execute find command directly with proper quoting
#find "$target" -mindepth 1 -maxdepth "$max_depth" \
#    $(if [ ${#exclude_patterns[@]} -gt 0 ]; then
#        printf '\( '
#        for pattern in "${exclude_patterns[@]}"; do
#            printf '-path "*/%s" -prune -o ' "$pattern"
#        done
#        printf '\) -o '
#    fi) \
#    $(if [[ "$include_files" = false ]]; then echo "-type d"; fi) | \
#awk -v base="$target" '
#    BEGIN { skip_base = 0 }
#    {
#        if ($0 == ".") { 
#            print $0
#            next 
#        }
#        
#        if ($0 == base) next
#        
#        rel_path = substr($0, length(base) + 2)
#        split(rel_path, parts, "/")
#        depth = length(parts)
#        
#        indent = ""
#        for (i = 1; i < depth; i++) {
#            indent = indent "|  "
#        }
#        
#        if (depth > 0) {
#            indent = indent "+- "
#        }
#        
#        print indent parts[length(parts)]
#    }'
#    } > "$output_file"
#    
#    # Display results
#    echo -e "\n${BOLD}[*] Statistics:${NC}"
#    echo -e "   Total Entries: ${GREEN}$(wc -l < "$output_file")${NC}"
#    echo -e "   Directories: ${GREEN}$(grep -c '^+- ' "$output_file")${NC}"
#    if [[ "$include_files" = true ]]; then
#        echo -e "   Files: ${GREEN}$(grep -c -v '^+- ' "$output_file" | awk '{print $1-4}')${NC}"
#    fi
#    
#    echo -e "\n${GREEN}[û] Tree generated successfully${NC}"
#    echo -e "${BOLD}${separator}${NC}"
#    echo -e "Output saved to: ${BLUE}$output_file${NC}"
#    echo -e "${BOLD}${separator}${NC}\n"
#
#    # Offer to display the result
#    echo -e "${YELLOW}[?] Would you like to view the output? (y/n)${NC}"
#    read -r response
#    if [[ $response =~ ^[Yy]$ ]]; then
#        less "$output_file"
#    fi
#}
