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
