# shellcheck shell=bash
# VERSION: 1
# ------------------------------------------------------------------------------
# TITLE      : MC message engine (lib/message.sh)
# PURPOSE    : Centralized, level-filtered, colorized logging. Provides the
#              internal _msg engine and the public msg_info/msg_warn/msg_error/
#              msg_debug wrappers.
# CONTRACT   : Public function names, their stderr routing, and verbosity gating
#              are frozen; callers across the framework depend on them.
# SELF-CONTAINED : Does not require 00_config.sh to have run. It defaults
#              MC_VERBOSITY and defines the color palette itself if not already
#              set, so it can be sourced standalone (e.g. by lib/message.test.sh).
# USAGE      : source "$MC_ROOT/lib/message.sh"; msg_info "Hello"
# DEPENDS    : printf, tput (optional), bash 4.0+
# ------------------------------------------------------------------------------

# Idempotent load guard: a second source is a no-op.
if [[ -n "${_MC_LIB_MESSAGE_LOADED:-}" ]]; then
    return 0
fi
_MC_LIB_MESSAGE_LOADED=1

# Default verbosity if the config has not set it. The engine also defaults
# inline below, so this does not change behavior; it just makes the value
# concrete when the library is sourced on its own.
: "${MC_VERBOSITY:=3}"

# Color palette. Defined here so the engine is self-contained. Only initialized
# if not already set, so a palette established earlier in the chain (00_config)
# is preserved rather than clobbered.
if [[ -z "${_MC_COLOR_RESET:-}" ]]; then
    _MC_COLOR_RESET=$(tput sgr0 2>/dev/null || printf '\033[0m')

    if [ -t 2 ] && [ -n "${TERM:-}" ] && [ "${TERM:-}" != "dumb" ]; then
        _MC_COLOR_ERROR=$(tput setaf 1 2>/dev/null || printf '\033[0;31m')
        _MC_COLOR_WARN=$(tput setaf 3 2>/dev/null || printf '\033[0;33m')
        _MC_COLOR_INFO=$(tput setaf 6 2>/dev/null || printf '\033[0;36m')
        _MC_COLOR_DEBUG=$(tput setaf 8 2>/dev/null || printf '\033[0;90m')

        # Safety check for tput validity
        if printf "%s" "$_MC_COLOR_RESET" | grep -q 'tput: unknown'; then
            _MC_COLOR_ERROR='' _MC_COLOR_WARN='' _MC_COLOR_INFO='' _MC_COLOR_DEBUG=''
        fi
    else
        _MC_COLOR_ERROR='' _MC_COLOR_WARN='' _MC_COLOR_INFO='' _MC_COLOR_DEBUG=''
    fi
fi

# ------------------------------------------------------------------------------
# TITLE      : _msg (Internal Logging Engine)
# PURPOSE    : Centralized output handler with level filtering and color support.
# INIT       : Requires MC_VERBOSITY and _MC_COLOR_* variables to be defined.
# USAGE      : Internal: _msg "LEVEL" "PRIORITY" "COLOR_CODE" "Message"
#              External: source mc_config.sh && msg_info "Hello"
# DEPENDS    : printf, tput, bash 4.0+
# DATE       : 2025-12-22
# ------------------------------------------------------------------------------
_msg() {
  if [[ $# -lt 3 ]]; then
    printf "ERROR: _msg requires Level, Num, and Color arguments.\n"
    printf "ERROR: Only $# arguments passed.\n"
    return 1
  fi

  local level=$1
  local level_num=$2
  local color=$3
  shift 3

  # Validation: Ensure level_num is actually a digit to prevent script errors
  if [[ ! "$level_num" =~ ^[0-9]$ ]]; then
    return 1

  fi

  # Exit early if below threshold.
  if [[ ${MC_VERBOSITY:-3} -lt $level_num ]]; then
    return 0

  fi

  # Message Check: If no message is left after shift, don't print anything
  if [[ -z "$*" ]]; then
    printf "%b[WARN ] _msg called with empty message%b\n" \
    "$_MC_COLOR_WARN" \
    "$_MC_COLOR_RESET" >&2
    return 0

  fi

  # Color Integrity Check: Ensure it looks like an ANSI escape code
  # If it doesn't start with ESC (ASCII 27), we strip it to prevent printing garbage
  if [[ -n "$color" && ! "$color" =~ ^$'\E' ]]; then
    color=""

  fi

  local trace=""
  if [[ ${MC_VERBOSITY:-0} -ge 5 ]]; then
    # FUNCNAME[1] is _msg, FUNCNAME[2] is msg_info, FUNCNAME[3] is the caller
    trace="(${FUNCNAME[3]:-main}) "

  fi

  printf "%b[%-5s] %s%s%b\n" \
    "$color" \
    "$level" \
    "$trace" \
    "$*" \
    "$_MC_COLOR_RESET" >&2
}

# ------------------------------------------------------------------------------
# TITLE      : Public Logging Wrappers
# PURPOSE    : Simplify calls to _msg using predefined levels and colors.
# USAGE      : msg_info "Task complete"; msg_error "File not found"
# ------------------------------------------------------------------------------
msg_error() { _msg "ERROR" 1 "$_MC_COLOR_ERROR" "$@"; }
msg_warn()  { _msg "WARN" 2 "$_MC_COLOR_WARN"  "$@"; }
msg_info()  { _msg "INFO" 3 "$_MC_COLOR_INFO"  "$@"; }
msg_debug() { _msg "DEBUG" 4 "$_MC_COLOR_DEBUG" "$@"; }
