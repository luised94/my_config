#!/bin/bash

# Standard output formatting symbols for CLI feedback
declare -A OUTPUT_SYMBOLS=(
    ["START"]="=== "    # Indicates start of operation
    ["PROCESSING"]=">>> " # Shows ongoing process
    ["SUCCESS"]="[+] "   # Positive completion
    ["ERROR"]="[X] "     # Error condition
    ["WARNING"]="[?] "   # Warning or attention needed
    ["INFO"]="[*] "      # General information
    ["DONE"]="=== "      # Operation completion
)


#local width=$(tput cols)
#local separator=$(printf '%*s' "$width" '' | tr ' ' '=')
#local sub_separator=$(printf '%*s' "$width" '' | tr ' ' '-')
#local RED='\033[0;31m'
#local GREEN='\033[0;32m'
#local BLUE='\033[0;34m'
#local YELLOW='\033[1;33m'
#local NC='\033[0m'
#local BOLD='\033[1m'
