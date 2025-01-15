view_files() {
    local width=$(tput cols)
    local separator=$(printf '%*s' "$width" '' | tr ' ' '=')
    
    local usage="Usage: view_files [-t type] [-f filter] [-x exclude] [-b batch_size] [-d depth] [-s sort_order] [-v] [-h] directory
Options:
    -t, --type     File type (e.g., html, svg, pdf) [default: html]
    -f, --filter   Include pattern
    -x, --exclude  Exclude pattern
    -b, --batch    Batch size [default: 5]
    -d, --depth    Search depth [default: 3]
    -s, --sort     Sort order (alpha, rev) [default: alpha]
    -v, --verbose  Verbose output
    -h, --help     Show this help message"

    # Color definitions
    local RED='\033[0;31m'
    local GREEN='\033[0;32m'
    local BLUE='\033[0;34m'
    local YELLOW='\033[1;33m'
    local NC='\033[0m'
    local BOLD='\033[1m'
    
    # Browser configuration (for now, keep it as a single browser)
    # For future multi-browser support, you can uncomment the following:
    # local -a browsers=(
    #     "/mnt/c/Program Files/BraveSoftware/Brave-Browser/Application/brave.exe"
    #     # Add more browsers here
    # )
    # Use the first browser for now
    local browser="/mnt/c/Program Files/BraveSoftware/Brave-Browser/Application/brave.exe"

    # Initialize variables with new defaults
    local type="html"
    local filter=""
    local exclude=""
    local batch_size=5
    local depth=3  # Changed default depth
    local sort_order="alpha"
    local verbose=0

    local OPTIND opt
    
    # Argument parsing using getopts
    while getopts ":t:f:x:b:d:s:vh" opt; do
        case $opt in
            t) type=$OPTARG ;;
            f) filter=$OPTARG ;;
            x) exclude=$OPTARG ;;
            b) batch_size=$OPTARG ;;
            d) depth=$OPTARG ;;
            s) sort_order=$OPTARG ;;
            v) verbose=1 ;;
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

    # Check if there are any remaining non-option arguments before the directory
    if [ $# -gt 1 ]; then
        echo -e "${RED}[ERROR] Invalid argument order. Directory must be the last argument.${NC}\n"
        echo -e "${usage}\n"
        return 1
    fi

    # Handle directory argument
    local target="${1:-$(pwd)}"
    if [[ ! -d "$target" ]]; then
        echo -e "${RED}[ERROR] Invalid directory: $target${NC}"
        echo -e "${YELLOW}Hint: Make sure the directory is the last argument${NC}"
        echo -e "Example: view_files -t html -d 5 ~/your/directory"
        return 1
    fi

    # Build find command arguments
    build_find_command() {
        local depth=$1
        local type=$2
        local filter=$3
        local exclude=$4
        
        local cmd=("-maxdepth" "$depth" "-type" "f")
        
        # Add type filter
        [[ -n "$type" ]] && cmd+=("-name" "*.$type")
        
        # Add include filter if specified
        if [[ -n "$filter" ]]; then
            cmd+=("-a" "-name" "*${filter}*")
        fi
        
        # Add exclude filter if specified
        if [[ -n "$exclude" ]]; then
            cmd+=("!" "-name" "*${exclude}*")
        fi
        
        echo "${cmd[@]}"
    }
    # Build find command with diagnostic output
    #local find_args=("-maxdepth" "$depth" "-type" "f")
    #[[ -n "$type" ]] && find_args+=("-name" "*.$type")
    #[[ -n "$filter" ]] && find_args+=("-a" "-name" "*${filter}*")
    #[[ -n "$exclude" ]] && find_args+=("!" "-name" "*${exclude}*")

    # Find files using properly constructed command
    local find_args
    find_args=($(build_find_command "$depth" "$type" "$filter" "$exclude"))


    # Required command checks
    command -v wslpath >/dev/null 2>&1 || {
        echo -e "${RED}[ERROR] wslpath not found${NC}"
        return 1
    }
    
    [ ! -f "$browser" ] && {
        echo -e "${RED}[ERROR] Browser not found at specified path${NC}"
        return 1
    }

    echo -e "\n${BOLD}${separator}${NC}"
    printf "${BOLD}>> File Viewer - Target: ${BLUE}%s${NC}\n" "$target"
    echo -e "${BOLD}${separator}${NC}"
    
    # Find files matching criteria, sort them by default alphabetically

    local files
    if [[ "$sort_order" = "alpha" ]]; then
        IFS=$'\n' read -d '' -r -a files < <(find "$target" "${find_args[@]}" 2>/dev/null | sort)
    elif [[ "$sort_order" = "rev" ]]; then
        IFS=$'\n' read -d '' -r -a files < <(find "$target" "${find_args[@]}" 2>/dev/null | sort -r)
    else
        echo -e "${RED}[ERROR] Invalid sort order${NC}"
        return 1
    fi

    local file_count=${#files[@]}
    
    # No files found - provide helpful diagnostics
    if [ $file_count -eq 0 ]; then
        echo -e "\n${YELLOW}[!] No matching files found${NC}"
        echo -e "\nTroubleshooting suggestions:"
        echo -e "1. Current depth is set to ${BOLD}$depth${NC}. Try increasing with: -d option"
        echo -e "2. Looking for ${BOLD}*.$type${NC} files. Check if this is correct"
        echo -e "3. Run with -v flag for verbose output"
        echo -e "${YELLOW}4. Make sure the directory is the last argument${NC}"
        
        # Quick directory analysis for suggestions
        local deeper_files
        IFS=$'\n' read -d '' -r -a deeper_files < <(find "$target" -type f -name "*.$type" 2>/dev/null | head -n 1)
        if [ ${#deeper_files[@]} -gt 0 ]; then
            local suggested_depth=$(echo "${deeper_files[0]}" | awk -F"/" "{print NF-split(\"$target\", a, \"/\")+1}")
            echo -e "\n${GREEN}[TIP] Found files at depth ${suggested_depth}. Try:${NC}"
            echo -e "view_files -t $type -d $suggested_depth \"$target\"\n"
        fi
        return 0
    fi
    
    # Display statistics
    echo -e "\n${BOLD}[*] File Statistics:${NC}"
    echo -e "   Total files found: ${GREEN}$file_count${NC}"
    echo -e "   Batch size: ${GREEN}$batch_size${NC}"
    
    # Confirm before proceeding
    echo -e "\n${YELLOW}[?] Proceed with viewing files? (y/n)${NC}"
    read -r response
    if [[ ! $response =~ ^[Yy]$ ]]; then
        echo -e "\n${BLUE}[-] Operation cancelled by user${NC}"
        return 0
    fi

    # Process files in batches
    local index=0
    local batch=1
    
    while (( index < file_count )); do
        echo -e "\n${BOLD}${separator}${NC}"
        echo -e "${BOLD}Batch $batch - Files $((index+1)) to $((index+5 > file_count ? file_count : index+5)) of $file_count${NC}"
        echo -e "${BOLD}${separator}${NC}"
        
        for (( i=0; i<batch_size && index < file_count; i++, index++ )); do
            local html_file="${files[index]}"
            local windows_path
            windows_path=$(wslpath -w "$html_file")
            
            echo -e "\n${BLUE}[>] Opening file $((index+1))/${file_count}: ${NC}$(basename "$html_file")"
            "$browser" "$windows_path" &
        done
        
        wait # Wait for browser processes
        
        if (( index < file_count )); then
            echo -e "\n${YELLOW}[?] Press Enter for next batch, [q] to quit${NC}"
            read -r input
            if [[ $input = "q" ]]; then
                echo -e "\n${BLUE}[*] Viewer terminated by user${NC}"
                return 0
            fi
        fi
        
        ((batch++))
    done
    
    echo -e "\n${GREEN}[û] Processing complete!${NC}"
    echo -e "${BOLD}${separator}${NC}"
    echo -e "       Files processed: $file_count"
    echo -e "       Batches completed: $((batch-1))"
    echo -e "${BOLD}${separator}${NC}\n"
}

debug_view_files() {
    local width=$(tput cols)
    local separator=$(printf '%*s' "$width" '' | tr ' ' '=')
    local sub_separator=$(printf '%*s' "$width" '' | tr ' ' '-')
    
    # Color definitions
    local RED='\033[0;31m'
    local GREEN='\033[0;32m'
    local BLUE='\033[0;34m'
    local YELLOW='\033[1;33m'
    local NC='\033[0m'
    local BOLD='\033[1m'

    # Stage 1: Argument Processing
    echo -e "\n${BOLD}${separator}"
    printf "${BOLD}DEBUG STAGE 1: Argument Processing${NC}\n"
    echo -e "${separator}\n"
    
    printf "Raw arguments received:\n${sub_separator}\n"
    printf "   Count: %d\n" $#
    printf "   Values: %s\n" "$@"

    # Initialize variables
    local type="html"
    local filter=""
    local exclude=""
    local batch_size=5
    local depth=1
    local sort_order="alpha"
    local verbose=0
    local target=""

    # Stage 2: Option Parsing
    echo -e "\n${BOLD}${separator}"
    printf "${BOLD}DEBUG STAGE 2: Option Parsing${NC}\n"
    echo -e "${separator}\n"

    local OPTIND opt
    while getopts ":t:f:x:b:d:s:vh" opt; do
        case $opt in
            t) 
                type=$OPTARG
                printf "   Option -t: type set to '%s'\n" "$type"
                ;;
            f) 
                filter=$OPTARG
                printf "   Option -f: filter set to '%s'\n" "$filter"
                ;;
            x) 
                exclude=$OPTARG
                printf "   Option -x: exclude set to '%s'\n" "$exclude"
                ;;
            b) 
                batch_size=$OPTARG
                printf "   Option -b: batch_size set to '%s'\n" "$batch_size"
                ;;
            d) 
                depth=$OPTARG
                printf "   Option -d: depth set to '%s'\n" "$depth"
                ;;
            s) 
                sort_order=$OPTARG
                printf "   Option -s: sort_order set to '%s'\n" "$sort_order"
                ;;
            v) 
                verbose=1
                printf "   Option -v: verbose mode enabled\n"
                ;;
            h) 
                printf "   Option -h: help requested\n"
                return 0
                ;;
            \?) 
                printf "   ${RED}Invalid option: -%s${NC}\n" "$OPTARG"
                return 1
                ;;
        esac
    done

    # Stage 3: Target Directory Processing
    echo -e "\n${BOLD}${separator}"
    printf "${BOLD}DEBUG STAGE 3: Target Directory Processing${NC}\n"
    echo -e "${separator}\n"

    shift $((OPTIND-1))
    target="${1:-$(pwd)}"
    
    printf "After option processing:\n${sub_separator}\n"
    printf "   OPTIND: %d\n" "$OPTIND"
    printf "   Remaining args: %s\n" "$@"
    printf "   Target directory: %s\n" "$target"
    printf "   Directory exists: %s\n" "$([ -d "$target" ] && echo 'yes' || echo 'no')"

    # Stage 4: Find Command Construction
    echo -e "\n${BOLD}${separator}"
    printf "${BOLD}DEBUG STAGE 4: Find Command Construction${NC}\n"
    echo -e "${separator}\n"

    local find_cmd="find \"$target\" -maxdepth $depth -type f -name \"*.$type\""
    [[ -n "$filter" ]] && find_cmd+=" -a -name \"*${filter}*\""
    [[ -n "$exclude" ]] && find_cmd+=" ! -name \"*${exclude}*\""

    printf "Constructed find command:\n${sub_separator}\n"
    printf "   %s\n" "$find_cmd"

    # Stage 5: File Finding Execution
    echo -e "\n${BOLD}${separator}"
    printf "${BOLD}DEBUG STAGE 5: File Finding Execution${NC}\n"
    echo -e "${separator}\n"

    printf "Executing find command...\n${sub_separator}\n"
    local files
    IFS=$'\n' read -d '' -r -a files < <(eval "$find_cmd" 2>/dev/null | sort)
    
    printf "Results:\n"
    printf "   Found %d files\n" "${#files[@]}"
    if [ ${#files[@]} -gt 0 ]; then
        printf "\nFirst 5 files found (if any):\n"
        for ((i=0; i<5 && i<${#files[@]}; i++)); do
            printf "   %s\n" "${files[$i]}"
        done
    fi

    echo -e "\n${BOLD}${separator}${NC}\n"
}
