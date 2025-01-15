view_files() {
    local target="${1:-$(pwd)}"
    local width=$(tput cols)
    local separator=$(printf '%*s' "$width" '' | tr ' ' '=')
    local usage="Usage: view_files [-t type] [-f filter] [-x exclude] [-b batch_size] [-d depth] [-s sort_order] [-v] [-h] directory
    Options:
        -t, --type     File type (e.g., html, svg, pdf)
        -f, --filter   Include pattern
        -x, --exclude  Exclude pattern
        -b, --batch    Batch size (default: 5)
        -d, --depth    Search depth (default: 1)
        -s, --sort     Sort order (default: alpha, reverse: rev)
        -v, --verbose  Verbose output
        -h, --help     Show this help message
    "
    
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
    
    # Option parsing
    local OPTIND opt
    local type="html"
    local filter=""
    local exclude=""
    local batch_size=5
    local depth=1
    local sort_order="alpha"
    local verbose=0
    
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

    # Ensure target directory is valid
    if [[ ! -d "$target" ]]; then
        echo -e "${RED}[ERROR] Invalid directory: $target${NC}"
        return 1
    fi

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
    if [ "$sort_order" = "alpha" ]; then
        IFS=$'\n' read -d '' -r -a files < <(find "$target" -maxdepth "$depth" -type f -name "*.$type" \( -name "$filter"* \) ! -name "$exclude"* | sort)
    elif [ "$sort_order" = "rev" ]; then
        IFS=$'\n' read -d '' -r -a files < <(find "$target" -maxdepth "$depth" -type f -name "*.$type" \( -name "$filter"* \) ! -name "$exclude"* | sort -r)
    else
        echo -e "${RED}[ERROR] Invalid sort order${NC}"
        return 1
    fi

    local file_count=${#files[@]}
    
    if [ $file_count -eq 0 ]; then
        echo -e "\n${YELLOW}[!] No matching files found${NC}"
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
