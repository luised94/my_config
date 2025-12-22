
_msg() {
  if [[ $# -lt 3 ]]; then
    printf "ERROR: _msg requires at least three arguments.\n"
    return 1
  fi

    local level=$1
    local level_num=$2
    local color=$3
    shift 3

    # Validation: Ensure level_num is actually a digit to prevent script errors
    if [[ ! "$level_num" =~ ^[0-9]+$ ]]; then
        return 1
    fi

  # Exit early if below threshold.
  if [[ $MC_VERBOSITY -lt $level_num ]]; then
    return 0

  fi

  # Message Check: If no message is left after shift, don't print anything
  if [[ -z "$*" ]]; then
    printf "ERROR: _msg called with no message.\n"
    return 1

  fi

  printf "%b[%s] %s%b\n" \
    "$color" \
    "$level" \
    "$*" \
    "$_MC_COLOR_RESET" >&2
}

msg_error() { _msg "ERROR" 1 "$_MC_COLOR_ERROR" "$@"; }
msg_warn()  { _msg "WARN" 2 "$_MC_COLOR_WARN"  "$@"; }
msg_info()  { _msg "INFO" 3 "$_MC_COLOR_INFO"  "$@"; }
msg_debug() { _msg "DEBUG" 4 "$_MC_COLOR_DEBUG" "$@"; }
