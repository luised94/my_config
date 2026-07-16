# Zotero Directory Maintenance Plan

Status: ACTIVE
Created: 2026-07-15
Scope: everything under zotero/ in this repository.

This document is the spine of a multi-thread maintenance and feature effort.
Each implementation thread reads this file plus its handoff document under
handoff/. Decisions made in a thread are committed back into the relevant
handoff document so the repository, not any chat transcript, is the record.

## 1. Context

- Library scale: ~60,000 items in My Library. The linked-attachment folder
  contains more files than items. Any script touching the full library or
  the full folder MUST use the batching/yield/progress/checkpoint patterns
  described in CONVENTIONS.md. These are not optional polish; they are what
  keeps Zotero usable and prevents crashes at this scale.
- Environment: Zotero runs on Windows. Attachments are linked files under
  a Dropbox folder on the Windows filesystem. Development happens in WSL
  Ubuntu. Consequence: bash cannot be the primary tool for anything that
  runs against the live library or files. Going forward, scripts are either
  Zotero console JavaScript (run inside Zotero) or PowerShell (run on the
  Windows side). Bash is acceptable only for trivial WSL-side dev utilities.
- WSL/Windows repo gap: this repository is cloned in WSL. Zotero (Windows)
  cannot conveniently read files from the WSL filesystem. Working assumption:
  scripts that Zotero must read from disk are manually copied to a
  Windows-side folder. This is an explicit requirement and a recorded TODO
  (future feature: sync step, Windows-side clone, or \\wsl$ experiment).
  See handoff/03_incoming_automation.md.
- Plugins in use: Better BibTeX, Better Notes, Actions & Tags.
  Tested version ceilings are recorded per script (see CONVENTIONS.md).

## 2. File inventory and verdicts

| File | Verdict |
|---|---|
| backup_zotero.sh | DELETE. Buggy stub (inverted tests, duplicated block, missing $), superseded by powershell/Backup-ZoteroStorage.ps1. |
| bash/backup_to_hard_drive.sh | DELETE. Deprecated. Its ideas (marker-file drive detection) already live in the PS1 script. |
| bash/find_files.sh | MOVE to one-time-operations/ with a completed-checklist header. Optional PS1 port is deferred, low priority. |
| one-time-operations/verify_pdf_file_duplicates_with_hash.sh | DELETE. Empty file. |
| one-time-operations/verify_pdf_file_duplicates_with_file_name.sh | DELETE. Filename-prefix matching is unsafe (15-char truncation causes false positives). If duplicate detection recurs, do it properly by DOI/ISBN/title in console JS, or port the PS1 backup scaffold. Git history preserves this script. |
| powershell/Backup-ZoteroStorage.ps1 | KEEP. Reference-quality. Serves as the scaffold for future PS1 tools (e.g. Move-OrphanFiles.ps1). Encoding is plain ASCII; no conversion needed. |
| console_js/bbt_export.js | KEEP. Flagship script. Open item: incremental-export scaffolding is half built; either finish incremental slicing or freeze as full-export-only with a comment. |
| console_js/bbt_citation_key_refresh.js | KEEP. Fix one stray 0x1A control character in a comment. Open item: sort item IDs before processing so START_INDEX resume is order-stable. |
| console_js/adjust_attachment_paths.js | KEEP. Useful whenever a base path changes. Also informs the orphan pipeline (historical base paths). |
| console_js/convert_readstatus_to_tags.js | SALVAGE. One-time migration, but its tag logic seeds the tag-hygiene report (thread 3). |
| console_js/determine_readstatus_and_tag_combinations.js | SALVAGE. Generalize into a recurring tag-hygiene report (thread 3). |
| plugin_actions_and_tag_js/add-google-tag.js | SPLIT. File is an accidental concatenation of three actions (duplicate const declarations, unreachable code). Split into mark-as-read.js and tag-google-books.js; dedupe the in-progress action against the yml backup. |
| plugin_actions_and_tag_js/actions-zotero.yml | KEEP as backup artifact. Decision: repository .js files are canonical; the yml is an exported backup, refreshed after changes. README states this. |
| better_notes_templates/*.md | KEEP. No changes planned. |
| general_settings.md | FOLD into this plan / README, then delete. It is a task list, not settings. |

## 3. Decisions (settled)

- D1: Console JS and PowerShell only for new tooling (see Context).
- D2: Detection and destruction are separate tools. Anything that reports
  never deletes; anything that deletes reads a reviewed input list, runs
  dry-run by default, and quarantines rather than removes where possible.
- D3: Orphan scope is the linked-file base directory only. Zotero's own
  storage/ directory is out of scope. My Library only. All attachment
  formats (pdf, html, epub, ...) are in scope; only OS/sync noise files
  are ignored (data-driven ignore list).
- D4: Orphan quarantine location: a sibling folder "zotero-orphans/" next
  to the linked base (mirrors the existing pdf_to_delete pattern). Moves
  preserve relative subfolder structure so restore is trivial.
- D5: Automation starts with the item-added event only, via Actions & Tags.
  Rules are a data-driven table of {name, guard, apply}, idempotent, with
  cheap guards first. LOG_ONLY is the default mode.
- D6: js files in this repository are canonical for Actions & Tags actions;
  actions-zotero.yml is a backup export.
- D7: Delivery model: work is batched per thread; each commit is delivered
  as a patch in an ordered series (git format-patch / git am) with an
  application note, reviewable before anything touches the repo.
- D8: Every load-bearing assumption about Zotero internals is verified by a
  spike before design freezes. Spike findings are committed into the
  relevant handoff document as "Verified facts" with the Zotero and plugin
  versions they were tested against.
- D9: All new files are ASCII-only.

## 4. Open questions

- Q1: Tag taxonomy refinement. Current __ workflow tags need review.
  Owner: user. Recorded as DRAFT in CONVENTIONS.md Part B. Blocks the final
  rule set in thread 3; blocks nothing in thread 2.
- Q2: Reporting standard for automatic actions. Proposal pending spike S4:
  Zotero.debug always; append-file in the data directory for run records;
  Zotero.ProgressWindow only for brief user-facing summaries. Confirm in
  thread 3.
- Q3: bbt_export incremental mode: finish or freeze. Decide opportunistically.
- Q4: Fate of duplicate detection: likely a future console JS report by
  DOI/ISBN/normalized title. Not scheduled.
- Q5: WSL-to-Windows script transport: manual copy for now; future feature.
- Q6: Environment/version reporting (folded from general_settings.md,
  now deleted): a small console script that outputs Zotero version,
  installed plugins and their versions, and selected preferences, so
  the tested-version ceilings in script CONFIGs and the dependency
  list in README.md can be updated from real data instead of memory.
  Original notes also wanted Zotero version detection from WSL
  (wslpath); superseded if the console script covers it. Unscheduled;
  natural fit alongside any thread's spike work.

## 5. Spike track

Cheap throwaway console scripts run interactively (user pastes output back).
Spikes live in their threads, not in thread 1.

- S1 (thread 2): attachment introspection. linkMode values present in the
  library; getFilePath() behavior for linked file / stored / linked URL /
  missing file; how html, epub, snapshot attachments present.
- S2 (thread 2): IOUtils directory walk at scale (60k+ files). Streaming vs
  buffering, memory, duration, Dropbox hydration behavior.
- S3 (thread 3): item-added event semantics. Fire timing vs translator
  metadata population; whether saveTx inside a handler re-triggers events;
  item state at fire time; burst behavior on bulk import. Make-or-break for
  the normalizer design.
- S4 (thread 3): logging surfaces. Zotero.debug vs append-file vs
  ProgressWindow ergonomics; pick the standard (see Q2).
- S5 (thread 4): annotation model. Annotation APIs; whether exported PDFs
  embed the Zotero item key; options for writing annotations into PDF files;
  Better Notes interactions.

## 6. Thread map

- Thread 1 (this one): housekeeping and foundations. Documents (this file,
  CONVENTIONS.md, handoff docs), control-character fix, deletions, moves,
  action-script split, README. No spikes, no console pasting.
- Thread 2: orphan attachment pipeline. Sequence: S1, S2, finalize design
  into handoff doc (committed), audit_orphan_attachments.js with
  1000/5000/full validation ramp, Move-OrphanFiles.ps1 dry-run then execute.
  See handoff/02_orphan_pipeline.md.
- Thread 3: incoming-item automation, test-first. Sequence: S3, S4, commit
  findings, then rules-table normalizer (item-added), library-wide backfill
  runner, tag-hygiene report salvage. Requires Q1 resolved. See
  handoff/03_incoming_automation.md.
- Thread 4: annotation export. Deliberately under-specified until S5.
  Independent; can float. See handoff/04_annotation_export.md.

Ordering: thread 1 first. Thread 2 next, optionally overlapping thread 3's
spike phase. Thread 3 implementation after its spikes and Q1. Thread 4 last
or whenever convenient.

## 7. Thread 1 commit plan

1. docs(zotero): add MAINTENANCE_PLAN.md
2. docs(zotero): add CONVENTIONS.md
3. docs(zotero): add handoff documents for threads 2-4
4. fix(zotero): remove control character from bbt_citation_key_refresh.js
5. chore(zotero): delete deprecated backup scripts
6. chore(zotero): retire filename-based duplicate checker
7. refactor(zotero): move find_files.sh to one-time-operations
8. refactor(zotero): split add-google-tag.js into single-purpose actions
9. docs(zotero): add README.md; fold and remove general_settings.md

Commits 1-3 are the documentation series (this patch set). Commits 4-9 are
the code-change series, delivered after the documents are reviewed.
