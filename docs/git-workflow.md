# Git Workflow

Branch-and-worktree workflow for managing experiments and projects.

## Overview

Branches represent experiments or projects. Worktrees represent active work - a branch with a worktree in `~/personal_repos` is active, a branch without one is shelved. Merged into `main` means done. Tags are point-in-time snapshots.

There is no `dev` or `develop` branch. `main` is the single integration point.

## Conventions

### Branch prefixes

| Prefix | Intent | Example |
|--------|--------|---------|
| `exp/` | Exploratory experiment. May be abandoned. | `exp/logit-regression` |
| `proj/` | Directed project work. More likely to complete. | `proj/backup-migration` |

Both follow the same lifecycle. The distinction communicates intent, not process.

### Protected branch names

`main`, `master`, `develop` are never pruned by tooling.

### First-commit convention

The first commit on any `exp/` or `proj/` branch should have a subject line that answers: *"What is this about?"*

This commit may be otherwise empty (e.g., adding a notes file) or contain initial scaffolding. It serves as the experiment's description, retrievable later via the "first divergence commit" recipe.

Example:
git checkout -b exp/logit-regression
git commit --allow-empty -m "explore logistic regression for binary classification task"
### Snapshot tags

Format: `snapshot/<description>/<YYYY-MM-DD>`

- Created with `git tag -a` (annotated - includes a message)
- Used for known-good states before risky changes
- Replace the former practice of backup branches
- Greppable: `git tag -l 'snapshot/*'`

## Lifecycle
Create  Work  Maintain  Shelve  Resume  Finish
? Abandon
| Stage | Action | Tool |
|-------|--------|------|
| **Create** | Branch from `main` with `exp/` or `proj/` prefix, create worktree | `new_worktree` |
| **Work** | Commit on the branch in its worktree. First commit describes purpose. | - |
| **Maintain** | Rebase active worktrees onto current `main` | `rebase_worktrees_on_main` |
| **Shelve** | Remove worktree, keep branch for later | `remove_worktree` |
| **Resume** | Re-create worktree for existing branch | `new_worktree` |
| **Finish (merge)** | Merge into `main`; branch cleaned up later | `prune_merged_branches` |
| **Finish (abandon)** | Remove worktree, optionally delete branch | `remove_worktree`, manual |
| **Snapshot** | Tag a known-good state before risky changes | See recipe below |

## Functions Reference

All functions live in `bash/11_git_utils.sh`. Pass `-h` for usage.

| Function | Purpose |
|----------|---------|
| `new_worktree <branch>` | Create worktree for an existing branch in `~/personal_repos` |
| `remove_worktree <branch>` | Remove worktree (refuses if dirty) |
| `rebase_worktrees_on_main` | Rebase + push all worktrees onto `origin/main` |
| `prune_merged_branches [--delete]` | Find/remove branches fully merged into main (dry-run by default) |
| `status_all_repos [--fetch]` | Compact status table for all repos |
| `stash_report` | List stash entries across all repos |
| `pull_all_repos` | Pull all repos (auto-stashes dirty trees) |
| `push_all_repos` | Push repos with unpushed commits (skips diverged) |

## Recipes

### List experiment and project branches by activity

When you want to see all exp/proj branches, oldest first.

```bash
git branch --list 'exp/*' 'proj/*' --sort=committerdate --format='%(committerdate:short) %(refname:short)'
```

### Show all worktrees
When you want to see what's currently active.
```bash
git worktree list
```

### Check for broken or prunable worktrees
When a worktree directory was deleted without git worktree remove.
```bash
git worktree prune --dry-run
```
Remove --dry-run to execute.

### Check for uncommitted work across worktrees
When you want to know if any active worktree has unsaved changes.

```bash
git worktree list --porcelain | grep '^worktree ' | sed 's/^worktree //' | while read -r wt; do
    if [ -n "$$(git -C "$$wt" status --porcelain 2>/dev/null)" ]; then
        echo "dirty: $wt"
    fi
done
```

### Show last commit on a branch
When returning to a branch and you want to remember where you left off.
```bash
git log -1 --format='%h %s (%cr)' <branch-name>
```

### Show first divergence commit (experiment description)

Relies on first-commit convention. Retrieves the purpose of an experiment branch.
```bash
git log main..<branch-name> --reverse --format='%h %s (%cr)' | head -1
```

### Show branches merged into main

What's ready to clean up.
```bash
git branch --merged main
```

### Convert a branch to a snapshot tag

Archive a known-good state. This is the backup migration recipe.
```bash
# 1. Create annotated tag
git tag -a "snapshot/<description>/<YYYY-MM-DD>" <branch-name> -m "Snapshot: <why>"

# 2. Verify tag points to correct commit
git log -1 --format="%H" <branch-name>
git log -1 --format="%H" "snapshot/<description>/<YYYY-MM-DD>"
# Both should print the same SHA

# 3. Delete local branch (use -D if not merged into main)
git branch -d <branch-name>

# 4. Delete remote branch (if pushed)
git push origin --delete <branch-name>

# 5. Push tag to remote
git push origin "snapshot/<description>/<YYYY-MM-DD>"
```

### List snapshot tags
See all archived snapshots, newest first.
git tag -l 'snapshot/*' --sort=-creatordate --format='%(creatordate:short) %(refname:short)'

### Restore from a snapshot tag
When you need to resume work from an archived snapshot.

```bash
# Create a branch from the tag
git checkout -b exp/<new-name> snapshot/<description>/<date>

# Optionally create a worktree for it
new_worktree exp/<new-name>
```

---
