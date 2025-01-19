#!/usr/bin/env bash
#!/usr/bin/env bash
# terminal_format.sh - base library
declare -A OUTPUT_SYMBOLS=(
    ["START"]="=== "    # Indicates start of operation
    ["PROCESSING"]=">>> " # Shows ongoing process
    ["SUCCESS"]="[+] "   # Positive completion
    ["ERROR"]="[X] "     # Error condition
    ["WARNING"]="[?] "   # Warning or attention needed
    ["INFO"]="[*] "      # General information
    ["DONE"]="=== "      # Operation completion
)

get_terminal_width() {
    local cols="${COLUMNS:-}"
    if [[ -z "$cols" ]]; then
        if command -v tput &>/dev/null; then
            cols=$(tput cols 2>/dev/null || echo 80)
        else
            cols=80
        fi
    fi
    echo "$cols"
}

make_separator() {
    local width
    width=$(get_terminal_width)
    printf '%*s' "$width" '' | tr ' ' '='
}

make_sub_separator() {
    local width
    width=$(get_terminal_width)
    printf '%*s' "$width" '' | tr ' ' '-'
}

declare -r FMT_RED='\033[0;31m'
declare -r FMT_GREEN='\033[0;32m'
declare -r FMT_BLUE='\033[0;34m'
declare -r FMT_YELLOW='\033[1;33m'
declare -r FMT_BOLD='\033[1m'
declare -r FMT_RESET='\033[0m'
# Map output types to colors
declare -A OUTPUT_COLORS=(
    ["START"]="$FMT_BOLD$FMT_BLUE"
    ["PROCESSING"]="$FMT_BOLD$FMT_YELLOW"
    ["SUCCESS"]="$FMT_BOLD$FMT_GREEN"
    ["ERROR"]="$FMT_BOLD$FMT_RED"
    ["WARNING"]="$FMT_BOLD$FMT_YELLOW"
    ["INFO"]="$FMT_BOLD$FMT_BLUE"
    ["DONE"]="$FMT_BOLD$FMT_GREEN"
)

fmt_echo() {
    local color="$1"
    shift
    printf "%b%s%b\n" "$color" "$*" "$FMT_RESET"
}
# Function: Generic display message using OUTPUT_SYMBOLS
display_message() {
    local type="$1"
    local message="$2"

    # Check if the type exists as a key in OUTPUT_SYMBOLS
    if [[ -v "OUTPUT_SYMBOLS[$type]" ]]; then
        printf "%b%s%b\n" "$FMT_BOLD" "${OUTPUT_SYMBOLS[$type]}$message" "$FMT_RESET"
    else
        printf "%b[WARNING]%b Unknown message type: %s. Message: %s\n" "$FMT_YELLOW" "$FMT_RESET" "$type" "$message"
    fi
}

# Function: Print a header section
print_header() {
    local title="$1"

    local separator
    separator=$(make_separator)
    printf "%b\n" "$FMT_BOLD$separator$FMT_RESET"
    printf "%b %s%b\n" "$FMT_BOLD" "$title" "$FMT_RESET"
    printf "%b\n\n" "$FMT_BOLD$separator$FMT_RESET"
}

# Function: Print a footer separator (to indicate the end of a function call)
print_footer() {
    local separator
    separator=$(make_separator)
    printf "%b\n" "$FMT_YELLOW$separator$FMT_RESET"
}

# Function: Print error messages wrapped in a formatted block
print_error() {
    local message="$1"
    fmt_echo "$FMT_RED" "[ERROR] $message"
}

# Function: Print success messages
print_success() {
    local message="$1"
    fmt_echo "$FMT_GREEN" "[SUCCESS] $message"
}

styled_message() {
    local type="$1"
    local message="$2"

    # Check if the type exists in both OUTPUT_SYMBOLS and OUTPUT_COLORS
    if [[ -v "OUTPUT_SYMBOLS[$type]" && -v "OUTPUT_COLORS[$type]" ]]; then
        local symbol="${OUTPUT_SYMBOLS[$type]}"
        local color="${OUTPUT_COLORS[$type]}"
        printf "%b%s%s%b\n" "$color" "$symbol" "$message" "$FMT_RESET"
    else
        # Default for unknown types
        fmt_echo "$FMT_RED" "[UNKNOWN] $message (Type: $type)"
    fi
}
### Demonstration Area ###

# Example usage of headers and separators.
print_header "Starting Demonstration Script"

# Example: Displaying an info message
display_message "INFO" "This is a general information message."

# Example: Displaying a success message
display_message "SUCCESS" "The operation completed successfully."

# Example: Printing an error message
print_error "Something went wrong here!"

# Example: Printing a success message
print_success "All operations completed correctly."

# Example: Displaying a warning
display_message "WARNING" "This configuration might need attention."

usage="Usage: view_files [-t type] [-f filter] [-x exclude] [-b batch_size] [-d depth] [-s sort_order] [-a after_time] [-B before_time] [-v] [-h] directory
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


# Example: Displaying the footer separator
print_footer

print_header "${usage}"
# Example usage of headers and separators.
print_header "Starting Demonstration Script"

# Example: Displaying an info message
styled_message "INFO" "This is a general information message."

# Example: Displaying a success message
styled_message "SUCCESS" "The operation completed successfully."

# Example: Printing an error message
styled_message "ERROR" "Something went wrong here!"

# Example: Displaying a warning
styled_message "WARNING" "This configuration might need attention."

# Example: Printing a footer separator
print_footer
