# shellcheck shell=bash
# ------------------------------------------------------------------------------
# TITLE   : MC config tools (07_config_tools.sh)
# PURPOSE : mc_config -- inspect the framework's MC_* settings together with the
#           "##" documentation defined in 00_config.sh.
# DEPENDS : lib/config_inspect.awk, the msg_* helpers (03_message.sh), awk,
#           and bash 4.3+ (namerefs are used to expand array settings by name).
# USAGE   : mc_config list | get <name> | doc <name> | dump | -h
# ------------------------------------------------------------------------------

# Emit the settings registry (NAME<TAB>TYPE<TAB>DOC) by parsing 00_config.sh.
_mc_config_registry() {
    local config_file="$MC_ROOT/bash/00_config.sh"
    local awk_script="$MC_ROOT/lib/config_inspect.awk"
    if [[ ! -f "$config_file" ]]; then
        msg_error "mc_config: config file not found: $config_file"
        return 1
    fi
    if [[ ! -f "$awk_script" ]]; then
        msg_error "mc_config: parser not found: $awk_script"
        return 1
    fi
    awk -f "$awk_script" "$config_file"
}

# Print a setting's live value. Args: <name> <type> <prefix>. Arrays print one
# element per line; the prefix is prepended to each output line.
_mc_config_print_value() {
    local name="$1"
    local kind="$2"
    local prefix="$3"
    if [[ "$kind" == "array" ]]; then
        local -n _values="$name"
        local element
        for element in "${_values[@]}"; do
            printf '%s%s\n' "$prefix" "$element"
        done
    else
        printf '%s%s\n' "$prefix" "${!name}"
    fi
}

mc_config() {
    local subcommand="${1:-}"
    local target="${2:-}"

    case "$subcommand" in
        list)
            _mc_config_registry | cut -f1
            ;;
        doc)
            if [[ -z "$target" ]]; then
                msg_error "mc_config doc: needs a setting name"
                return 1
            fi
            local name type doc found=""
            while IFS=$'\t' read -r name type doc; do
                if [[ "$name" == "$target" ]]; then
                    printf '%s\n' "$doc"
                    found="yes"
                    break
                fi
            done < <(_mc_config_registry)
            if [[ -z "$found" ]]; then
                msg_error "mc_config doc: unknown setting: $target"
                return 1
            fi
            ;;
        get)
            if [[ -z "$target" ]]; then
                msg_error "mc_config get: needs a setting name"
                return 1
            fi
            if [[ ! "$target" =~ ^MC_[A-Za-z0-9_]+$ ]]; then
                msg_error "mc_config get: invalid setting name: $target"
                return 1
            fi
            local decl
            if ! decl="$(declare -p "$target" 2>/dev/null)"; then
                msg_error "mc_config get: setting is unset: $target"
                return 1
            fi
            if [[ "$decl" == "declare -a"* || "$decl" == "declare -A"* ]]; then
                _mc_config_print_value "$target" "array" ""
            else
                _mc_config_print_value "$target" "scalar" ""
            fi
            ;;
        dump)
            local name type doc
            while IFS=$'\t' read -r name type doc; do
                printf '%s (%s)\n' "$name" "$type"
                [[ -n "$doc" ]] && printf '  doc: %s\n' "$doc"
                _mc_config_print_value "$name" "$type" "  = "
            done < <(_mc_config_registry)
            ;;
        ""|-h|--help)
            printf 'Usage: mc_config <command>\n'
            printf '  list          List all MC_* setting names\n'
            printf '  get <name>    Print a setting value (arrays: one per line)\n'
            printf '  doc <name>    Print a setting documentation string\n'
            printf '  dump          Print every setting with its type, doc, and value\n'
            ;;
        *)
            msg_error "mc_config: unknown command: $subcommand (try: mc_config -h)"
            return 1
            ;;
    esac
}
