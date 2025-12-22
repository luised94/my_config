#!/bin/bash
#!/bin/bash

# --- 1. BOOTSTRAP (Basic reporting before library loads) ---
_ERR='\033[0;31m' _OK='\033[0;32m' _RST='\033[0m'
_report() { printf "[%b%s%b] %s\n" "$1" "$2" "$_RST" "$3"; }

# --- 2. ENVIRONMENT DISCOVERY ---
# Determine root based on TMUX worktrees or default
if [[ -n "$TMUX" ]]; then
    _session=$(tmux display-message -p '#S')
    if [[ "$_session" =~ ^my_config\>(.*) ]]; then
        _possible_root="$HOME/personal_repos/my_config-${BASH_REMATCH[1]}/bash"
        [[ -d "$_possible_root" ]] && BASH_UTILS_ROOT="$_possible_root"
    fi
fi

BASH_UTILS_ROOT="${BASH_UTILS_ROOT:-$HOME/personal_repos/my_config/bash}"
BASH_UTILS_ROOT="${BASH_UTILS_ROOT%/}"

[[ ! -d "$BASH_UTILS_ROOT" ]] && { _report "$_ERR" "FAIL" "Root not found: $BASH_UTILS_ROOT"; exit 1; }

# --- 3. SOURCING ---
FILES_TO_TEST=("00_config.sh" "10_message.sh")

for file in "${FILES_TO_TEST[@]}"; do
    filepath="$BASH_UTILS_ROOT/$file"
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
