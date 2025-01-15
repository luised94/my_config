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

    # Function to build find command
    build_find_command() {
        local target=$1
        local max_depth=$2
        local include_files=$3
        
        local cmd=("-L" "$target" "-maxdepth" "$max_depth" "-not" "-path" "*/.*")
        
        [[ "$include_files" = false ]] && cmd+=("-type" "d")
        
        for pattern in "${exclude_patterns[@]}"; do
            cmd+=("-not" "-path" "*$pattern*" "-not" "-name" "$pattern")
        done
        
        echo "${cmd[@]}"
    }

    # Parse arguments using getopts
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
            \?)
                echo -e "${RED}[ERROR] Invalid option: -$OPTARG${NC}\n"
                echo -e "${usage}\n"
                return 1
                ;;
        esac
    done
    shift $((OPTIND-1))

    # Handle directory argument
    target="${1:-$(pwd)}"
    if [[ ! -d "$target" ]]; then
        echo -e "${RED}[ERROR] Invalid directory: $target${NC}"
        echo -e "${YELLOW}Hint: Make sure the directory exists${NC}"
        return 1
    fi

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

    echo -e "\n${BOLD}${separator}${NC}"
    printf "${BOLD}>> Directory Tree Generator - Target: ${BLUE}%s${NC}\n" "$target"
    echo -e "${BOLD}${separator}${NC}"

    # Display configuration
    echo -e "\n${BOLD}[*] Configuration:${NC}"
    echo -e "   Max Depth: ${GREEN}$max_depth${NC}"
    echo -e "   Include Files: ${GREEN}$include_files${NC}"
    echo -e "   Output File: ${GREEN}$output_file${NC}"
    echo -e "   Exclusions: ${GREEN}${exclude_patterns[*]}${NC}"

    # Build and execute find command
    local find_args
    find_args=($(build_find_command "$target" "$max_depth" "$include_files"))

    echo -e "\n${BOLD}[*] Processing...${NC}"

    # Execute and format output with progress tracking
    {
        echo -e "Directory Tree for: $target"
        echo -e "Generated on: $(date '+%Y-%m-%d %H:%M:%S')"
        echo -e "Configuration: depth=$max_depth, files=$include_files"
        echo -e "${separator}\n"
        
        find "${find_args[@]}" 2>/dev/null | awk '
        BEGIN {
            prefix[""] = "";
        }
        {
            split($0, parts, "/");
            depth = length(parts) - 1;
            last = parts[length(parts)];
            
            indent = "";
            for (i = 1; i < depth; i++) {
                indent = indent "³  ";
            }
            
            if (depth > 0) {
                indent = indent "ÃÄ ";
            }
            
            print indent last;
        }'
    } > "$output_file"

    # Get statistics
    local total_entries=$(wc -l < "$output_file")
    local dir_count=$(find "${find_args[@]}" -type d 2>/dev/null | wc -l)
    local file_count=0
    [[ "$include_files" = true ]] && file_count=$((total_entries - dir_count))

    # Display results
    echo -e "\n${BOLD}[*] Statistics:${NC}"
    echo -e "   Total Entries: ${GREEN}$total_entries${NC}"
    echo -e "   Directories: ${GREEN}$dir_count${NC}"
    [[ "$include_files" = true ]] && echo -e "   Files: ${GREEN}$file_count${NC}"

    echo -e "\n${GREEN}[û] Tree generated successfully!${NC}"
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
