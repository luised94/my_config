# job_hunt: config relocation into kbd + 6-bucket update

Date: 2026-06-23
Module: `15_job_hunt.sh`
Related: LEARN-A Thread 1 (triage workflow), master-overview learn-a1 update

This document records a reorganization of the job-hunt tooling and the
commit-by-commit plan used to apply it. It is self-contained: someone
reading only this file should understand what changed, why, and how to
finish the migration on disk.

## Summary

Two changes landed together:

1. Split the single Dropbox root into two roots. Version-controlled
   config and knowledge (alerts, bookmarks, prompts, portal-ready-info)
   now lives in the kbd repo. Bulky or working data (postings, tracker)
   stays in Dropbox.
2. Expanded the skill-profile bucket system from 4 to 6 buckets, per the
   LEARN-A update, so `joblog` and the posting stub accept buckets 5 and 6.

No files are moved by the script. A new dry-run helper, `jobmigrate`,
prints the exact `mv` commands for the user to review and run by hand.

## Why split the roots

The old design derived every path from one `JOB_DIR` in Dropbox. That
mixed two kinds of content with different needs:

- Config / knowledge (alerts/, bookmarks/, prompts/,
  portal-ready-info.txt): small, diffable text. Worth committing to git
  so it is versioned, reviewable, and portable across machines.
- Data / artifacts (postings/, tracker.tsv, jpegs, etc.): large, changes
  constantly, or simply not something to keep in a git history.

Putting config in `~/personal_repos/kbd/docs/job_hunt/` matches the
convention of grouping docs for a task under
`~/personal_repos/kbd/docs/<task>/`. Dropbox keeps the rest.

## New path layout

CONFIG root (kbd, version-controlled):
`~/personal_repos/kbd/docs/job_hunt/`
- `prompts/*.txt`
- `bookmarks/*.txt`
- `alerts/*.txt`
- `portal-ready-info.txt`

DATA root (Dropbox, not committed):
`/mnt/c/Users/$MC_WINDOWS_USER/MIT Dropbox/Luis Martinez/Personal/job_applications/`
- `postings/YYYY-MM-DD_company_role/`
- `tracker.tsv`
- everything else already there (jpegs, README.md, jobportal.txt,
  recruitment_agencies/, reference-emails, skills-per-job.txt, etc.)

In the module these are now two variables instead of one:

```
JOB_CONFIG_DIR="${HOME}/personal_repos/kbd/docs/job_hunt"
JOB_DATA_DIR="/mnt/c/Users/${MC_WINDOWS_USER}/MIT Dropbox/Luis Martinez/Personal/job_applications"
```

Config paths (prompts, bookmarks, alerts, portal) hang off
`JOB_CONFIG_DIR`. Data paths (postings, tracker) hang off `JOB_DATA_DIR`.
To relocate either root later, change only that one line.

## Decisions locked in

- Config root: `~/personal_repos/kbd/docs/job_hunt/`.
- tracker.tsv: stays in Dropbox (data root), not committed.
- `jobinit` creates the kbd structure but never moves existing files.
- `jobmigrate` is a dry run: it only prints `mv` commands.
- Buckets expanded 4 -> 6.

## Commit-by-commit implementation plan

Apply in this order. Each commit is self-contained and leaves the script
syntactically valid (`bash -n` passes).

### Commit 1 -- split JOB_DIR into JOB_CONFIG_DIR + JOB_DATA_DIR

Message: `job_hunt: split config (kbd) and data (Dropbox) roots`

- Replace the single-root PATHS block with two roots and re-point the six
  derived path variables. `JOB_PROMPTS`, `JOB_BOOKMARKS`, `JOB_ALERTS`,
  `JOB_PORTAL` -> config; `JOB_POSTINGS`, `JOB_TRACKER` -> data.
- Update ROOT DIRECTORY VALIDATION to check both roots and warn
  separately (kbd may be uncloned; Dropbox may be unsynced).
- Update `jobinit` to create both roots and place subdirs under the
  correct root. Split the closing summary into a CONFIG tree and a DATA
  tree.
- Replace `alias jobcd` (pointed at the old single root) with `jobcd`
  (config root) and a new `jobcddata` (data root).
- Update `jobdiag` Directories section to report both roots.
- Result: no `JOB_DIR` references remain.

### Commit 2 -- expand bucket system 4 -> 6

Message: `job_hunt: support buckets 5 and 6 (LEARN-A non-research + strategic)`

- `joblog`: change validation regex `^[1-4]$` to `^[1-6]$` and expand the
  error text to describe buckets 5 (non-research PhD) and 6 (strategic /
  non-bench, dormant).
- `joblog` usage/help text and header comment: `1-4` -> `1-6`.
- `jobsave` posting stub: `Bucket: [1-4 ...]` -> `[1-6 ...]`.
- `jobhelp`: one-line `joblog` description and the BUCKET REFERENCE block
  now list all six buckets.
- `linkedin-alerts.txt` starter heredoc: replace the stale
  "4 total for a four-bucket system" note with the current alert-to-bucket
  mapping (Alerts 1-4 -> buckets 1-4, Alert 5 -> bucket 5).

### Commit 3 -- add jobmigrate dry-run helper

Message: `job_hunt: add jobmigrate (dry-run relocation plan)`

- New `jobmigrate` function inserted before the HELP section. It prints,
  but never executes: a `mkdir -p` for the kbd root, `mv` lines for any of
  alerts/bookmarks/prompts that exist in the old Dropbox root,
  a `mv` line for portal-ready-info.txt, an explicit "stays in Dropbox"
  list (postings, tracker, jpegs, etc.), a kbd `git add`/`git commit`
  suggestion, and a `jobdiag` verification step. Missing sources print a
  `# (skip: ...)` comment instead of a command.
- Add `jobmigrate`, `jobcd`, `jobcddata` to the jobhelp SETUP section.
- Rewrite the jobhelp DIRECTORY LAYOUT block to show both roots.

### Commit 4 -- update file header

Message: `job_hunt: document two-root layout in header`

- Update the SETUP steps to mention cloning kbd and that config lives in
  the kbd prompts/ directory.
- Add a LAYOUT note describing the two roots and pointing to `jobmigrate`.

## How to finish the migration on disk

The script changes only describe where files should live; the existing
files still need to be moved once. Run the helper to get the exact
commands, review them, then run them by hand:

```
jobmigrate            # prints the plan, moves nothing
jobmigrate | less     # page through it
```

The plan, for the current Dropbox contents, expands to roughly:

```
mkdir -p "$HOME/personal_repos/kbd/docs/job_hunt"

mv ".../job_applications/alerts"    "$HOME/personal_repos/kbd/docs/job_hunt/alerts"
mv ".../job_applications/bookmarks" "$HOME/personal_repos/kbd/docs/job_hunt/bookmarks"
mv ".../job_applications/prompts"   "$HOME/personal_repos/kbd/docs/job_hunt/prompts"
mv ".../job_applications/portal-ready-info.txt" \
   "$HOME/personal_repos/kbd/docs/job_hunt/portal-ready-info.txt"

# postings/ and tracker.tsv stay in Dropbox -- not moved.

cd "$HOME/personal_repos/kbd/docs/job_hunt" && git add -A && \
  git commit -m 'job_hunt: relocate config (alerts/bookmarks/prompts/portal) into kbd'

jobdiag    # all config paths should read OK
```

If the kbd destination is a git work tree and you want to preserve file
history through the move, substitute `git mv` for `mv` (run from inside
the repo).

After moving, run `jobdiag` to confirm every config and data path reports
OK.

## Verification performed

- `bash -n 15_job_hunt.sh` passes (syntax valid).
- No `JOB_DIR` references remain; 36 references to the two new root
  variables.
- `jobmigrate` against an empty old root prints skip comments and moves
  nothing; against a populated fixture it emits the four expected `mv`
  lines and the mkdir/commit/verify scaffolding.
- `joblog` rejects bucket 7 and accepts buckets 5 and 6.

## Items intentionally not changed

- The actual content of alerts files (LinkedIn Alert 5, Indeed Search 3)
  is edited via `jobalertedit` against the live files, not via the script.
  The starter heredocs only run on a fresh `jobinit`.
- The Perplexity cadence change (monthly deep dives -> event-driven) is a
  process note recorded in the alert files, not a script behavior.
- Postings, jpegs, and other Dropbox artifacts are left where they are.
