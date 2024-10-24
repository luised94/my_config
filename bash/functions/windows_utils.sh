#!/bin/bash

# Function: setup_windows_environment
# Purpose: Determine the username of the windows user. Most important reason is to travel to dropbox location quickly.
# Parameters: None.
# Return: Export windows_user and DROPBOX_PATH variables. Create new functions list_dropbox and search_dropbox.
[[ -z "$_BASH_UTILS_INITIALIZED" ]] && source "${BASH_SOURCE%/*}/../init.sh"
setup_windows_environment() {
    local windows_user
    local dropbox_path
    local max_retries=3
    local retry_count=0

    # Function to get Windows username
    get_windows_username() {
        windows_user=$(cmd.exe /C "echo %USERNAME%" 2>/dev/null | tr -d '\r\n')
        if [[ -z "$windows_user" ]]; then
            log_error "Error: Unable to retrieve Windows username." >&2
            return 1
        fi
        log_info "$windows_user"
    }

    # Try to get Windows username with retries
    while [[ $retry_count -lt $max_retries ]]; do
        if windows_user=$(get_windows_username); then
            break
        fi
        ((retry_count++))
        sleep 1
    done

    if [[ -z "$windows_user" ]]; then
        log_error "Error: Failed to retrieve Windows username after $max_retries attempts." >&2
        return 1
    fi

    # Set up Dropbox path
    dropbox_path="/mnt/c/Users/${windows_user}/Dropbox (MIT)/"
    if [[ ! -d "$dropbox_path" ]]; then
        log_warning "Warning: Dropbox directory not found at $dropbox_path" >&2
        # Attempt to find Dropbox directory
        local potential_path="/mnt/c/Users/${windows_user}/Dropbox"
        if [[ -d "$potential_path" ]]; then
            dropbox_path="$potential_path/"
            log_info "Found Dropbox at $dropbox_path" >&2
        else
            log_error "Error: Unable to locate Dropbox directory." >&2
            return 1
        fi
    fi

    # Export variables
    export WINDOWS_USER="$windows_user"
    export DROPBOX_PATH="$dropbox_path"

    # Create alias for switching to Windows directory
    alias cdwin='cd "$DROPBOX_PATH"'

    # Optional: Create a function to list contents of Dropbox
    list_dropbox() {
        ls -la "$DROPBOX_PATH"
    }

    # Optional: Create a function to search Dropbox
    search_dropbox() {
        local usage="Usage: search_dropbox [-d depth] [-t filetype] [-c content] [-x exclude] search_term
        -d: Max depth (default: 1)
        -t: File type (e.g., pdf, txt)
        -c: Search file contents
        -x: Exclude directory (can be used multiple times)
        -h: Show this help message"
    
        local depth=1
        local filetype=""
        local content=""
        local exclude_dirs=()
        local OPTIND opt
        while getopts "d:t:c:x:h" opt; do
            case $opt in
                d) depth=$OPTARG ;;
                t) filetype=$OPTARG ;;
                c) content=$OPTARG ;;
                x) exclude_dirs+=("-not -path */$OPTARG/*") ;;
                h) echo "$usage"; return 0 ;;
                *) echo "Invalid option: -$OPTARG" >&2; echo "$usage" >&2; return 1 ;;
            esac
        done
        shift $((OPTIND-1))
    
        if [[ $# -eq 0 ]]; then
            log_error "Error: No search term provided." >&2
            echo "$usage" >&2
            return 1
        fi
    
        local search_term=$1
        local find_args=("$DROPBOX_PATH" -maxdepth "$depth" "${exclude_dirs[@]}")
    
        if [[ -n $filetype ]]; then
            find_args+=(-name "*.$filetype")
        fi
    
        if [[ -n $content ]]; then
            find "${find_args[@]}" -type f -print0 | xargs -0 grep -l "$content" | grep -i "$search_term"
        else
            find "${find_args[@]}" -iname "*$search_term*" -type f
        fi
    }

    echo "Windows environment setup complete."
    echo "Use 'cdwin' to navigate to your Dropbox directory."
    echo "Use 'list_dropbox' to list contents of your Dropbox."
    echo "Use 'search_dropbox <term>' to search your Dropbox."
}
