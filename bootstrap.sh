#!/usr/bin/env bash
# ------------------------------------------------------------------------------
# TITLE   : MC bootstrap installer (bootstrap.sh)
# PURPOSE : Set up the framework on a new machine from the single source of
#           truth in 00_config.sh: create the symlinks declared in MC_SYMLINKS
#           and report on the programs listed in MC_REQUIRED_PROGS. Dry-run by
#           default; pass --apply to make changes.
# USAGE   : ./bootstrap.sh [--apply] [-h|--help]
# DEPENDS : lib/message.sh, bash/00_config.sh, bash/04_verify.sh; ln, readlink
# NOTE    : Not part of the sourced numbered chain; run manually.
# ------------------------------------------------------------------------------
set -o pipefail

# Resolve the repo root from this script's own location.
MC_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
export MC_ROOT

# Message engine (self-contained) and the settings (MC_SYMLINKS, MC_REQUIRED_PROGS).
# Preserve a caller-supplied verbosity across the 00_config source below, which
# sets its own default, so `MC_VERBOSITY=4 ./bootstrap.sh` can raise the detail.
_bootstrap_verbosity="${MC_VERBOSITY:-}"
# shellcheck source=lib/message.sh
source "$MC_ROOT/lib/message.sh"
# shellcheck source=bash/00_config.sh
source "$MC_ROOT/bash/00_config.sh"
[[ -n "$_bootstrap_verbosity" ]] && MC_VERBOSITY="$_bootstrap_verbosity"

# Install a git pre-commit hook that runs the lint suite. Standalone action.
_bootstrap_install_git_hook() {
    local hook_file="$MC_ROOT/.git/hooks/pre-commit"
    if [[ ! -d "$MC_ROOT/.git" ]]; then
        msg_error "bootstrap: $MC_ROOT is not a git repository; cannot install hook"
        return 1
    fi
    if [[ -e "$hook_file" ]]; then
        msg_warn "bootstrap: pre-commit hook already exists, leaving as-is: $hook_file"
        return 0
    fi
    printf '#!/usr/bin/env bash\nexec "$(git rev-parse --show-toplevel)/scripts/lint.sh"\n' > "$hook_file"
    chmod +x "$hook_file"
    msg_info "bootstrap: installed pre-commit hook (runs scripts/lint.sh)"
}

# --- Argument parsing ---------------------------------------------------------
apply="false"
for arg in "$@"; do
    case "$arg" in
        --apply)
            apply="true"
            ;;
        --install-git-hook)
            if _bootstrap_install_git_hook; then exit 0; fi
            exit 1
            ;;
        -h|--help)
            printf 'Usage: bootstrap.sh [--apply]\n'
            printf '  (default)   Dry run: report required programs and show the\n'
            printf '              symlinks that would be created.\n'
            printf '  --apply     Create the symlinks from MC_SYMLINKS, then run\n'
            printf '              mc_verify --force.\n'
            printf '  --install-git-hook\n'
            printf '              Install a pre-commit hook that runs scripts/lint.sh.\n'
            exit 0
            ;;
        *)
            msg_error "bootstrap: unknown argument: $arg (try --help)"
            exit 1
            ;;
    esac
done

if [[ "$apply" == "true" ]]; then
    msg_info "bootstrap: apply mode (changes will be made)"
else
    msg_info "bootstrap: dry run (no changes); re-run with --apply to make them"
fi

# --- 1. Required-program preflight (MC_REQUIRED_PROGS) -------------------------
msg_info "Checking required programs..."
missing_progs=0
for prog in "${MC_REQUIRED_PROGS[@]}"; do
    if command -v "$prog" >/dev/null 2>&1; then
        msg_debug "  present: $prog"
    else
        msg_warn "  missing: $prog"
        missing_progs=$((missing_progs + 1))
    fi
done
if [[ "$missing_progs" -gt 0 ]]; then
    msg_warn "$missing_progs required program(s) missing; install them and re-run"
fi

# --- 2. Symlinks (MC_SYMLINKS: "source:target" pairs) -------------------------
msg_info "Processing symlinks..."
for pair in "${MC_SYMLINKS[@]}"; do
    src="${pair%%:*}"
    dst="${pair#*:}"

    if [[ ! -e "$src" ]]; then
        msg_error "  source missing, skipping: $src"
        continue
    fi
    if [[ -L "$dst" && "$(readlink "$dst")" == "$src" ]]; then
        msg_debug "  ok (already linked): $dst -> $src"
        continue
    fi
    if [[ -e "$dst" || -L "$dst" ]]; then
        msg_warn "  exists and not our link, leaving as-is: $dst"
        continue
    fi

    if [[ "$apply" == "true" ]]; then
        mkdir -p "$(dirname "$dst")"
        if ln -s "$src" "$dst"; then
            msg_info "  linked: $dst -> $src"
        else
            msg_error "  failed to link: $dst -> $src"
        fi
    else
        msg_info "  would link: $dst -> $src"
    fi
done

# --- 3. Final verification ----------------------------------------------------
if [[ "$apply" == "true" ]]; then
    msg_info "Running verification (mc_verify --force)..."
    # Load the verifier; suppress its source-time auto-run, then run authoritatively.
    # shellcheck source=bash/04_verify.sh
    source "$MC_ROOT/bash/04_verify.sh" >/dev/null 2>&1
    if command -v mc_verify >/dev/null 2>&1; then
        mc_verify --force
    else
        msg_warn "mc_verify unavailable; skipping final verification"
    fi
else
    msg_info "Dry run complete. Re-run with --apply to create the symlinks above."
fi
