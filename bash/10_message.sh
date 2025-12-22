
_msg() {
    local level=$1
    local level_num=$2
    local color=$3
    shift 3

    [[ $HELPERS_VERBOSITY -lt $level_num ]] && return 0

    printf "${color}[%s] %s${_COLOR_RESET}\n" "$level" "$*" >&2
}

msg_error() { _msg "ERROR" 1 "$_COLOR_ERROR" "$@"; }
msg_warn()  { _msg "WARN " 2 "$_COLOR_WARN"  "$@"; }
msg_info()  { _msg "INFO " 3 "$_COLOR_INFO"  "$@"; }
msg_debug() { _msg "DEBUG" 4 "$_COLOR_DEBUG" "$@"; }
