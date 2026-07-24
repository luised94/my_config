#!/usr/bin/env bash
# ------------------------------------------------------------------------------
# TITLE   : Tests for the repo-loop functions in bash/11_git_utils.sh
# PURPOSE : Characterize current behavior of stash_report, pull_all_repos,
#           push_all_repos, and prune_merged_branches against real (local) git
#           fixtures, plus the usb-repos skip regression. Assertions are on
#           observable state (SHAs, branch lists, return codes); msg_* text is
#           asserted only where a message is the behavior under test. Exits
#           nonzero on any failure.
# USAGE   : bash bash/test/git_repo_loops.sh
# NOTES   : Everything happens inside a mktemp sandbox with HOME redirected into
#           it and git forced noninteractive, so no real HOME, global git
#           config, or MC_REPOS_ROOT is ever read or written. The functions are
#           always given the sandbox root as an explicit argument (the narrow
#           interface); MC_REPOS_ROOT is set only as a sandbox-confined dead-end
#           safety net in case a code path ever falls through to the default.
# ------------------------------------------------------------------------------
set -u

test_directory="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo_root="$(cd "$test_directory/../.." && pwd)"

# Paths are resolved at runtime from repo_root/test_directory; tell shellcheck
# not to try to follow them statically (the sourced files are analyzed on their
# own via scripts/test.sh and direct shellcheck runs).
# shellcheck source=/dev/null
source "$repo_root/lib/message.sh"
# shellcheck source=/dev/null
source "$repo_root/bash/11_git_utils.sh"
# shellcheck source=/dev/null
source "$test_directory/fixtures/git_fixtures.sh"

# --- Sandbox and isolation ----------------------------------------------------
sandbox="$(mktemp -d)"
trap 'rm -rf "$sandbox"' EXIT

export HOME="$sandbox"                       # no real ~/.gitconfig, no real HOME
export GIT_CONFIG_NOSYSTEM=1                  # ignore /etc/gitconfig
export GIT_TERMINAL_PROMPT=0                  # never block on a credential prompt
export GIT_EDITOR=true                        # never open an editor (merge/commit)
export GIT_SEQUENCE_EDITOR=true               # never open an editor (rebase -i)
export MC_REPOS_ROOT="$sandbox/never_used_default"   # sandbox-confined safety net

# --- Assertion helpers (same shape as lib/message.test.sh) --------------------
tests_run=0
tests_failed=0
tests_skipped=0

check() {   # check <description> <expected> <actual>
    tests_run=$((tests_run + 1))
    if [[ "$2" == "$3" ]]; then
        printf '  ok   %s\n' "$1"
    else
        printf '  FAIL %s (expected [%s], got [%s])\n' "$1" "$2" "$3"
        tests_failed=$((tests_failed + 1))
    fi
}

skip() {    # skip <description> <reason>
    tests_skipped=$((tests_skipped + 1))
    printf '  SKIP %s (%s)\n' "$1" "$2"
}

contains() { grep -qF -- "$2" <<< "$1" && printf 'yes' || printf 'no'; }

# rc_of <verbosity> <command...> : run quietly, return the command's exit code
rc_of() { local verbosity="$1"; shift; MC_VERBOSITY="$verbosity" "$@" >/dev/null 2>&1; }

sha_of() { git -C "$1" rev-parse "${2:-HEAD}"; }

# ==============================================================================
# 1. stash_report
# ==============================================================================
printf '\n--- stash_report ---\n'
stash_root="$sandbox/stash_root"
mkdir -p "$stash_root"
fixture_make_repo_with_remote "$sandbox/rem/stash_a.git" "$stash_root/repo_a" >/dev/null
fixture_make_repo_with_remote "$sandbox/rem/stash_b.git" "$stash_root/repo_b" >/dev/null
fixture_make_repo_with_remote "$sandbox/rem/stash_clean.git" "$stash_root/repo_clean" >/dev/null
fixture_make_stash "$stash_root/repo_a"        # call site 1
fixture_make_stash "$stash_root/repo_b"        # call site 2
mkdir -p "$stash_root/plaindir"                # non-git subdirectory (tolerated)

rc_of 0 stash_report "$stash_root"; stash_rc=$?
check "stash_report returns 1 when stashes exist" "1" "$stash_rc"

stash_out="$(MC_VERBOSITY=3 stash_report "$stash_root" 2>&1)"
check "stashed repo_a is reported"        "yes" "$(contains "$stash_out" "repo_a")"
check "stashed repo_b is reported"        "yes" "$(contains "$stash_out" "repo_b")"
check "clean repo is not reported"        "no"  "$(contains "$stash_out" "repo_clean")"
check "non-git plaindir is not reported"  "no"  "$(contains "$stash_out" "plaindir")"

clean_root="$sandbox/clean_root"
mkdir -p "$clean_root"
fixture_make_repo_with_remote "$sandbox/rem/only_clean.git" "$clean_root/repo_only" >/dev/null
mkdir -p "$clean_root/plaindir"
rc_of 0 stash_report "$clean_root"; clean_rc=$?
check "stash_report returns 0 when no stashes exist" "0" "$clean_rc"

# ==============================================================================
# 2. pull_all_repos
# ==============================================================================
printf '\n--- pull_all_repos ---\n'
pull_root="$sandbox/pull_root"
mkdir -p "$pull_root"

# repo_behind: local reset one commit behind its remote (a clean fast-forward)
behind_a="$(fixture_make_repo_with_remote "$sandbox/rem/pull_behind.git" "$pull_root/repo_behind")"
behind_b="$(fixture_make_commit "$pull_root/repo_behind" "behind B" "b.txt" "bee")"
git -C "$pull_root/repo_behind" push --quiet origin main
git -C "$pull_root/repo_behind" reset --hard "$behind_a" >/dev/null 2>&1

# repo_uptodate: untouched, already in sync
fixture_make_repo_with_remote "$sandbox/rem/pull_synced.git" "$pull_root/repo_uptodate" >/dev/null
uptodate_before="$(sha_of "$pull_root/repo_uptodate")"

# repo_dirty_behind: behind AND has an uncommitted tracked change on a file the
# incoming commit does not touch (README vs b.txt), so auto-stash + ff + pop
# all succeed without conflict.
dirty_a="$(fixture_make_repo_with_remote "$sandbox/rem/pull_dirty.git" "$pull_root/repo_dirty_behind")"
dirty_b="$(fixture_make_commit "$pull_root/repo_dirty_behind" "dirty B" "b.txt" "bee")"
git -C "$pull_root/repo_dirty_behind" push --quiet origin main
git -C "$pull_root/repo_dirty_behind" reset --hard "$dirty_a" >/dev/null 2>&1
fixture_make_dirty "$pull_root/repo_dirty_behind" "README" "DIRTY-MARKER"

rc_of 0 pull_all_repos "$pull_root"; pull_rc=$?
check "pull_all_repos returns 0 (all fast-forwardable)" "0" "$pull_rc"
check "behind repo advanced to remote tip" "$behind_b" "$(sha_of "$pull_root/repo_behind")"
check "up-to-date repo left unchanged"     "$uptodate_before" "$(sha_of "$pull_root/repo_uptodate")"
# NOTE: current behavior for a dirty repo is auto-stash (tracked change only,
# via `git diff-index --quiet HEAD`), fast-forward, then `stash pop`. An
# untracked-only change would NOT trigger the stash, and a stash that conflicts
# with the pulled commit would leave the pop unresolved (not exercised here).
check "dirty+behind repo advanced to remote tip" "$dirty_b" "$(sha_of "$pull_root/repo_dirty_behind")"
dirty_readme="$(cat "$pull_root/repo_dirty_behind/README")"
check "dirty repo local change was restored after pull" "yes" "$(contains "$dirty_readme" "DIRTY-MARKER")"

# ==============================================================================
# 3. push_all_repos
# ==============================================================================
printf '\n--- push_all_repos ---\n'
push_root="$sandbox/push_root"
mkdir -p "$push_root"

# repo_ahead: one local commit not yet pushed
fixture_make_repo_with_remote "$sandbox/rem/push_ahead.git" "$push_root/repo_ahead" >/dev/null
push_b="$(fixture_make_commit "$push_root/repo_ahead" "ahead B" "b.txt" "bee")"
ahead_bare_before="$(git -C "$sandbox/rem/push_ahead.git" rev-parse main)"

# repo_synced: nothing to push
fixture_make_repo_with_remote "$sandbox/rem/push_synced.git" "$push_root/repo_synced" >/dev/null
synced_bare_before="$(git -C "$sandbox/rem/push_synced.git" rev-parse main)"

rc_of 0 push_all_repos "$push_root"; push_rc=$?
check "push_all_repos returns 0 on success"          "0" "$push_rc"
check "ahead repo was pushed (bare advanced to local tip)" "$push_b" "$(git -C "$sandbox/rem/push_ahead.git" rev-parse main)"
check "ahead repo bare actually changed"             "no"  "$([[ "$ahead_bare_before" == "$push_b" ]] && printf yes || printf no)"
check "synced repo bare left unchanged"              "$synced_bare_before" "$(git -C "$sandbox/rem/push_synced.git" rev-parse main)"
# Regression: the "early exit if nothing to push" block computed its status
# with `(( ${#diverged_repos[@]} == 0 ))` but had no `return`, so control fell
# through to the empty push loop and printed a bogus "Found 0 repo(s)" and
# "Complete: 0/0". C27 adds the missing `return`. The return code was always 0
# in this case, so only the spurious output changed; the assertions below pin
# that (a root where every repo is already synced -> nothing pushable).
nopush_root="$sandbox/nopush_root"
mkdir -p "$nopush_root"
fixture_make_repo_with_remote "$sandbox/rem/nopush_a.git" "$nopush_root/repo_a" >/dev/null
fixture_make_repo_with_remote "$sandbox/rem/nopush_b.git" "$nopush_root/repo_b" >/dev/null

rc_of 0 push_all_repos "$nopush_root"; nopush_rc=$?
check "push_all_repos returns 0 when nothing to push"        "0"   "$nopush_rc"

nopush_out="$(MC_VERBOSITY=3 push_all_repos "$nopush_root" 2>&1)"
check "nothing-to-push says 'Nothing to push'"               "yes" "$(contains "$nopush_out" "Nothing to push")"
check "nothing-to-push omits bogus 'Found 0 repo(s)'"        "no"  "$(contains "$nopush_out" "Found 0 repo(s)")"
check "nothing-to-push omits bogus 'Complete: 0/0'"          "no"  "$(contains "$nopush_out" "Complete: 0/0")"

# ==============================================================================
# 4. usb-repos skip regression (all four loop functions)
# ==============================================================================
printf '\n--- usb-repos skip regression ---\n'
usb_root="$sandbox/usb_root"
mkdir -p "$usb_root"

# Control repo "normal": behind its remote, so a working loop advances it.
normal_a="$(fixture_make_repo_with_remote "$sandbox/rem/usb_normal.git" "$usb_root/normal")"
normal_b="$(fixture_make_commit "$usb_root/normal" "normal B" "nb.txt" "en")"
git -C "$usb_root/normal" push --quiet origin main
git -C "$usb_root/normal" reset --hard "$normal_a" >/dev/null 2>&1

# "usb-repos": rigged so every loop function WOULD change it if the skip broke:
# behind its remote (pull would advance), a merged branch (prune would delete),
# and a stash (stash_report would report).
usb_a="$(fixture_make_repo_with_remote "$sandbox/rem/usb_usb.git" "$usb_root/usb-repos")"
fixture_make_commit "$usb_root/usb-repos" "usb B" "ub.txt" "you" >/dev/null
git -C "$usb_root/usb-repos" push --quiet origin main
git -C "$usb_root/usb-repos" reset --hard "$usb_a" >/dev/null 2>&1
git -C "$usb_root/usb-repos" branch usb_merged "$usb_a"
fixture_make_stash "$usb_root/usb-repos"

rc_of 0 pull_all_repos "$usb_root"
check "control repo IS processed by pull (advanced)" "$normal_b" "$(sha_of "$usb_root/normal")"
check "usb-repos HEAD untouched by pull_all_repos"   "$usb_a"    "$(sha_of "$usb_root/usb-repos")"

rc_of 0 push_all_repos "$usb_root"
check "usb-repos HEAD untouched by push_all_repos"   "$usb_a"    "$(sha_of "$usb_root/usb-repos")"

rc_of 0 prune_merged_branches --delete "$usb_root"
check "usb-repos merged branch untouched by prune" "usb_merged" "$(git -C "$usb_root/usb-repos" branch --list usb_merged --format='%(refname:short)')"

usb_stash_out="$(MC_VERBOSITY=3 stash_report "$usb_root" 2>&1)"
rc_of 0 stash_report "$usb_root"; usb_stash_rc=$?
check "usb-repos stash not reported by stash_report" "no" "$(contains "$usb_stash_out" "usb-repos")"
check "stash_report returns 0 (usb stash skipped)"   "0"  "$usb_stash_rc"
# The skip is a silent `continue` in all four functions; there is no skip-notice
# message to capture, contrary to the handoff wording. Recorded as a finding.
skip "usb-repos skip notice capture" "current code skips usb-repos silently; no notice is emitted"

# ==============================================================================
# 5. prune_merged_branches
# ==============================================================================
printf '\n--- prune_merged_branches ---\n'
prune_root="$sandbox/prune_root"
mkdir -p "$prune_root"
prune_a="$(fixture_make_repo_with_remote "$sandbox/rem/prune.git" "$prune_root/repo")"
prune_repo="$prune_root/repo"

# merged_feature points at the old tip; main then advances past it -> merged.
git -C "$prune_repo" branch merged_feature "$prune_a"
fixture_make_commit "$prune_repo" "main B" "mb.txt" "em" >/dev/null   # main now ahead of A

# unmerged_feature carries a commit that never lands on main -> not merged.
git -C "$prune_repo" branch unmerged_feature
git -C "$prune_repo" checkout --quiet unmerged_feature
fixture_make_commit "$prune_repo" "unmerged C" "uc.txt" "see" >/dev/null
git -C "$prune_repo" checkout --quiet main

# current_merged is merged (at main's tip) and will be the checked-out branch.
git -C "$prune_repo" branch current_merged
git -C "$prune_repo" checkout --quiet current_merged

# Dry-run first: nothing should be deleted.
rc_of 0 prune_merged_branches "$prune_root"; prune_dry_rc=$?
check "prune dry-run returns 0"                    "0" "$prune_dry_rc"
check "dry-run leaves merged branch in place" "merged_feature" "$(git -C "$prune_repo" branch --list merged_feature --format='%(refname:short)')"

# Now delete for real.
rc_of 0 prune_merged_branches --delete "$prune_root"; prune_del_rc=$?
check "prune --delete returns 0"                   "0" "$prune_del_rc"
check "merged branch was deleted"                  ""  "$(git -C "$prune_repo" branch --list merged_feature --format='%(refname:short)')"
check "unmerged branch survives"     "unmerged_feature" "$(git -C "$prune_repo" branch --list unmerged_feature --format='%(refname:short)')"
check "current branch survives even though merged" "current_merged" "$(git -C "$prune_repo" branch --list current_merged --format='%(refname:short)')"
check "main branch survives"                    "main" "$(git -C "$prune_repo" branch --list main --format='%(refname:short)')"

# --- Summary ------------------------------------------------------------------
printf '\n[git_repo_loops] %d run, %d failed, %d skipped\n' "$tests_run" "$tests_failed" "$tests_skipped"
[[ "$tests_failed" -eq 0 ]]
