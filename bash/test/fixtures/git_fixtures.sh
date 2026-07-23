# shellcheck shell=bash
# ------------------------------------------------------------------------------
# TITLE   : Git fixture helpers for bash/test
# PURPOSE : Build throwaway git repositories (bare remotes, working clones,
#           dirty trees, stashes, extra commits) for the git_utils tests. Every
#           helper takes explicit path arguments and touches only those paths;
#           none reads or writes a global location. Callers are expected to run
#           inside a sandbox with HOME pointed at that sandbox and a
#           noninteractive git environment (see the test files that source this).
# USAGE   : source this file, then call fixture_* with absolute paths.
# NOTES   : - The default branch is forced to "main" independent of the host
#             git's init.defaultBranch, because the functions under test look
#             for "main" (then "master") and rebase onto "origin/main".
#           - Identity is set locally per repository; global git config is never
#             read or written (callers also isolate it via HOME/GIT_CONFIG_*).
#           - No eval; every expansion is quoted.
# ------------------------------------------------------------------------------

# fixture_set_identity <repo_path>
# Set a local (repo-scoped) commit identity so commits succeed without any
# global git configuration.
fixture_set_identity() {
    local repo_path="${1:?repo path required}"
    git -C "$repo_path" config user.name "Fixture User"
    git -C "$repo_path" config user.email "fixture@example.invalid"
    git -C "$repo_path" config commit.gpgsign false
}

# fixture_make_bare_remote <bare_path>
# Create an empty bare repository whose HEAD points at "main", so a clone of it
# checks out "main" by default.
fixture_make_bare_remote() {
    local bare_path="${1:?bare path required}"
    git init --quiet --bare -b main "$bare_path"
}

# fixture_make_repo_with_remote <bare_path> <work_path>
# Create <work_path> (a working repo with one initial commit on main) and
# <bare_path> (a bare remote), wire the remote up as origin, and push so both
# share history and the working repo tracks origin/main. Building the working
# repo first and pushing (rather than cloning an empty bare) avoids git's
# "cloned an empty repository" warning. Prints the initial commit SHA on stdout.
fixture_make_repo_with_remote() {
    local bare_path="${1:?bare path required}"
    local work_path="${2:?work path required}"

    git init --quiet -b main "$work_path"
    fixture_set_identity "$work_path"
    printf 'initial\n' > "$work_path/README"
    git -C "$work_path" add README
    git -C "$work_path" commit --quiet -m "initial commit"

    fixture_make_bare_remote "$bare_path"
    git -C "$work_path" remote add origin "$bare_path"
    git -C "$work_path" push --quiet -u origin main
    git -C "$work_path" rev-parse HEAD
}

# fixture_make_commit <repo_path> <message> [file] [content]
# Create or overwrite a tracked file and commit it. Defaults keep successive
# calls from colliding by deriving the file name from the current commit count.
# Prints the new HEAD SHA on stdout.
fixture_make_commit() {
    local repo_path="${1:?repo path required}"
    local message="${2:?message required}"
    local file="${3:-}"
    local content="${4:-content}"

    if [[ -z "$file" ]]; then
        local n
        n=$(git -C "$repo_path" rev-list --count HEAD 2>/dev/null || printf '0')
        file="file_${n}.txt"
    fi

    printf '%s\n' "$content" > "$repo_path/$file"
    git -C "$repo_path" add "$file"
    git -C "$repo_path" commit --quiet -m "$message"
    git -C "$repo_path" rev-parse HEAD
}

# fixture_make_dirty <repo_path> [file] [content]
# Introduce an uncommitted change to a TRACKED file (defaults to README, which
# fixture_make_repo_with_remote creates). This is what pull_all_repos and
# push_all_repos detect via `git diff-index --quiet HEAD`; an untracked-only
# change would NOT be detected, which is why this modifies a tracked file.
fixture_make_dirty() {
    local repo_path="${1:?repo path required}"
    local file="${2:-README}"
    local content="${3:-uncommitted change}"
    printf '%s\n' "$content" >> "$repo_path/$file"
}

# fixture_make_stash <repo_path>
# Leave exactly one stash entry in <repo_path> and a clean working tree, by
# dirtying a tracked file and stashing it. Prints nothing.
fixture_make_stash() {
    local repo_path="${1:?repo path required}"
    fixture_make_dirty "$repo_path" "README" "to be stashed"
    git -C "$repo_path" stash push --quiet -u -m "fixture stash"
}
