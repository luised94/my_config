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
    local width=$(tput cols)
    local separator=$(printf '%*s' "$width" '' | tr ' ' '=')
    
    # Color definitions
    local RED='\033[0;31m'
    local GREEN='\033[0;32m'
    local BLUE='\033[0;34m'
    local YELLOW='\033[1;33m'
    local NC='\033[0m'
    local BOLD='\033[1m'

    local usage="Usage: dirtree [-d depth] [-o output] [-e exclude] [-f] [-h] directory
Options:
    -d, --depth NUM    Maximum depth to traverse [default: 3]
    -o, --output FILE  Output file [default: dir_tree_output.txt]
    -e, --exclude PAT  Exclude pattern (can be used multiple times)
    -f, --files       Include files in output
    -h, --help        Show this help message"

    # Initialize variables
    local max_depth=3
    local output_file="dir_tree_output.txt"
    local include_files=false
    local target
    declare -a exclude_patterns
    
    # Parse arguments
    local OPTIND opt
    while getopts ":d:o:e:fh" opt; do
        case $opt in
            d) max_depth=$OPTARG ;;
            o) output_file=$OPTARG ;;
            e) exclude_patterns+=("$OPTARG") ;;
            f) include_files=true ;;
            h)
                echo -e "\n${usage}\n"
                return 0
                ;;
        esac
    done
    shift $((OPTIND-1))
    
    # Target directory validation
    target="${1:-$(pwd)}"
    if [[ ! -d "$target" ]]; then
        echo -e "${RED}[ERROR] Invalid directory: $target${NC}"
        return 1
    fi
    
    # Default exclusions with verification
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
    
    # Find command construction
    local find_cmd=$(build_find_command "$target" "$max_depth" "$include_files")
    
    # Process output with AWK
    {
        printf "Directory Tree for: %s\n" "$target"
        printf "Generated on: %s\n" "$(date '+%Y-%m-%d %H:%M:%S')"
        printf "Configuration: depth=%s, files=%s\n" "$max_depth" "$include_files"
        printf "Find Command: %s\n" "$find_cmd"
        printf "%s\n\n" "$separator"
        
        # Execute find and process through awk in a single pipeline
        {
            echo "."  # Print root directory
            eval "$find_cmd" 2>/dev/null
        } | awk -v base="$target" '
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
    
    echo -e "\n${GREEN}[û] Tree generated successfully${NC}"
    echo -e "${BOLD}${separator}${NC}"
    echo -e "Output saved to: ${BLUE}$output_file${NC}"
    echo -e "${BOLD}${separator}${NC}\n"

    # Offer to display the result
    echo -e "${YELLOW}[?] Would you like to view the output? (y/n)${NC}"
    read -r response
    if [[ $response =~ ^[Yy]$ ]]; then
        less "$output_file"
    fi
}
