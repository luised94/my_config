# ------------------------------------------------------------------------------
# TITLE      : MC WSL Platform Logic (02_wsl.sh)
# PURPOSE    : Handles Windows interop, Dropbox path detection, and WSL-specific vars.
# CONTEXT    : Sourced by .bashrc; skipped if not on WSL.
# DATE       : 2025-12-22
# ------------------------------------------------------------------------------

# 1. Guard: Exit immediately if not a WSL environment
[[ -z "$WSL_DISTRO_NAME" ]] && return 0

# 2. Extract Windows Identity
# Note: Use _MC prefix for internal local discovery; export the final public result
_MC_WIN_USER=$(cmd.exe /C "echo %USERNAME%" 2>/dev/null | tr -d '\r\n')

if [[ -z "$_MC_WIN_USER" ]]; then
    printf "[ERROR] WSL Logic: Unable to identify Windows user.\n" >&2
    return 1
fi

export MC_WINDOWS_USER="$_MC_WIN_USER"

# 3. Dropbox Path Resolution
# Use the preference from 00_config.sh (e.g., "MIT Dropbox/Luis Martinez")
# If it's not defined yet, we'll default to the known current value.
_MC_DB_SUBPATH="${MC_DROPBOX_SUBPATH:-MIT Dropbox/Luis Martinez}"
_MC_C_DRIVE="/mnt/c/Users/$_MC_WIN_USER"

# Procedural Path Probing: Try the specific subpath first, then the generic fallback
_MC_PROBED_PATH="$_MC_C_DRIVE/$_MC_DB_SUBPATH"

if [[ ! -d "$_MC_PROBED_PATH" ]]; then
    _MC_PROBED_PATH="$_MC_C_DRIVE/Dropbox (MIT)"
fi

# 4. Final Validation and Export
if [[ -d "$_MC_PROBED_PATH" ]]; then
    export MC_DROPBOX_PATH="$_MC_PROBED_PATH"
else
    printf "[ERROR] WSL Logic: Dropbox not found at: %s\n" "$_MC_C_DRIVE/..." >&2
fi

# 5. Clean up environment
unset _MC_WIN_USER _MC_DB_SUBPATH _MC_C_DRIVE _MC_PROBED_PATH
