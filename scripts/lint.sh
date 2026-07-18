#!/usr/bin/env bash
# ------------------------------------------------------------------------------
# TITLE   : MC lint runner (scripts/lint.sh)
# PURPOSE : Run ShellCheck (warning severity) over the framework's shell sources
#           and detect non-ASCII bytes in shell and markdown files. Exits
#           nonzero on any finding so it can gate commits.
# USAGE   : bash scripts/lint.sh
# DEPENDS : shellcheck on PATH; grep -P (PCRE); find
# ------------------------------------------------------------------------------
set -o pipefail

# Resolve the repo root from this script's own location so lint works from any
# working directory.
script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo_root="$(cd "$script_dir/.." && pwd)"
cd "$repo_root" || exit 1

exit_status=0

# --- ShellCheck pass ----------------------------------------------------------
# Severity is applied here (-S warning) because .shellcheckrc cannot express it.
if ! command -v shellcheck >/dev/null 2>&1; then
    printf '[lint] ERROR: shellcheck not found on PATH; install it and retry.\n' >&2
    exit 1
fi

shellcheck_targets=()
for candidate in bash/*.sh dotfiles/bashrc.sh scripts/*.sh lib/*.sh; do
    # Globs such as lib/*.sh may not match yet during the refactor; skip
    # anything that is not an actual file.
    [[ -f "$candidate" ]] || continue
    shellcheck_targets+=("$candidate")
done

printf '[lint] shellcheck (-S warning): %d file(s)\n' "${#shellcheck_targets[@]}"
for target in "${shellcheck_targets[@]}"; do
    if shellcheck -S warning "$target"; then
        printf '  OK   %s\n' "$target"
    else
        printf '  FAIL %s\n' "$target"
        exit_status=1
    fi
done

# --- Non-ASCII detector -------------------------------------------------------
# The framework contract is ASCII-only sources (no em dashes, smart quotes, or
# other unicode). Scan *.sh and *.md under the in-scope roots.
#
# zotero/ and nvim's fix_mojibake.lua are excluded by design: the former is out
# of scope for this refactor, the latter's non-ASCII is intentional test data.
# Neither can appear in the current roots (zotero is not a root; the lua file
# matches neither *.sh nor *.md), but the prune and path filter keep the intent
# explicit and correct if the roots are ever widened.
scan_roots=()
for root in bash scripts dotfiles lib docs; do
    [[ -d "$root" ]] && scan_roots+=("$root")
done

printf '[lint] non-ASCII scan (*.sh, *.md)\n'
while IFS= read -r scanned_file; do
    if LC_ALL=C grep -nP '[^\x00-\x7F]' "$scanned_file" >/dev/null 2>&1; then
        printf '  NON-ASCII %s\n' "$scanned_file"
        LC_ALL=C grep -nP '[^\x00-\x7F]' "$scanned_file"
        exit_status=1
    fi
done < <(find "${scan_roots[@]}" \
             -type d -name zotero -prune -o \
             -type f \( -name '*.sh' -o -name '*.md' \) \
             ! -path '*/nvim/lua/scripts/fix_mojibake.lua' -print 2>/dev/null | sort)

# --- Summary ------------------------------------------------------------------
if [[ "$exit_status" -ne 0 ]]; then
    printf '[lint] FAILED (see shellcheck findings and/or non-ASCII hits above)\n' >&2
else
    printf '[lint] OK (no findings)\n'
fi
exit "$exit_status"
