#process_html_files() {
#    local target="${1:-$(pwd)}"
#    
#    # Check for required commands
#    command -v wslpath >/dev/null 2>&1 || { echo "Error: wslpath not found. Please install it."; return 1; }
#    command -v "/mnt/c/Program Files/BraveSoftware/Brave-Browser/Application/brave.exe" >/dev/null 2>&1 || { echo "Error: Brave browser not found at specified path."; return 1; }
#    
#    # Validate directory
#    if [[ ! -d "$target" ]]; then
#        echo "Error: Provided path is not a valid directory."
#        return 1
#    fi
#
#    # Find HTML files
#    local files
#    IFS=$'\n' read -d '' -r -a files < <(find "$target" -type f -name "*.html" 2>/dev/null)
#    
#    # Quick statistics
#    local file_count=${#files[@]}
#    printf "Found %d HTML files in directory: %s\n" "$file_count" "$target"
#    if [[ $file_count -eq 0 ]]; then
#        echo "No HTML files found. Exiting."
#        return 0
#    fi
#
#    read -p "Proceed with processing these files? (y/n): " confirm
#    if [[ ! "$confirm" =~ ^[Yy]$ ]]; then
#        echo "Exiting without processing."
#        return 0
#    fi
#
#    # Process files in batches of 5
#    local index=0
#    while (( index < file_count )); do
#        echo "Processing files:"
#        for (( i=0; i<5 && index < file_count; i++, index++ )); do
#            local html_file="${files[index]}"
#            local windows_path
#            windows_path=$(wslpath -w "$html_file")
#            echo "Opening: $html_file"
#            "/mnt/c/Program Files/BraveSoftware/Brave-Browser/Application/brave.exe" "$windows_path" &
#        done
#        
#        wait # Wait for all opened browsers to process before proceeding
#        if (( index < file_count )); then
#            read -p "Press Enter to continue to the next set of files, or type 'exit' to quit: " user_input
#            if [[ "$user_input" == "exit" ]]; then
#                break
#            fi
#        fi
#    done
#
#    echo "Processing complete. Exiting."
#}

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
    command -v wslpath >/dev/null 2>&1 || { 
        echo -e "${RED}[ERROR] wslpath not found${NC}"
        return 1
    }
    
    command -v "/mnt/c/Program Files/BraveSoftware/Brave-Browser/Application/brave.exe" >/dev/null 2>&1 || { 
        echo -e "${RED}[ERROR] Brave browser not found${NC}"
        return 1
    }
    
    # Validate directory
    [[ ! -d "$target" ]] && {
        echo -e "${RED}[ERROR] Invalid directory: $target${NC}"
        return 1
    }
    
    echo -e "\n${BOLD}${separator}${NC}"
    printf "${BOLD}>> HTML File Viewer - Target: ${BLUE}%s${NC}\n" "$target"
    echo -e "${BOLD}${separator}${NC}"
    
    # Find HTML files using improved array handling
    local -a files
    IFS=$'\n' read -d '' -r -a files < <(find "$target" -type f -name "*.html" 2>/dev/null)
    
    local file_count=${#files[@]}
    
    # Enhanced statistics display
    echo -e "\n${BOLD}[*] File Statistics:${NC}"
    echo -e "   Total HTML files found: ${GREEN}$file_count${NC}"
    echo -e "   Target directory size: ${GREEN}$(du -sh "$target" 2>/dev/null | cut -f1)${NC}"
    echo -e "   Processing batch size: ${GREEN}5${NC}"
    
    [[ $file_count -eq 0 ]] && {
        echo -e "\n${YELLOW}[!] No HTML files found${NC}"
        return 0
    }
    
    echo -e "\n${YELLOW}[?] Proceed with viewing files? (y/n)${NC}"
    read -r response
    [[ ! $response =~ ^[Yy]$ ]] && {
        echo -e "\n${BLUE}[-] Operation cancelled${NC}"
        return 0
    }
    
    local index=0
    local batch=1
    
    while (( index < file_count )); do
        echo -e "\n${BOLD}${separator}${NC}"
        echo -e "${BOLD}Batch $batch - Files $((index+1)) to $((index+5 > file_count ? file_count : index+5)) of $file_count${NC}"
        echo -e "${BOLD}${separator}${NC}"
        
        for (( i=0; i<5 && index < file_count; i++, index++ )); do
            local html_file="${files[index]}"
            local windows_path
            windows_path=$(wslpath -w "$html_file")
            
            echo -e "\n${BLUE}[>] Opening file $((index+1))/${file_count}: ${NC}$(basename "$html_file")"
            "/mnt/c/Program Files/BraveSoftware/Brave-Browser/Application/brave.exe" "$windows_path" &
        done
        
        wait # Wait for browser processes
        
        (( index < file_count )) && {
            echo -e "\n${YELLOW}[?] Press [Enter] for next batch, [q] to quit${NC}"
            read -r input
            [[ $input = "q" ]] && {
                echo -e "\n${BLUE}[*] Viewer terminated by user${NC}"
                return 0
            }
        }
        
        ((batch++))
    done
    
    echo -e "\n${GREEN}[û] Processing complete!${NC}"
    echo -e "${BOLD}${separator}${NC}"
    echo -e "       Files processed: $file_count"
    echo -e "       Batches completed: $((batch-1))"
    echo -e "${BOLD}${separator}${NC}\n"
}
