#!/bin/bash

[[ -z "$_BASH_UTILS_INITIALIZED" ]] && source "${BASH_SOURCE%/*}/../init.sh"

display_message() {
    local type="$1"
    local message="$2"

    # Check if the type exists as a key in the array
    if [[ -v "OUTPUT_SYMBOLS[$type]" ]]; then # -v checks if the variable exists
        echo "${OUTPUT_SYMBOLS[$type]}$message"
    else
        # Handle the error: Provide a default message or log an error
        echo "[UNKNOWN MESSAGE TYPE] $message (Type: $type)" >&2 # Output to stderr
        # OR:
        # echo "[ERROR] Invalid message type: $type" >&2
        # return 1 # Return an error code if you want to stop execution
    fi
}
