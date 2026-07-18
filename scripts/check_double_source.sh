#!/usr/bin/env bash
# ------------------------------------------------------------------------------
# TITLE   : MC double-source idempotency check (scripts/check_double_source.sh)
# PURPOSE : Source the numbered bash chain twice in a clean shell and assert the
#           resulting variable, alias, and PATH state is identical after each
#           pass. Guards the "sourced files must be idempotent" contract.
# USAGE   : bash scripts/check_double_source.sh
# ------------------------------------------------------------------------------

# Re-exec once in a clean, non-interactive shell so the caller's aliases and
# exported variables cannot skew the comparison.
if [[ -z "${_MC_DBLSRC_CLEAN:-}" ]]; then
    export _MC_DBLSRC_CLEAN=1
    exec bash --norc --noprofile "${BASH_SOURCE[0]}" "$@"
fi

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo_root="$(cd "$script_dir/.." && pwd)"
export MC_ROOT="$repo_root"

# WHY no `set -u`: the chain intentionally references some unset variables in
# untaken branches (WSL_DISTRO_NAME, MC_REPO_ROOT). A real interactive shell
# does not run under `set -u`, so neither does this harness.
source_chain() {
    local chain_file
    for chain_file in "$MC_ROOT"/bash/[0-9][0-9]_*.sh; do
        # shellcheck disable=SC1090  # glob-sourced chain; path is not constant
        source "$chain_file"
    done
}

# Capture the state that must be stable across a re-source: declared variables
# and aliases, minus volatile bash internals that legitimately change between
# reads (BASH_*, FUNCNAME, PIPESTATUS, RANDOM, SECONDS, LINENO, and $_).
snapshot() {
    {
        declare -p
        alias
    } 2>/dev/null \
        | grep -vE '\b(BASH_[A-Z]+|FUNCNAME|PIPESTATUS|RANDOM|SECONDS|LINENO|_)='
}

before_file="$(mktemp)"
after_file="$(mktemp)"
trap 'rm -f "$before_file" "$after_file"' EXIT

# Capture both snapshots before introducing any comparison variables, so the
# harness's own bookkeeping cannot appear as spurious drift between the passes.
source_chain >/dev/null 2>&1
snapshot > "$before_file"

source_chain >/dev/null 2>&1
snapshot > "$after_file"

# Everything below runs after both captures, so new variables here are safe.
status=0

# PATH is asserted explicitly: it is the one value the pre-C3 chain could grow
# on re-source. It also appears inside the snapshots, so genuine drift is caught
# twice; this dedicated check just yields a clearer message.
path_before="$(grep -E '^declare -x PATH=' "$before_file" || true)"
path_after="$(grep -E '^declare -x PATH=' "$after_file" || true)"
if [[ "$path_before" != "$path_after" ]]; then
    printf '[double-source] FAIL: PATH grew after the second source.\n' >&2
    printf '  before: %s\n' "$path_before" >&2
    printf '  after : %s\n' "$path_after" >&2
    status=1
fi

if ! diff -u "$before_file" "$after_file" >/dev/null 2>&1; then
    printf '[double-source] FAIL: vars/aliases changed after the second source:\n' >&2
    diff -u "$before_file" "$after_file" >&2
    status=1
fi

if [[ "$status" -eq 0 ]]; then
    printf '[double-source] OK: chain is idempotent under re-source.\n'
fi
exit "$status"
