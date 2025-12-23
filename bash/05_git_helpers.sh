#!/bin/bash
# ------------------------------------------------------------------------------
# TITLE      : MC Git helpers (05_git_helpers.sh)
# PURPOSE    : Reusable functions to check git state.
# DEPENDENCIES: Git
# Usage: Sourced by bashrc or source manually.
# DATE: 2025-12-23
# ------------------------------------------------------------------------------

# Check that user is in git repo.
_is_git_repo() {
    if git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
        return 0
    else
        return 1
    fi
}
