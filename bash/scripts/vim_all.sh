#!/bin/bash

[[ -z "$_BASH_UTILS_INITIALIZED" ]] && source "${BASH_SOURCE%/*}/../init.sh"

# Main script wrapper for vim_all function
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    # Script is being run directly
    vim_all "$@"
fi
