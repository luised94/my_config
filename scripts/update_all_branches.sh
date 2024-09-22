#!/bin/bash

# Fetch all changes from the remote repository
git fetch --all

# Store current branch to return at the end of script
current_branch=$(git rev-parse --abbrev-ref HEAD)

# Get all local branch names except main
branches=$(git for-each-ref --format='%(refname:short)' refs/heads/ | grep -v '^main$')

# Function to rebase a branch
rebase_branch() {
    local branch=$1
    echo "Rebasing branch: $branch"
    git checkout "$branch"
    git rebase main
    if [ $? -eq 0 ]; then 
        git push --force-with-lease origin "$branch"
    else 
        echo "Rebase conflict in $branch. Aborting rebase."
        git rebase --abort
    fi
}

for branch in $branches; do
    rebase_branch "$branch"
done

# Return to origin branch
git checkout "$current_branch"

echo "All branches updated and rebased on main"
