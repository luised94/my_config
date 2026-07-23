#!/usr/bin/env bash
# ------------------------------------------------------------------------------
# TITLE   : Tests for the worktree functions in bash/11_git_utils.sh
# PURPOSE : Characterize current behavior of new_worktree and
#           rebase_worktrees_on_main against real (local) git fixtures. Both
#           functions operate on the current working directory, so each call is
#           made inside a subshell that cd's into the fixture repo. Assertions
#           are on observable state (directories, branch tips, worktree counts,
#           return codes). Exits nonzero on any failure.
# USAGE   : bash bash/test/git_worktrees.sh
# NOTES   : Same sandbox/isolation model as git_repo_loops.sh (HOME redirected
#           into a mktemp sandbox, git forced noninteractive). Neither function
#           invokes tmux, so the handoff's tmux-stub contingency does not apply.
# ------------------------------------------------------------------------------
set -u

test_directory="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo_root="$(cd "$test_directory/../.." && pwd)"

# Runtime-resolved paths; not statically followable (see git_repo_loops.sh).
# shellcheck source=/dev/null
source "$repo_root/lib/message.sh"
# shellcheck source=/dev/null
source "$repo_root/bash/11_git_utils.sh"
# shellcheck source=/dev/null
source "$test_directory/fixtures/git_fixtures.sh"

# --- Sandbox and isolation ----------------------------------------------------
sandbox="$(mktemp -d)"
trap 'rm -rf "$sandbox"' EXIT

export HOME="$sandbox"
export GIT_CONFIG_NOSYSTEM=1
export GIT_TERMINAL_PROMPT=0
export GIT_EDITOR=true
export GIT_SEQUENCE_EDITOR=true
export MC_REPOS_ROOT="$sandbox/never_used_default"

# --- Assertion helpers --------------------------------------------------------
tests_run=0
tests_failed=0

check() {   # check <description> <expected> <actual>
    tests_run=$((tests_run + 1))
    if [[ "$2" == "$3" ]]; then
        printf '  ok   %s\n' "$1"
    else
        printf '  FAIL %s (expected [%s], got [%s])\n' "$1" "$2" "$3"
        tests_failed=$((tests_failed + 1))
    fi
}

worktree_count() { git -C "$1" worktree list --porcelain | grep -c '^worktree '; }
sha_of() { git -C "$1" rev-parse "${2:-HEAD}"; }

# ==============================================================================
# 1. new_worktree - happy path
# ==============================================================================
# NOTE: new_worktree requires the branch to ALREADY exist; it does not create
# one (it errors on a missing refs/heads/<branch>). The handoff's "new branch"
# wording is adapted here to "create the branch first, then the worktree".
printf '\n--- new_worktree (happy path) ---\n'
src_repo="$sandbox/w1/src"
trees="$sandbox/w1/trees"
fixture_make_repo_with_remote "$sandbox/rem/w1.git" "$src_repo" >/dev/null
git -C "$src_repo" branch "feature/login"

( cd "$src_repo" && MC_VERBOSITY=0 new_worktree "feature/login" "$trees" ) >/dev/null 2>&1
new_rc=$?
# Destination path is "${worktree_root}/${repo_name}--${branch-with-/-as-}".
expected_dest="$trees/src--feature-login"

check "new_worktree returns 0"                 "0"    "$new_rc"
check "worktree directory created at expected path" "yes" "$([[ -d "$expected_dest" ]] && printf yes || printf no)"
check "worktree has the requested branch checked out" "feature/login" "$(git -C "$expected_dest" branch --show-current)"
check "source repo left clean"                 ""     "$(git -C "$src_repo" status --porcelain)"
check "one linked worktree now exists (2 total)" "2"   "$(worktree_count "$src_repo")"

# ==============================================================================
# 2. new_worktree - failure paths
# ==============================================================================
printf '\n--- new_worktree (failure paths) ---\n'
# (a) Re-requesting the same branch: the destination already exists -> refuses.
( cd "$src_repo" && MC_VERBOSITY=0 new_worktree "feature/login" "$trees" ) >/dev/null 2>&1
dup_rc=$?
check "new_worktree refuses when destination exists" "1" "$dup_rc"

# (b) A branch that does not exist -> refuses (does not create it).
( cd "$src_repo" && MC_VERBOSITY=0 new_worktree "no/such/branch" "$trees" ) >/dev/null 2>&1
missing_rc=$?
check "new_worktree refuses a nonexistent branch"    "1" "$missing_rc"
check "no worktree was created for the missing branch" "no" \
    "$([[ -e "$trees/src--no-such-branch" ]] && printf yes || printf no)"
check "worktree count unchanged after failures (2)"  "2" "$(worktree_count "$src_repo")"

# ==============================================================================
# 3. rebase_worktrees_on_main
# ==============================================================================
# NOTE: rebase_worktrees_on_main ignores its documented [worktree-root]
# argument; it discovers worktrees via `git worktree list` relative to the
# current directory and rebases each onto origin/main, then pushes with
# --force-with-lease. It is invoked here from inside the main worktree.
printf '\n--- rebase_worktrees_on_main ---\n'
rb_repo="$sandbox/w2/src"
rb_trees="$sandbox/w2/trees"
fixture_make_repo_with_remote "$sandbox/rem/w2.git" "$rb_repo" >/dev/null

# A linked worktree on 'feature', carrying its own commit F on top of main's A.
git -C "$rb_repo" branch feature
feature_wt="$rb_trees/feature_wt"
git -C "$rb_repo" worktree add --quiet "$feature_wt" feature
fixture_make_commit "$feature_wt" "feature F" "f.txt" "eff" >/dev/null

# origin/main advances to B (a commit the feature branch does not yet contain).
main_b="$(fixture_make_commit "$rb_repo" "main B" "mb.txt" "bee")"
git -C "$rb_repo" push --quiet origin main

( cd "$rb_repo" && MC_VERBOSITY=0 rebase_worktrees_on_main ) >/dev/null 2>&1
rebase_rc=$?

check "rebase_worktrees_on_main returns 0" "0" "$rebase_rc"
# After rebasing feature onto origin/main, B must be an ancestor of feature.
git -C "$feature_wt" merge-base --is-ancestor "$main_b" HEAD 2>/dev/null
contains_main="$?"
check "feature worktree now contains the new main commit" "0" "$contains_main"
# The feature branch still carries its own work on top (F replayed), so its tip
# is not simply B.
check "feature tip is not just origin/main (own commit replayed)" "no" \
    "$([[ "$(sha_of "$feature_wt")" == "$main_b" ]] && printf yes || printf no)"
# The rebased branch was pushed back to origin.
check "origin received the rebased feature branch" "$(sha_of "$feature_wt")" \
    "$(git -C "$sandbox/rem/w2.git" rev-parse feature)"

# --- Summary ------------------------------------------------------------------
printf '\n[git_worktrees] %d run, %d failed\n' "$tests_run" "$tests_failed"
[[ "$tests_failed" -eq 0 ]]
