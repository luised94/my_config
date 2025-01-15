
directorystats() {
    local target="${1:-$(pwd)}"
    local width=$(tput cols)
    local separator=$(printf '%*s' "$width" '' | tr ' ' '=')
    local sub_separator=$(printf '%*s' "$width" '' | tr ' ' '-')
    
    # Color definitions
    local RED='\033[0;31m'
    local GREEN='\033[0;32m'
    local BLUE='\033[0;34m'
    local YELLOW='\033[1;33m'
    local NC='\033[0m' # No Color
    local BOLD='\033[1m'
    
    echo -e "\n${BOLD}${separator}${NC}"
    printf "${BOLD}>> Directory Statistics for: ${BLUE}%s${NC}\n" "$target"
    echo -e "${BOLD}${separator}${NC}"
    
    # Storage statistics
    printf "\n${BOLD}[*] Storage Usage:${NC}\n"
    printf "%s\n" "${sub_separator}"
    du -sh "$target" 2>/dev/null | awk '{printf "   %-15s %s\n", $2, $1}'
    
    # Detailed storage by subdirectories (top 5)
    echo -e "\n${BOLD}[*] Largest Subdirectories:${NC}\n"
    printf "%s\n" "${sub_separator}"
    du -h "$target"/* 2>/dev/null | sort -hr | head -n 5 | \
        awk '{printf "   %-50s %s\n", $2, $1}'
    
    # File counts
    printf "\n${BOLD}[+] File Statistics:${NC}\n"
    printf "%s\n" "${sub_separator}"
    find "$target" -type f 2>/dev/null | wc -l | \
        awk '{printf "   %-20s %'"'"'d files\n", "Total:", $1}'
    find "$target" -type d 2>/dev/null | wc -l | \
        awk '{printf "   %-20s %'"'"'d dirs\n", "Directories:", $1}'
    
    # Time-based statistics
    echo -e "\n${BOLD}[>] Time Statistics:${NC}\n"
    printf "%s\n" "${sub_separator}"
    find "$target" -type f -printf '%TY-%Tm-%Td %TH:%TM:%TS %p\n' 2>/dev/null | \
        awk '
        BEGIN {
            newest = "1970-01-01 00:00:00"
            oldest = "9999-12-31 23:59:59"
        }
        {
            datetime = $1 " " $2
            if (datetime > newest) newest = datetime
            if (datetime < oldest) oldest = datetime
        }
        END {
            printf "   %-20s %s\n", "Newest file:", newest
            printf "   %-20s %s\n", "Oldest file:", oldest
        }'
    
    # Extension distribution
    printf "\n${BOLD}[>] Extension Distribution:${NC}\n"
    printf "%s\n" "${sub_separator}"
    find "$target" -type f 2>/dev/null | awk -F. '
        NF>1 {ext=$NF} 
        NF==1 {ext="[no extension]"}
        {count[ext]++}
        END {
            for (ext in count) {
                printf "   %-15s %d files\n", ext ":", count[ext]
            }
        }' | sort -rn -k2 | head -n 10
    
    # Log file pattern analysis (if logs are present)
    if find "$target" -type f -name "*.log" 2>/dev/null | grep -q .; then
        printf "\n${BOLD}[#] Log Analysis:${NC}\n"
        printf "%s\n" "${sub_separator}"
        find "$target" -type f -name "*.log" -exec grep -h "\[.*\] \[.*\]" {} \; 2>/dev/null | \
            awk '
            match($0, /\[(INFO|WARNING|ERROR|DEBUG)\]/) {
                level = substr($0, RSTART+1, RLENGTH-2)
                count[level]++
                total++
            }
            END {
                printf "   %-15s %d entries\n", "Total:", total
                printf "%s\n", "   " separator
                for (level in count) {
                    percentage = (count[level] / total) * 100
                    printf "   %-15s %d entries (%.1f%%)\n", level ":", count[level], percentage
                }
            }' | sort -r
    fi

    echo -e "\n${BOLD}${separator}${NC}\n"
}
