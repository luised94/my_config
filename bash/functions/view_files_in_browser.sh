#!bin/bash
parse_date_string() {
    local date_str=$1
    local -n parsed_timestamp_ref=$2
    
    # Standardized formats
    case $date_str in
        [0-9][0-9][0-9][0-9][0-9][0-9][0-9][0-9]) # YYYYMMDD
            parsed_timestamp_ref=$(date -d "${date_str:0:4}-${date_str:4:2}-${date_str:6:2}" +%s 2>/dev/null)
            ;;
        [0-9][0-9][0-9][0-9][0-9][0-9][0-9][0-9]_[0-9][0-9][0-9][0-9][0-9][0-9]) # YYYYMMDD_HHMMSS
            parsed_timestamp_ref=$(date -d "${date_str:0:4}-${date_str:4:2}-${date_str:6:2} ${date_str:9:2}:${date_str:11:2}:${date_str:13:2}" +%s 2>/dev/null)
            ;;
        today|yesterday)
            parsed_timestamp_ref=$(date -d "$date_str 00:00:00" +%s)
            ;;
        last_week)
            parsed_timestamp_ref=$(date -d "1 week ago 00:00:00" +%s)
            ;;
        last_month)
            parsed_timestamp_ref=$(date -d "1 month ago 00:00:00" +%s)
            ;;
        [0-9]*d)
            local num=${date_str%d}
            parsed_timestamp_ref=$(date -d "$num days ago 00:00:00" +%s)
            ;;
        [0-9]*w)
            local num=${date_str%w}
            parsed_timestamp_ref=$(date -d "$num weeks ago 00:00:00" +%s)
            ;;
        [0-9]*m)
            local num=${date_str%m}
            parsed_timestamp_ref=$(date -d "$num months ago 00:00:00" +%s)
            ;;
        *)
            return 1
            ;;
    esac
    
    [[ -n "$parsed_timestamp_ref" ]] && return 0 || return 1
}

filter_files_by_time() {
    local -n files_ref=$1
    local time_filter=$2
    local comparison=${3:-after}  # 'after' or 'before'
    
    local target_timestamp
    if ! parse_date_string "$time_filter" target_timestamp; then
        echo "Invalid time format: $time_filter" >&2
        return 1
    fi
    
    if [[ $? -ne 0 ]]; then
        return 1
    fi
    
    local -a filtered_files=()
    local file_timestamp
    for file in "${files_ref[@]}"; do
        file_timestamp=$(stat -c %Y "$file")
        if [[ "$comparison" == "after" && $file_timestamp -ge $target_timestamp ]] || \
           [[ "$comparison" == "before" && $file_timestamp -le $target_timestamp ]]; then
            filtered_files+=("$file")
        fi
    done
    
    files_ref=("${filtered_files[@]}")
}
# ============================================================================
# view_files.sh
# ----------------------------------------------------------------------------
# Purpose:
#   Browse HTML/SVG files in batches using system browsers from WSL/Linux
#
# Usage:
#   view_files [-t type] [-f filter] [-x exclude] [-b batch_size] [-d depth] directory
#
# Options:
#   -t  File type (html, svg) [default: html]
#   -d  Search depth [default: 3]
#   ...
#
# Returns:
#   0 on success, 1 on error
#
# Examples:
#   view_files -t html -d 5 ~/logs
#   view_files -t svg -b 10 ~/plots
#
# Dependencies:
#   - wslpath (WSL environments)
#   - find
#   - A compatible web browser
#
# Notes:
#   - WSL-specific functionality for browser detection
#   - Falls back to xdg-open on Linux
#
# Author: [Your Name]
# Date: [Creation Date]
# Version: 1.0.0
# ============================================================================
view_files() {
    local width=$(tput cols)
    local separator=$(printf '%*s' "$width" '' | tr ' ' '=')
    
    local usage="Usage: view_files [-t type] [-f filter] [-x exclude] [-b batch_size] [-d depth] [-s sort_order] [-a after_time] [-B before_time] [-v] [-h] directory
Options:
    -t, --type     File type (e.g., html, svg, pdf) [default: html]
    -f, --filter   Include pattern
    -x, --exclude  Exclude pattern
    -b, --batch    Batch size [default: 5]
    -d, --depth    Search depth [default: 3]
    -s, --sort     Sort order (alpha, rev) [default: alpha]
    -a, --after    Show files after time (YYYYMMDD, YYYYMMDD_HHMMSS, Nd/w/m ago, today, yesterday)
    -B, --before   Show files before time (same format as -a)
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
    if [[ ! -f $browser ]]; then
        browser="/mnt/c/Program Files (x86)/BraveSoftware/Brave-Browser/Application/brave.exe"
    fi
    [ ! -f "$browser" ] && {
        echo "Browser exe does not exist in both of the Program Files directories."
        echo -e "${RED}[ERROR] Browser not found at specified path${NC}"
        return 1
    }

    # Add time filter variables
    local time_after=""
    local time_before=""

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
    while getopts ":t:f:x:b:d:s:a:B:vh" opt; do
        case $opt in
            t)  
                if is_valid_filetype "$OPTARG"; then
                    type=$OPTARG
                else
                    echo -e "${YELLOW}[WARNING] Invalid file type '$OPTARG'. Using default: html${NC}"
                    echo -e "${YELLOW}Note: Currently supported types are: html, svg, pdf${NC}"
                    echo -e "${YELLOW}For other file types, please test manually first${NC}"
                    type="html"
                fi
                ;;
            f)  
                if is_safe_pattern "$OPTARG"; then
                    filter=$OPTARG
                else
                    echo -e "${YELLOW}[WARNING] Invalid filter pattern '$OPTARG'. Pattern contains unsafe characters${NC}"
                    filter=""
                fi
                ;;
            x)  
                if is_safe_pattern "$OPTARG"; then
                    exclude=$OPTARG
                else
                    echo -e "${YELLOW}[WARNING] Invalid exclude pattern '$OPTARG'. Pattern contains unsafe characters${NC}"
                    exclude=""
                fi
                ;;
            b)  
                if is_positive_integer "$OPTARG"; then
                    batch_size=$OPTARG
                else
                    echo -e "${YELLOW}[WARNING] Invalid batch size '$OPTARG'. Using default: 5${NC}"
                    batch_size=5
                fi
                ;;
            d)  
                if is_positive_integer "$OPTARG"; then
                    depth=$OPTARG
                else
                    echo -e "${YELLOW}[WARNING] Invalid depth '$OPTARG'. Using default: 3${NC}"
                    depth=3
                fi
                ;;
            s)  
                if is_valid_sort_order "$OPTARG"; then
                    sort_order=$OPTARG
                else
                    echo -e "${YELLOW}[WARNING] Invalid sort order '$OPTARG'. Using default: alpha${NC}"
                    echo -e "${YELLOW}Valid options are: alpha, rev${NC}"
                    sort_order="alpha"
                fi
                ;;
            a)  
                local timestamp
                if parse_date_string "$OPTARG" timestamp; then
                    time_after=$OPTARG
                else
                    echo -e "${YELLOW}[WARNING] Invalid after-time format '$OPTARG'. Ignoring time filter${NC}"
                    time_after=""
                fi
                ;;
            B)  
                local timestamp
                if parse_date_string "$OPTARG" timestamp; then
                    time_before=$OPTARG
                else
                    echo -e "${YELLOW}[WARNING] Invalid before-time format '$OPTARG'. Ignoring time filter${NC}"
                    time_before=""
                fi
                ;;
            v) verbose=1 ;;
            h) 
                echo -e "\n${BOLD}${separator}"
                echo -e "${usage}\n"
                echo -e "${separator}${NC}\n"
                return 0
                ;;
            \?)
                echo -e "\n${BOLD}${separator}"
                echo -e "${RED}[ERROR] Invalid option: -$OPTARG${NC}"
                echo -e "${usage}"
                echo -e "${separator}${NC}\n"
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
    local target=$(realpath -s "${1:-$(pwd)}")
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
        
        local cmd=(-maxdepth "$depth" -type f)
        
        # Use explicit quoting for patterns (safe for special characters)
        [[ -n "$type" ]] && cmd+=(-name "*.${type}")
        
        if [[ -n "$filter" ]]; then
            cmd+=(-a -name "*${filter}*")
        fi
        
        if [[ -n "$exclude" ]]; then
            cmd+=(! -name "*${exclude}*")
        fi
        
        # Print each argument on separate line for safe parsing
        printf '%s\n' "${cmd[@]}"
    }
    # Build find command with diagnostic output
    #local find_args=("-maxdepth" "$depth" "-type" "f")
    #[[ -n "$type" ]] && find_args+=("-name" "*.$type")
    #[[ -n "$filter" ]] && find_args+=("-a" "-name" "*${filter}*")
    #[[ -n "$exclude" ]] && find_args+=("!" "-name" "*${exclude}*")

    # Find files using properly constructed command
    local find_args
    mapfile -t find_args < <(build_find_command "$depth" "$type" "$filter" "$exclude")
    #find_args=($(build_find_command "$depth" "$type" "$filter" "$exclude"))


    # Required command checks
    command -v wslpath >/dev/null 2>&1 || {
        echo -e "${RED}[ERROR] wslpath not found${NC}"
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

    if [[ -n "$time_after" ]]; then
        if ! filter_files_by_time files "$time_after" "after"; then
            echo -e "${RED}[ERROR] Failed to apply 'after' time filter${NC}"
            return 1
        fi
    fi
    
    if [[ -n "$time_before" ]]; then
        if ! filter_files_by_time files "$time_before" "before"; then
            echo -e "${RED}[ERROR] Failed to apply 'before' time filter${NC}"
            return 1
        fi
    fi

    local file_count=${#files[@]}
    if (( verbose )); then
        echo -e "\n${BOLD}${YELLOW}[DEBUG] Verbose Output:${NC}"
        echo -e "  Target path: ${GREEN}$target${NC}"
        echo -e "  Find command: find \"$target\" ${find_args[*]}"
        echo -e "  File count: ${GREEN}${#files[@]}${NC}"
        echo -e "  First 3 files:"
        [ $file_count -gt 0 ] && printf '    %s\n' "${files[@]:0:3}"
        echo -e "${BOLD}${YELLOW}---------------------${NC}\n"
    fi
    
    # No files found - provide helpful diagnostics
    if [ $file_count -eq 0 ]; then
        echo -e "\n${YELLOW}[!] No matching files found${NC}"
        echo -e "\nTroubleshooting suggestions:"
        echo -e "1. Current depth is set to ${BOLD}$depth${NC}. Try increasing with: -d option"
        echo -e "2. Looking for ${BOLD}*.$type${NC} files. Check if this is correct"
        [[ -n "$time_after" ]]  && echo -e "3. After time filter: ${BOLD}$time_after${NC}"
        [[ -n "$time_before" ]] && echo -e "4. Before time filter: ${BOLD}$time_before${NC}"
        echo -e "5. Run with -v flag for verbose output"
        echo -e "${YELLOW}6. Make sure the directory is the last argument${NC}"
        
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
    
    local browser_delay=0.5  # Seconds between browser launches
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
            sleep "$browser_delay"
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
    
    echo -e "\n${GREEN}[Yay] Processing complete!${NC}"
    echo -e "${BOLD}${separator}${NC}"
    echo -e "       Files processed: $file_count"
    echo -e "       Batches completed: $((batch-1))"
    echo -e "${BOLD}${separator}${NC}\n"
}

#debug_view_files() {
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
#    # Stage 1: Argument Processing
#    echo -e "\n${BOLD}${separator}"
#    printf "${BOLD}DEBUG STAGE 1: Argument Processing${NC}\n"
#    echo -e "${separator}\n"
#    
#    printf "Raw arguments received:\n${sub_separator}\n"
#    printf "   Count: %d\n" $#
#    printf "   Values: %s\n" "$@"
#
#    # Initialize variables
#    local type="html"
#    local filter=""
#    local exclude=""
#    local batch_size=5
#    local depth=1
#    local sort_order="alpha"
#    local verbose=0
#    local target=""
#
#    # Stage 2: Option Parsing
#    echo -e "\n${BOLD}${separator}"
#    printf "${BOLD}DEBUG STAGE 2: Option Parsing${NC}\n"
#    echo -e "${separator}\n"
#
#    local OPTIND opt
#    while getopts ":t:f:x:b:d:s:vh" opt; do
#        case $opt in
#            t) 
#                type=$OPTARG
#                printf "   Option -t: type set to '%s'\n" "$type"
#                ;;
#            f) 
#                filter=$OPTARG
#                printf "   Option -f: filter set to '%s'\n" "$filter"
#                ;;
#            x) 
#                exclude=$OPTARG
#                printf "   Option -x: exclude set to '%s'\n" "$exclude"
#                ;;
#            b) 
#                batch_size=$OPTARG
#                printf "   Option -b: batch_size set to '%s'\n" "$batch_size"
#                ;;
#            d) 
#                depth=$OPTARG
#                printf "   Option -d: depth set to '%s'\n" "$depth"
#                ;;
#            s) 
#                sort_order=$OPTARG
#                printf "   Option -s: sort_order set to '%s'\n" "$sort_order"
#                ;;
#            v) 
#                verbose=1
#                printf "   Option -v: verbose mode enabled\n"
#                ;;
#            h) 
#                printf "   Option -h: help requested\n"
#                return 0
#                ;;
#            \?) 
#                printf "   ${RED}Invalid option: -%s${NC}\n" "$OPTARG"
#                return 1
#                ;;
#        esac
#    done
#
#    # Stage 3: Target Directory Processing
#    echo -e "\n${BOLD}${separator}"
#    printf "${BOLD}DEBUG STAGE 3: Target Directory Processing${NC}\n"
#    echo -e "${separator}\n"
#
#    shift $((OPTIND-1))
#    target="${1:-$(pwd)}"
#    
#    printf "After option processing:\n${sub_separator}\n"
#    printf "   OPTIND: %d\n" "$OPTIND"
#    printf "   Remaining args: %s\n" "$@"
#    printf "   Target directory: %s\n" "$target"
#    printf "   Directory exists: %s\n" "$([ -d "$target" ] && echo 'yes' || echo 'no')"
#
#    # Stage 4: Find Command Construction
#    echo -e "\n${BOLD}${separator}"
#    printf "${BOLD}DEBUG STAGE 4: Find Command Construction${NC}\n"
#    echo -e "${separator}\n"
#
#    local find_cmd="find \"$target\" -maxdepth $depth -type f -name \"*.$type\""
#    [[ -n "$filter" ]] && find_cmd+=" -a -name \"*${filter}*\""
#    [[ -n "$exclude" ]] && find_cmd+=" ! -name \"*${exclude}*\""
#
#    printf "Constructed find command:\n${sub_separator}\n"
#    printf "   %s\n" "$find_cmd"
#
#    # Stage 5: File Finding Execution
#    echo -e "\n${BOLD}${separator}"
#    printf "${BOLD}DEBUG STAGE 5: File Finding Execution${NC}\n"
#    echo -e "${separator}\n"
#
#    printf "Executing find command...\n${sub_separator}\n"
#    local files
#    IFS=$'\n' read -d '' -r -a files < <(eval "$find_cmd" 2>/dev/null | sort)
#    
#    printf "Results:\n"
#    printf "   Found %d files\n" "${#files[@]}"
#    if [ ${#files[@]} -gt 0 ]; then
#        printf "\nFirst 5 files found (if any):\n"
#        for ((i=0; i<5 && i<${#files[@]}; i++)); do
#            printf "   %s\n" "${files[$i]}"
#        done
#    fi
#
#    echo -e "\n${BOLD}${separator}${NC}\n"
#}

detect_browsers() {
    local -A browsers
    local default_browser=""
    
    # WSL-specific detection
    if grep -qi microsoft /proc/version; then
        echo "WSL environment detected, checking Windows browsers..."
        
        # Common Windows browser paths
        local win_paths=(
            "/mnt/c/Program Files/BraveSoftware/Brave-Browser/Application/brave.exe"
            "/mnt/c/Program Files/Mozilla Firefox/firefox.exe"
            "/mnt/c/Program Files/Google/Chrome/Application/chrome.exe"
            "/mnt/c/Program Files (x86)/Microsoft/Edge/Application/msedge.exe"
        )
        
        for path in "${win_paths[@]}"; do
            if [ -f "$path" ]; then
                local browser_name=$(basename "$path" .exe)
                browsers[$browser_name]=$path
                # Set first found browser as default
                [[ -z "$default_browser" ]] && default_browser=$browser_name
            fi
        done
    else
        echo "Linux environment detected, checking system browsers..."
        
        # Linux browser detection
        local linux_browsers=("firefox" "chromium" "google-chrome" "brave-browser")
        
        for browser in "${linux_browsers[@]}"; do
            if command -v "$browser" >/dev/null 2>&1; then
                browsers[$browser]=$(command -v "$browser")
                [[ -z "$default_browser" ]] && default_browser=$browser
            fi
        done
        
        # Check for xdg-open as fallback
        if command -v xdg-open >/dev/null 2>&1; then
            browsers["system"]="xdg-open"
            [[ -z "$default_browser" ]] && default_browser="system"
        fi
    fi
    
    # Return results
    if [ ${#browsers[@]} -eq 0 ]; then
        echo "No browsers found"
        return 1
    fi
    
    echo "Available browsers:"
    for browser in "${!browsers[@]}"; do
        echo "  - $browser: ${browsers[$browser]}"
    done
    echo "Default browser: $default_browser"
    
    # Export results for use in main function
    declare -g AVAILABLE_BROWSERS=("${!browsers[@]}")
    declare -g DEFAULT_BROWSER=$default_browser
    declare -gA BROWSER_PATHS=()
    for k in "${!browsers[@]}"; do
        BROWSER_PATHS[$k]=${browsers[$k]}
    done
}
