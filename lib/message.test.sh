#!/usr/bin/env bash
# ------------------------------------------------------------------------------
# TITLE   : Tests for lib/message.sh
# PURPOSE : Assert the public logging contract: functions exist, verbosity
#           gating works, output is routed to stderr, and re-sourcing is a
#           no-op. Exits nonzero on any failure.
# USAGE   : bash lib/message.test.sh
# ------------------------------------------------------------------------------
set -u

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=./message.sh
source "$script_dir/message.sh"

tests_run=0
tests_failed=0

# check <description> <expected> <actual>
check() {
    tests_run=$((tests_run + 1))
    if [[ "$2" == "$3" ]]; then
        printf '  ok   %s\n' "$1"
    else
        printf '  FAIL %s (expected [%s], got [%s])\n' "$1" "$2" "$3"
        tests_failed=$((tests_failed + 1))
    fi
}

# yesno <command...> -> prints "yes" if the captured value is non-empty helper
nonempty() { [[ -n "$1" ]] && printf 'yes' || printf 'no'; }
contains() { printf '%s' "$1" | grep -q "$2" && printf 'yes' || printf 'no'; }

# (a) public functions exist
for fn in _msg msg_info msg_warn msg_error msg_debug; do
    check "function exists: $fn" "function" "$(type -t "$fn")"
done

# (b) verbosity gating
out_info=$(MC_VERBOSITY=1 msg_info "hidden" 2>&1)
check "verbosity 1 suppresses info (level 3)" "" "$out_info"

out_err=$(MC_VERBOSITY=1 msg_error "shown" 2>&1)
check "verbosity 1 permits error (level 1)" "yes" "$(nonempty "$out_err")"

out_dbg4=$(MC_VERBOSITY=4 msg_debug "dbg" 2>&1)
check "verbosity 4 permits debug (level 4)" "yes" "$(nonempty "$out_dbg4")"

out_dbg3=$(MC_VERBOSITY=3 msg_debug "dbg" 2>&1)
check "verbosity 3 suppresses debug (level 4)" "" "$out_dbg3"

# (c) routing: all output goes to stderr; stdout stays empty
out_stdout=$(MC_VERBOSITY=4 msg_info "to-stderr" 2>/dev/null)
check "info writes nothing to stdout" "" "$out_stdout"

err_only=$(MC_VERBOSITY=4 msg_error "err" 2>&1 1>/dev/null)
check "error writes to stderr" "yes" "$(nonempty "$err_only")"

# content sanity: message text and level label appear
out_content=$(MC_VERBOSITY=3 msg_info "hello-world" 2>&1)
check "info output contains message" "yes" "$(contains "$out_content" "hello-world")"
check "info output has INFO label" "yes" "$(contains "$out_content" "INFO")"

# (d) double-source is a no-op (sentinel guard)
before_sentinel="${_MC_LIB_MESSAGE_LOADED:-unset}"
# shellcheck source=./message.sh
source "$script_dir/message.sh"
after_sentinel="${_MC_LIB_MESSAGE_LOADED:-unset}"
check "sentinel set after first load" "1" "$before_sentinel"
check "sentinel stable after re-source" "1" "$after_sentinel"

out_re=$(MC_VERBOSITY=3 msg_info "still-here" 2>&1)
check "msg_info still works after re-source" "yes" "$(contains "$out_re" "still-here")"

# --- summary ---
printf '\n[message.test] %d run, %d failed\n' "$tests_run" "$tests_failed"
[[ "$tests_failed" -eq 0 ]]
