#!/bin/bash

# Standard output formatting symbols for CLI feedback
declare -A OUTPUT_SYMBOLS=(
    ["START"]="=== "    # Indicates start of operation
    ["PROCESSING"]=">>> " # Shows ongoing process
    ["SUCCESS"]="[+] "   # Positive completion
    ["ERROR"]="[!] "     # Error condition
    ["WARNING"]="[?] "   # Warning or attention needed
    ["INFO"]="[*] "      # General information
    ["DONE"]="=== "      # Operation completion
)
