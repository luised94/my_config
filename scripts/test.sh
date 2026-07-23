#!/usr/bin/env bash
# ------------------------------------------------------------------------------
# TITLE   : MC test runner (scripts/test.sh)
# PURPOSE : Run every lib/*.test.sh and every bash/test/*.sh, print one
#           PASS/FAIL line per file, continue past failures, and exit nonzero
#           if any file failed so it can gate commits.
# USAGE   : bash scripts/test.sh
# DEPENDS : bash; the test files themselves
# ------------------------------------------------------------------------------
set -o pipefail

# Resolve the repo root from this script's own location so it runs from any
# working directory (mirrors scripts/lint.sh).
script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo_root="$(cd "$script_dir/.." && pwd)"
cd "$repo_root" || exit 1

exit_status=0
ran_count=0

# Two fixed globs, no discovery cleverness. A glob such as lib/*.test.sh may not
# match anything; the empty-glob case is handled the same way lint.sh does, by
# skipping any candidate that is not an actual file. Per-file output is silenced
# so the summary is exactly one PASS/FAIL line per file; re-run a failing file
# directly (bash <file>) to see why it failed.
for test_file in lib/*.test.sh bash/test/*.sh; do
    [[ -f "$test_file" ]] || continue
    ran_count=$((ran_count + 1))
    if bash "$test_file" >/dev/null 2>&1; then
        printf 'PASS %s\n' "$test_file"
    else
        printf 'FAIL %s\n' "$test_file"
        exit_status=1
    fi
done

printf '[test] %d file(s) run\n' "$ran_count"
if [[ "$exit_status" -ne 0 ]]; then
    printf '[test] FAILED (see FAIL lines above; re-run a file directly to debug)\n' >&2
else
    printf '[test] OK\n'
fi
exit "$exit_status"
