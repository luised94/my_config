process_html_files() {
    local target="${1:-$(pwd)}"
    
    # Check for required commands
    command -v wslpath >/dev/null 2>&1 || { echo "Error: wslpath not found. Please install it."; return 1; }
    command -v "/mnt/c/Program Files/BraveSoftware/Brave-Browser/Application/brave.exe" >/dev/null 2>&1 || { echo "Error: Brave browser not found at specified path."; return 1; }
    
    # Validate directory
    if [[ ! -d "$target" ]]; then
        echo "Error: Provided path is not a valid directory."
        return 1
    fi

    # Find HTML files
    local files
    IFS=$'\n' read -d '' -r -a files < <(find "$target" -type f -name "*.html" 2>/dev/null)
    
    # Quick statistics
    local file_count=${#files[@]}
    printf "Found %d HTML files in directory: %s\n" "$file_count" "$target"
    if [[ $file_count -eq 0 ]]; then
        echo "No HTML files found. Exiting."
        return 0
    fi

    read -p "Proceed with processing these files? (y/n): " confirm
    if [[ ! "$confirm" =~ ^[Yy]$ ]]; then
        echo "Exiting without processing."
        return 0
    fi

    # Process files in batches of 5
    local index=0
    while (( index < file_count )); do
        echo "Processing files:"
        for (( i=0; i<5 && index < file_count; i++, index++ )); do
            local html_file="${files[index]}"
            local windows_path
            windows_path=$(wslpath -w "$html_file")
            echo "Opening: $html_file"
            "/mnt/c/Program Files/BraveSoftware/Brave-Browser/Application/brave.exe" "$windows_path" &
        done
        
        wait # Wait for all opened browsers to process before proceeding
        if (( index < file_count )); then
            read -p "Press Enter to continue to the next set of files, or type 'exit' to quit: " user_input
            if [[ "$user_input" == "exit" ]]; then
                break
            fi
        fi
    done

    echo "Processing complete. Exiting."
}

view_html_files() {
    local target="${1:-$(pwd)}"
    local width=$(tput cols)
    local separator=$(printf '%*s' "$width" '' | tr ' ' '=')
    
    # Color definitions
    local RED='\033[0;31m'
    local GREEN='\033[0;32m'
    local BLUE='\033[0;34m'
    local YELLOW='\033[1;33m'
    local NC='\033[0m'
    local BOLD='\033[1m'
    
    # Check for required commands
    if ! command -v wslpath &> /dev/null; then
        echo -e "${RED}[ERROR] wslpath command not found${NC}"
        return 1
    fi
    
    if [ ! -f "/mnt/c/Program Files/BraveSoftware/Brave-Browser/Application/brave.exe" ]; then
        echo -e "${RED}[ERROR] Brave browser not found${NC}"
        return 1
    fi
    
    # Validate directory
    if [ ! -d "$target" ]; then
        echo -e "${RED}[ERROR] Directory not found: $target${NC}"
        return 1
    fi
    
    echo -e "\n${BOLD}${separator}${NC}"
    printf "${BOLD}>> HTML File Viewer - Target: ${BLUE}%s${NC}\n" "$target"
    echo -e "${BOLD}${separator}${NC}"
    
    # Find HTML files and store in array
    local -a html_files
    while IFS= read -r -d $'\0' file; do
        html_files+=("$file")
    done < <(find "$target" -type f -name "*.html" -print0)
    
    local total_files=${#html_files[@]}
    
    if [ $total_files -eq 0 ]; then
        echo -e "\n${YELLOW}[!] No HTML files found in directory${NC}"
        return 0
    fi
    
    # Display statistics
    echo -e "\n${BOLD}[*] File Statistics:${NC}"
    echo -e "   Total HTML files found: ${GREEN}$total_files${NC}"
    echo -e "   Processing batch size: ${GREEN}5${NC}"
    
    # Ask for confirmation
    echo -e "\n${YELLOW}[?] Do you want to proceed with viewing files? (y/n)${NC}"
    read -r response
    if [[ ! $response =~ ^[Yy]$ ]]; then
        echo -e "\n${BLUE}[-] Operation cancelled by user${NC}"
        return 0
    fi
    
    local current=0
    local batch=1
    
    while [ $current -lt $total_files ]; do
        echo -e "\n${BOLD}${separator}${NC}"
        echo -e "${BOLD}Batch $batch - Files ${current+1} to $((current+5 > total_files ? total_files : current+5)) of $total_files${NC}"
        echo -e "${BOLD}${separator}${NC}"
        
        for ((i=current; i<current+5 && i<total_files; i++)); do
            local file="${html_files[$i]}"
            local windows_path=$(wslpath -w "$file")
            
            echo -e "\n${BLUE}[>] Opening file $((i+1))/${total_files}: ${NC}$(basename "$file")"
            "/mnt/c/Program Files/BraveSoftware/Brave-Browser/Application/brave.exe" "$windows_path"
            
            if [ $((i+1)) -lt $total_files ]; then
                echo -e "\n${YELLOW}[?] Press [Enter] for next file, [q] to quit${NC}"
                read -r input
                if [[ $input = "q" ]]; then
                    echo -e "\n${BLUE}[*] Viewer terminated by user${NC}"
                    return 0
                fi
            fi
        done
        
        current=$((current+5))
        batch=$((batch+1))
        
        if [ $current -lt $total_files ]; then
            echo -e "\n${YELLOW}[?] Continue to next batch? (y/n)${NC}"
            read -r response
            if [[ ! $response =~ ^[Yy]$ ]]; then
                echo -e "\n${BLUE}[*] Viewer terminated by user${NC}"
                return 0
            fi
        fi
    done
    
    echo -e "\n${GREEN}[û] All HTML files processed successfully!${NC}"
    echo -e "${BOLD}${separator}${NC}\n"
    echo -e "       Thanks for using HTML Viewer!"
    echo -e "          See you next time!"
    echo -e "\n${BOLD}${separator}${NC}\n"
}
