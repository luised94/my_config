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
    
    # Add standard hidden files/directories exclusion
    cmd+=("!" "-path" "*/.*")
    
    # Add user-specified exclusions
    local first=true
    for pattern in "${exclude_patterns[@]}"; do
        cmd+=("-a" "!" "-path" "*/$pattern/*" "-a" "!" "-name" "$pattern")
    done
    
    # Close exclusion group
    cmd+=(")")
    
    echo "${cmd[@]}"
}

dirtree() {
    # Enable trace mode for specific blocks with cleanup
    trap 'set +x' EXIT  # Ensure we turn off tracing on exit
    
    local width=$(tput cols)
    local separator=$(printf '%*s' "$width" '' | tr ' ' '=')
    local sub_separator=$(printf '%*s' "$width" '' | tr ' ' '-')
    
    # Debug function with consistent formatting
    debug() {
        local level=$1
        local message=$2
        local color=$3
        printf "\n%s\n" "${separator}"
        printf "${color}[DEBUG] [%s] %s${NC}\n" "$level" "$message"
        printf "%s\n" "${sub_separator}"
    }
    
    # Data validation function
    validate_data() {
        local stage=$1
        local data=$2
        debug "VALIDATE" "Stage: $stage" "$YELLOW"
        printf "Data: %s\n" "$data"
        if [[ -z "$data" ]]; then
            printf "${RED}[ERROR] Empty data at stage: %s${NC}\n" "$stage"
            return 1
        fi
    }

    # Color definitions
    local RED='\033[0;31m'
    local GREEN='\033[0;32m'
    local BLUE='\033[0;34m'
    local YELLOW='\033[1;33m'
    local NC='\033[0m'
    local BOLD='\033[1m'

    debug "INIT" "Starting dirtree function" "$GREEN"
    
    # Initialize variables with validation
    local max_depth=3
    local output_file="dir_tree_output.txt"
    local include_files=false
    local target
    declare -a exclude_patterns
    
    debug "CONFIG" "Initial variables set" "$BLUE"
    
    # Parse arguments with explicit tracking
    debug "ARGS" "Processing arguments" "$BLUE"
    local OPTIND opt
    while getopts ":d:o:e:fh" opt; do
        case $opt in
            d) 
                debug "ARGS" "Setting depth: $OPTARG" "$GREEN"
                max_depth=$OPTARG 
                ;;
            o) 
                debug "ARGS" "Setting output file: $OPTARG" "$GREEN"
                output_file=$OPTARG 
                ;;
            e) 
                debug "ARGS" "Adding exclude pattern: $OPTARG" "$GREEN"
                exclude_patterns+=("$OPTARG") 
                ;;
            f) 
                debug "ARGS" "Enabling file inclusion" "$GREEN"
                include_files=true 
                ;;
            h)
                debug "ARGS" "Showing help" "$YELLOW"
                echo -e "\n${usage}\n"
                return 0
                ;;
        esac
    done
    shift $((OPTIND-1))
    
    # Target directory validation
    target="${1:-$(pwd)}"
    debug "PATH" "Target directory: $target" "$BLUE"
    if [[ ! -d "$target" ]]; then
        debug "ERROR" "Invalid directory: $target" "$RED"
        return 1
    fi
    
    # Default exclusions with verification
    if [ ${#exclude_patterns[@]} -eq 0 ]; then
        debug "EXCLUDE" "Setting default exclusions" "$BLUE"
        exclude_patterns=(
            "nvim-linux64"
            "backup"
            "node_modules"
            "vendor"
            "library"
            ".git"
        )
    fi
    
    # Find command construction with explicit debugging
    debug "FIND" "Building find command" "$BLUE"
    {
        set -x  # Enable tracing for find command construction
        local find_cmd="find \"$target\""
        find_cmd+=" -mindepth 1 -maxdepth $max_depth"
        [[ "$include_files" = false ]] && find_cmd+=" -type d"
        find_cmd+=" ! -path \"*/.*\""
        
        for pattern in "${exclude_patterns[@]}"; do
            find_cmd+=" ! -path \"*/$pattern/*\" ! -name \"$pattern\""
        done
        set +x  # Disable tracing
    }
    
    debug "FIND" "Final find command: $find_cmd" "$GREEN"
    
    # Test find command
    debug "TEST" "Testing find command output" "$BLUE"
    local test_output
    test_output=$(eval "$find_cmd" 2>/dev/null | head -n 5)
    printf "Sample output:\n%s\n" "$test_output"
    
    # Process output with AWK debugging
    debug "AWK" "Starting AWK processing" "$BLUE"
    {
        printf "Directory Tree for: %s\n" "$target"
        printf "Generated on: %s\n" "$(date '+%Y-%m-%d %H:%M:%S')"
        printf "Configuration: depth=%s, files=%s\n" "$max_depth" "$include_files"
        printf "%s\n\n" "$separator"
        
        {
            echo "."
            eval "$find_cmd" 2>/dev/null
        } | awk -v base="$target" '
            BEGIN {
                printf "AWK: Processing started\n" > "/dev/stderr"
            }
            {
                printf "AWK: Processing line: %s\n", $0 > "/dev/stderr"
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
            }
            END {
                printf "AWK: Processing completed\n" > "/dev/stderr"
            }'
    } > "$output_file"
    
    # Validate output file
    debug "OUTPUT" "Validating output file" "$BLUE"
    if [[ ! -s "$output_file" ]]; then
        debug "ERROR" "Output file is empty" "$RED"
        return 1
    fi
    
    # Display sample of output
    debug "RESULT" "First 10 lines of output:" "$GREEN"
    head -n 10 "$output_file" | sed 's/^/    /'
    
    debug "COMPLETE" "Processing finished" "$GREEN"
}
#dirtree() {
#    local width=$(tput cols)
#    local separator=$(printf '%*s' "$width" '' | tr ' ' '=')
#    
#    # Color definitions
#    local RED='\033[0;31m'
#    local GREEN='\033[0;32m'
#    local BLUE='\033[0;34m'
#    local YELLOW='\033[1;33m'
#    local NC='\033[0m'
#    local BOLD='\033[1m'
#
#    local usage="Usage: dirtree [-d depth] [-o output] [-e exclude] [-f] [-h] directory
#Options:
#    -d, --depth NUM    Maximum depth to traverse [default: 3]
#    -o, --output FILE  Output file [default: dir_tree_output.txt]
#    -e, --exclude PAT  Exclude pattern (can be used multiple times)
#    -f, --files       Include files in output
#    -h, --help        Show this help message"
#
#    # Initialize variables
#    local max_depth=3
#    local output_file="dir_tree_output.txt"
#    local include_files=false
#    local target
#    declare -a exclude_patterns
#
#    # Parse arguments using getopts
#    local OPTIND opt
#    while getopts ":d:o:e:fh" opt; do
#        case $opt in
#            d) max_depth=$OPTARG ;;
#            o) output_file=$OPTARG ;;
#            e) exclude_patterns+=("$OPTARG") ;;
#            f) include_files=true ;;
#            h)
#                echo -e "\n${usage}\n"
#                return 0
#                ;;
#            \?)
#                echo -e "${RED}[ERROR] Invalid option: -$OPTARG${NC}\n"
#                echo -e "${usage}\n"
#                return 1
#                ;;
#        esac
#    done
#    shift $((OPTIND-1))
#
#    # Handle directory argument
#    target="${1:-$(pwd)}"
#    if [[ ! -d "$target" ]]; then
#        echo -e "${RED}[ERROR] Invalid directory: $target${NC}"
#        echo -e "${YELLOW}Hint: Make sure the directory exists${NC}"
#        return 1
#    fi
#
#    # Add default exclusions if none specified
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
#    echo -e "\n${BOLD}[*] Processing...${NC}"
#
#    # Build and execute find command
#    local find_cmd="find"
#    local find_args
#    find_args=($(build_find_command "$target" "$max_depth" "$include_files"))
#    find_cmd+=" ${find_args[*]}"
#
#    # Process and write output
#    {
#        # Write header
#        printf "Directory Tree for: %s\n" "$target"
#        printf "Generated on: %s\n" "$(date '+%Y-%m-%d %H:%M:%S')"
#        printf "Configuration: depth=%s, files=%s\n" "$max_depth" "$include_files"
#        printf "%s\n\n" "$separator"
#        
#        # Execute find and process through awk in a single pipeline
#        {
#            echo "."  # Print root directory
#            eval "$find_cmd" 2>/dev/null
#        } | awk -v base="$target" '
#            BEGIN { skip_base = 0 }
#            {
#                if ($0 == ".") { 
#                    print $0
#                    next 
#                }
#                
#                if ($0 == base) next
#                
#                rel_path = substr($0, length(base) + 2)
#                split(rel_path, parts, "/")
#                depth = length(parts)
#                
#                indent = ""
#                for (i = 1; i < depth; i++) {
#                    indent = indent "|  "
#                }
#                
#                if (depth > 0) {
#                    indent = indent "+- "
#                }
#                
#                print indent parts[length(parts)]
#            }'
#    } > "$output_file"
#
#    # Get accurate statistics
#    local total_entries=$(wc -l < "$output_file")
#    local dir_count=$(eval "$find_cmd" 2>/dev/null | wc -l)
#    local file_count=0
#    if [[ "$include_files" = true ]]; then
#        file_count=$((total_entries - dir_count - 4))  # Subtract header lines
#    fi
#
#    # Adjust total_entries to exclude header
#    total_entries=$((total_entries - 4))  # Subtract header lines
#
#    # Display results
#    echo -e "\n${BOLD}[*] Statistics:${NC}"
#    echo -e "   Total Entries: ${GREEN}$total_entries${NC}"
#    echo -e "   Directories: ${GREEN}$dir_count${NC}"
#    [[ "$include_files" = true ]] && echo -e "   Files: ${GREEN}$file_count${NC}"
#
#    echo -e "\n${GREEN}[û] Tree generated successfully!${NC}"
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
## Function to build find command
##build_find_command() {
##    local target=$1
##    local max_depth=$2
##    local include_files=$3
##    local cmd=("-L" "$target" "-maxdepth" "$max_depth" "-not" "-path" "*/.*")
##    [[ "$include_files" = false ]] && cmd+=("-type" "d")
##    for pattern in "${exclude_patterns[@]}"; do
##        cmd+=("-not" "-path" "*$pattern*" "-not" "-name" "$pattern")
##    done
##    echo "${cmd[@]}"
##}
#build_find_command() {
#    local target=$1
#    local max_depth=$2
#    local include_files=$3
#    local -a cmd=()
#    
#    # Start with base command
#    cmd+=("$target")
#    cmd+=("-mindepth" "1" "-maxdepth" "$max_depth")
#    
#    # Add type restriction if files are not included
#    [[ "$include_files" = false ]] && cmd+=("-type" "d")
#    
#    # Start exclusion group
#    cmd+=("(")
#    
#    # Add standard hidden files/directories exclusion
#    cmd+=("!" "-path" "*/.*")
#    
#    # Add user-specified exclusions
#    local first=true
#    for pattern in "${exclude_patterns[@]}"; do
#        cmd+=("-a" "!" "-path" "*/$pattern/*" "-a" "!" "-name" "$pattern")
#    done
#    
#    # Close exclusion group
#    cmd+=(")")
#    
#    echo "${cmd[@]}"
#}
#
#dirtree() {
#    local width=$(tput cols)
#    local separator=$(printf '%*s' "$width" '' | tr ' ' '=')
#    
#    # Color definitions
#    local RED='\033[0;31m'
#    local GREEN='\033[0;32m'
#    local BLUE='\033[0;34m'
#    local YELLOW='\033[1;33m'
#    local NC='\033[0m'
#    local BOLD='\033[1m'
#
#    local usage="Usage: dirtree [-d depth] [-o output] [-e exclude] [-f] [-h] directory
#Options:
#    -d, --depth NUM    Maximum depth to traverse [default: 3]
#    -o, --output FILE  Output file [default: dir_tree_output.txt]
#    -e, --exclude PAT  Exclude pattern (can be used multiple times)
#    -f, --files       Include files in output
#    -h, --help        Show this help message"
#
#    # Initialize variables
#    local max_depth=3
#    local output_file="dir_tree_output.txt"
#    local include_files=false
#    local target
#    declare -a exclude_patterns
#
#
#    # Parse arguments using getopts
#    local OPTIND opt
#    while getopts ":d:o:e:fh" opt; do
#        case $opt in
#            d) max_depth=$OPTARG ;;
#            o) output_file=$OPTARG ;;
#            e) exclude_patterns+=("$OPTARG") ;;
#            f) include_files=true ;;
#            h)
#                echo -e "\n${usage}\n"
#                return 0
#                ;;
#            \?)
#                echo -e "${RED}[ERROR] Invalid option: -$OPTARG${NC}\n"
#                echo -e "${usage}\n"
#                return 1
#                ;;
#        esac
#    done
#    shift $((OPTIND-1))
#
#    # Handle directory argument
#    target="${1:-$(pwd)}"
#    if [[ ! -d "$target" ]]; then
#        echo -e "${RED}[ERROR] Invalid directory: $target${NC}"
#        echo -e "${YELLOW}Hint: Make sure the directory exists${NC}"
#        return 1
#    fi
#
#    # Add default exclusions if none specified
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
#    # Build and execute find command
#    local find_args
#    find_args=($(build_find_command "$target" "$max_depth" "$include_files"))
#
#    echo -e "\n${BOLD}[*] Processing...${NC}"
#
#    # Execute and format output with progress tracking
#    # Build and execute find command
#
#    # Process and write output
#    {
#        # Write header
#        printf "Directory Tree for: %s\n" "$target"
#        printf "Generated on: %s\n" "$(date '+%Y-%m-%d %H:%M:%S')"
#        printf "Configuration: depth=%s, files=%s\n" "$max_depth" "$include_files"
#        printf "%s\n\n" "$separator"
#        
#        # Execute find and process through awk in a single pipeline
#        {
#            echo "."  # Print root directory
#            eval "$find_cmd" 2>/dev/null
#        } | awk -v base="$target" '
#            BEGIN { skip_base = 0 }
#            {
#                if ($0 == ".") { 
#                    print $0
#                    next 
#                }
#                
#                if ($0 == base) next
#                
#                rel_path = substr($0, length(base) + 2)
#                split(rel_path, parts, "/")
#                depth = length(parts)
#                
#                indent = ""
#                for (i = 1; i < depth; i++) {
#                    indent = indent "|  "
#                }
#                
#                if (depth > 0) {
#                    indent = indent "+- "
#                }
#                
#                print indent parts[length(parts)]
#            }'
#    } > "$output_file"
#
#
#    # Get statistics
#    local total_entries=$(wc -l < "$output_file")
#    local dir_count=0
#    #local dir_count=$(find "${find_args[@]}" -type d 2>/dev/null | wc -l)
#    local file_count=0
#    [[ "$include_files" = true ]] && file_count=$((total_entries - dir_count))
#
#    # Display results
#    echo -e "\n${BOLD}[*] Statistics:${NC}"
#    echo -e "   Total Entries: ${GREEN}$total_entries${NC}"
#    echo -e "   Directories: ${GREEN}$dir_count${NC}"
#    [[ "$include_files" = true ]] && echo -e "   Files: ${GREEN}$file_count${NC}"
#
#    echo -e "\n${GREEN}[û] Tree generated successfully!${NC}"
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
#
#debug_dirtree() {
#    local target="${1:-$(pwd)}"
#    local width=$(tput cols)
#    local separator=$(printf '%*s' "$width" '' | tr ' ' '=')
#    local sub_separator=$(printf '%*s' "$width" '' | tr ' ' '-')
#    
#    # Color definitions
#    local RED='\033[0;31m'
#    local GREEN='\033[0;32m'
#    local BLUE='\033[0;34m'
#    local YELLOW='\033[1;33m'
#    local NC='\033[0m'
#    local BOLD='\033[1m'
#
#    # Initialize variables
#    local max_depth=3
#    local include_files=false
#    declare -a exclude_patterns=(
#        "nvim-linux64"
#        "backup"
#        "node_modules"
#        "vendor"
#        "library"
#        ".git"
#    )
#
#    # Step 1: Directory Validation
#    echo -e "\n${BOLD}${separator}"
#    printf "${BOLD}DEBUG STAGE 1: Directory Validation${NC}\n"
#    echo -e "${separator}\n"
#    
#    printf "Target directory: ${BLUE}%s${NC}\n" "$target"
#    printf "Absolute path: ${BLUE}%s${NC}\n" "$(readlink -f "$target")"
#    printf "Directory exists: ${GREEN}%s${NC}\n" "$([ -d "$target" ] && echo "YES" || echo "NO")"
#    
#    # Step 2: Find Command Construction
#    echo -e "\n${BOLD}${separator}"
#    printf "${BOLD}DEBUG STAGE 2: Find Command Construction${NC}\n"
#    echo -e "${separator}\n"
#    
#    local find_cmd="find \"$target\" -mindepth 1 -maxdepth $max_depth"
#    [[ "$include_files" = false ]] && find_cmd+=" -type d"
#    find_cmd+=" ! -path \"*/.*\""
#    
#    for pattern in "${exclude_patterns[@]}"; do
#        find_cmd+=" ! -path \"*/$pattern/*\" ! -name \"$pattern\""
#    done
#    
#    printf "Constructed find command:\n${sub_separator}\n"
#    echo -e "${BLUE}$find_cmd${NC}\n"
#    
#    # Step 3: Raw Find Output
#    echo -e "\n${BOLD}${separator}"
#    printf "${BOLD}DEBUG STAGE 3: Raw Find Output${NC}\n"
#    echo -e "${separator}\n"
#    
#    printf "Direct find command output:\n${sub_separator}\n"
#    eval "$find_cmd" 2>/dev/null | sed 's/^/   /'
#    printf "\nTotal entries found: ${GREEN}%d${NC}\n" "$(eval "$find_cmd" 2>/dev/null | wc -l)"
#
#    # Step 4: Tree Structure Generation
#    echo -e "\n${BOLD}${separator}"
#    printf "${BOLD}DEBUG STAGE 4: Tree Structure Generation${NC}\n"
#    echo -e "${separator}\n"
#    
#    printf "Processing through awk:\n${sub_separator}\n"
#    {
#        echo "."
#        eval "$find_cmd" 2>/dev/null | \
#        awk -v base="$target" '
#        BEGIN { print "AWK Processing Started" > "/dev/stderr" }
#        {
#            if ($0 == base) next
#            
#            rel_path = substr($0, length(base) + 2)
#            split(rel_path, parts, "/")
#            depth = length(parts)
#            
#            printf "Processing: %s (depth: %d)\n", rel_path, depth > "/dev/stderr"
#            
#            indent = ""
#            for (i = 1; i < depth; i++) {
#                indent = indent "|  "
#            }
#            
#            if (depth > 0) {
#                indent = indent "+- "
#            }
#            
#            print indent parts[length(parts)]
#        }
#        END { print "AWK Processing Completed" > "/dev/stderr" }'
#    } | tee /tmp/tree_output
#    
#    # Step 5: Final Output Validation
#    echo -e "\n${BOLD}${separator}"
#    printf "${BOLD}DEBUG STAGE 5: Final Output Validation${NC}\n"
#    echo -e "${separator}\n"
#    
#    printf "Tree structure preview:\n${sub_separator}\n"
#    head -n 10 /tmp/tree_output | sed 's/^/   /'
#    printf "\nTotal lines in output: ${GREEN}%d${NC}\n" "$(wc -l < /tmp/tree_output)"
#    
#    # Cleanup
#    rm -f /tmp/tree_output
#    
#    echo -e "\n${BOLD}${separator}${NC}\n"
#}
#
