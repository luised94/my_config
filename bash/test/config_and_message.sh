#!/bin/bash
#!/bin/bash

# --- 1. BOOTSTRAP (Basic reporting before library loads) ---
_ERR='\033[0;31m' _OK='\033[0;32m' _RST='\033[0m'
_report() { printf "[%b%s%b] %s\n" "$1" "$2" "$_RST" "$3"; }

# --- 2. ENVIRONMENT DISCOVERY ---
# Self-locating: derive the repo root from this file's own path so the test
# runs from any checkout (clone, worktree, or arbitrary directory), never from
# $HOME or a hardcoded path. This file lives at bash/test/, so the repo root is
# two directories above its own directory.
_test_directory="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MC_ROOT="$(cd "$_test_directory/../.." && pwd)"
export MC_ROOT

mc_bash_directory="$MC_ROOT/bash"

[[ ! -d "$mc_bash_directory" ]] && { _report "$_ERR" "FAIL" "Root not found: $mc_bash_directory"; exit 1; }

# 03_message.sh sources "$MC_ROOT/lib/message.sh"; MC_ROOT is set above.

# --- 3. SOURCING ---
FILES_TO_TEST=("00_config.sh" "03_message.sh")

for file in "${FILES_TO_TEST[@]}"; do
    filepath="$mc_bash_directory/$file"
    # shellcheck source=/dev/null  # path is built at runtime from FILES_TO_TEST
    if [[ -f "$filepath" ]] && source "$filepath"; then
        _report "$_OK" "LOAD" "$file"
    else
        _report "$_ERR" "FAIL" "Could not source $filepath"
        exit 1
    fi
done

# --- 4. TEST SUITE ---
# Test Level Filtering
echo -e "\n--- TESTING VERBOSITY LEVELS ---"
for v in {0..5}; do
    MC_VERBOSITY=$v
    echo "Level: $MC_VERBOSITY"
    msg_error "Testing Error"
    msg_warn  "Testing Warn"
    msg_info  "Testing Info"
    msg_debug "Testing Debug"
done

# Test Robustness (Boundary Conditions)
echo -e "\n--- TESTING ROBUSTNESS (Boundary Conditions) ---"
_report "$_OK" "TEST" "Zero Args: $(_msg 2>&1)"
_report "$_OK" "TEST" "One Args: $(_msg "ERR" 2>&1)"
_report "$_OK" "TEST" "Two Args: $(_msg "ERR" 1 2>&1)"
_report "$_OK" "TEST" "Empty Msg: $(_msg "INFO" 3 "$_MC_COLOR_INFO" 2>&1)"

echo -e "\n${_OK}ALL TESTS COMPLETE${_RST}"
