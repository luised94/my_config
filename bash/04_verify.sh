# ------------------------------------------------------------------------------
# TITLE      : MC System Verification (04_verify.sh)
# PURPOSE    : Persistent caching for environment health.
# CONTEXT    : Sourced by .bashrc. Defines and then runs the check.
# ------------------------------------------------------------------------------
mc_verify() {
    # 1. Setup Variables
    local cache_dir="$HOME/.cache/mc"
    local cache_file="$cache_dir/verify_success"
    local config_file="$MC_ROOT/bash/00_config.sh"
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
    #
    # --- Check 2: Dynamic Environment Variables ---
    # Ensures that if EDITOR/BROWSER are set, they point to valid binaries.
    for var in "EDITOR" "BROWSER" "VISUAL"; do
        local val="${!var}" # Indirect expansion
        if [[ -n "$val" ]]; then
             # Handle paths with spaces (common in BROWSER) by checking existence first if it looks like a path
             if [[ "$val" == /* ]]; then
                if [[ ! -e "$val" ]]; then
                    msg_error "Variable \$$var path not found: $val"
                    error_count=$((error_count + 1))
                fi
             else
                if ! command -v "$val" >/dev/null 2>&1; then
                    msg_error "Variable \$$var binary missing: $val"
                    error_count=$((error_count + 1))
                fi
             fi
        fi
    done

    # --- Check 3: Symlink Validation ---
    # Check 3: Symlink Validation
    for link_pair in "${MC_SYMLINKS[@]}"; do
        local src="${link_pair%%:*}"
        local dst="${link_pair#*:}"

        # A. Check existence (Always Error if missing)
        if [[ ! -L "$dst" ]]; then
            msg_error "Symlink missing: $dst"
            error_count=$((error_count + 1))
            continue
        fi

        # B. Check Target
        local actual_src
        actual_src=$(readlink -f "$dst")

        if [[ "$actual_src" != "$src" ]]; then
            # ARE WE IN A WORKTREE?
            # If the expected source contains our worktree path, but the actual link 
            # points to the MAIN repo, that is actually OKAY/EXPECTED.
            # Heuristic: If we are in a worktree, we shouldn't fail global symlinks
            if [[ "$MC_REPO_ROOT" != "$HOME/personal_repos/my_config" ]]; then
                 msg_warn "Symlink mismatch (Worktree Context): $dst points to $actual_src"
                 # Do NOT increment error_count here. It's a warning.
            else
                 # We are in main repo, so it MUST match.
                 msg_error "Symlink mismatch: $dst -> $actual_src (Expected: $src)"
                 error_count=$((error_count + 1))
            fi
        fi
    done

    # --- Check 4: WSL Dependencies ---
    # Only run if we are in a WSL environment
    if [[ -n "$WSL_DISTRO_NAME" ]]; then
        if [[ ! -d "$MC_DROPBOX_PATH" ]]; then
            msg_error "Dropbox path is invalid: $MC_DROPBOX_PATH"
            error_count=$((error_count + 1))
        fi

        for item in "${MC_WSL_DEPS[@]}"; do
            if [[ "$item" == /* ]]; then
                # It's an absolute path (e.g., Windows Browser or executable in Program Files dir)
                if [[ ! -e "$item" ]]; then
                    msg_error "WSL Path missing: $item"
                    error_count=$((error_count + 1))
                fi
            else
                # It's a command (e.g., wslpath)
                if ! command -v "$item" >/dev/null 2>&1; then
                    msg_error "WSL Command missing: $item"
                    error_count=$((error_count + 1))
                fi
            fi
        done

    fi

    # --- Check 5: Finalize ---
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
