# ------------------------------------------------------------------------------
# TITLE      : MC System Verification (04_verify.sh)
# PURPOSE    : Persistent caching for environment health.
# CONTEXT    : Sourced by .bashrc. Defines and then runs the check.
# ------------------------------------------------------------------------------
mc_verify() {
    # 1. Setup Variables
    local cache_dir="$HOME/.cache/mc"
    local cache_file="$cache_dir/verify_success"
    local config_file="$MC_ROOT/00_config.sh"
    local force_check="false"

    # Check for force flag
    if [[ "$1" == "--force" ]]; then
        force_check="true"
    fi

    # 2. Ensure the cache directory exists
    if [[ ! -d "$cache_dir" ]]; then
        mkdir -p "$cache_dir"
    fi

    # 3. Determine if we need to run the actual checks
    local run_now="false"

    if [[ "$force_check" == "true" ]]; then
        run_now="true"
    elif [[ ! -f "$cache_file" ]]; then
        # No cache exists yet
        run_now="true"
    elif [[ "$config_file" -nt "$cache_file" ]]; then
        # Config file is newer than the cache file
        run_now="true"
    fi

    # 4. Execute checks if necessary
    if [[ "$run_now" == "true" ]]; then
        _mc_perform_checks "$cache_file"
    fi
}

_mc_perform_checks() {
    local target_cache_file="$1"
    local error_count=0

    msg_info "Checking system integrity..."

    # --- Check 1: Required Programs ---
    for prog in "${MC_REQUIRED_PROGS[@]}"; do
        if ! command -v "$prog" >/dev/null 2>&1; then
            msg_error "Required program missing: $prog"
            error_count=$((error_count + 1))
        fi
    done

    # --- Check 2: WSL Paths ---
    # Only run if we are in a WSL environment
    if [[ -n "$WSL_DISTRO_NAME" ]]; then
        if [[ ! -d "$MC_DROPBOX_PATH" ]]; then
            msg_error "Dropbox path is invalid: $MC_DROPBOX_PATH"
            error_count=$((error_count + 1))
        fi
    fi

    # --- Check 3: Finalize ---
    if [[ "$error_count" -eq 0 ]]; then
        # Everything passed, update the timestamp
        touch "$target_cache_file"
        msg_debug "Verification successful. Cache updated."
    else
        # Something failed, remove the cache so it prompts again next time
        if [[ -f "$target_cache_file" ]]; then
            rm "$target_cache_file"
        fi
        msg_warn "Verification found $error_count issues."
    fi
}

# --- Auto-Run on Source ---
# This executes the function immediately after defining it.
mc_verify
