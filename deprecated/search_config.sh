# Search configuration
# Do not source directly - use init.sh
# Grep styling
#declare -A GREP_STYLES=(
#    ["MATCH_COLOR"]="01;31"  # Bold red
#    ["LINE_COLOR"]="01;90"   # Bold gray
#    ["FILE_COLOR"]="01;36"   # Bold cyan
#)
#AGGREGATE_REPOSITORY_USAGE="
#Usage: aggregate_repository [options] \"commit message\"
#
#Options:
#  -d|--max-depth N    Maximum directory depth to search
#  -e|--exclude-dir    Additional directory to exclude
#  -f|--exclude-file   Additional file pattern to exclude
#  -v|--verbose        Enable verbose output
#  -q|--quiet         Suppress all output except final counts
#"
#aggregate_repository() {
#    local output_file="repository_aggregate.md"
#    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
#    local verbose=0
#    local quiet=0
#    local max_depth=""
#    
#    # Show usage if no arguments or help flag
#    if [[ $# -eq 0 || "$1" == "-h" || "$1" == "--help" ]]; then
#        echo "${AGGREGATE_REPOSITORY_USAGE}"
#        return 0
#    fi
#    
#    # Initialize arrays for exclusions
#    local exclude_dirs=("${DEFAULT_SEARCH_EXCLUDE_DIRS[@]}")
#    local exclude_files=("${DEFAULT_SEARCH_EXCLUDE_FILES[@]}")
#
#    # Parse command line options
#    while [[ $# -gt 0 ]]; do
#        case "$1" in
#            -d|--max-depth)
#                max_depth="-maxdepth $2"
#                shift 2
#                ;;
#            -e|--exclude-dir)
#                exclude_dirs+=("$2")
#                shift 2
#                ;;
#            -f|--exclude-file)
#                exclude_files+=("$2")
#                shift 2
#                ;;
#            -v|--verbose)
#                verbose=1
#                shift
#                ;;
#            -q|--quiet)
#                quiet=1
#                shift
#                ;;
#            *)
#                break
#                ;;
#        esac
#    done
#
#    # Construct find command exclusions
#    local dir_excludes=""
#    for dir in "${exclude_dirs[@]}"; do
#        dir_excludes="$dir_excludes -not -path '*/$dir/*'"
#    done
#
#    local file_excludes=""
#    for pattern in "${exclude_files[@]}"; do
#        file_excludes="$file_excludes -not -name '$pattern'"
#    done
#
#    # Create aggregate file with header
#    {
#        echo "# Repository Aggregation"
#        echo "Generated: $timestamp"
#        echo "---"
#        echo
#    } > "$output_file"
#
#    # Find and process files
#    local find_command="find . $max_depth -type f $dir_excludes $file_excludes"
#    local file_count=0
#    local total_lines=0
#
#    while IFS= read -r file; do
#        [[ "$file" == "./$output_file" ]] && continue
#
#        [[ $verbose -eq 1 ]] && echo "Processing: $file"
#
#        {
#            echo "## File: $file"
#            echo "\`\`\`${file##*.}"
#            cat "$file"
#            echo "\`\`\`"
#            echo
#        } >> "$output_file"
#
#        ((file_count++))
#        [[ $verbose -eq 1 ]] && total_lines+=$(wc -l < "$file")
#    done < <(eval "$find_command" | sort)
#
#    [[ $quiet -eq 0 ]] && {
#        echo "Repository aggregation complete:"
#        echo "- Files processed: $file_count"
#        [[ $verbose -eq 1 ]] && echo "- Total lines: $total_lines"
#        echo "- Output: $output_file"
#    }
#}

# Usage example:
# aggregate_repository -v -d 3 -e "tests" -f "*.csv" "Initial repository aggregation"
