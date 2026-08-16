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
| console_js/bbt_export.js | KEEP. Flagship script. Fixed: stray non-ASCII byte (0xFB) on line 91 removed (thread 2 ASCII sweep, 2026-07). Open item: incremental-export scaffolding is half built; either finish incremental slicing or freeze as full-export-only with a comment. |
| console_js/bbt_citation_key_refresh.js | KEEP. Fix one stray 0x1A control character in a comment. Open item: sort item IDs before processing so START_INDEX resume is order-stable. |
| console_js/convert_readstatus_to_tags.js | SALVAGE, SUPERSEDED. Its replace-__unopened intent was completed by one-time-operations/reconcile_read_status.js (thread 3, 2026-08-12) under detect-then-write discipline; this draft never ran. |
| console_js/determine_readstatus_and_tag_combinations.js | SALVAGE, SUPERSEDED. Generalized into console_js/tag_hygiene_report.js (recurring, lean) plus one-time-operations/diagnose_thread3_tag_state.js (historically contingent checks). |
| console_js/adjust_attachment_paths.js | KEEP. Useful whenever a base path changes. Also informs the orphan pipeline (historical base paths). |
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
- D5: Automation rules are a data-driven table of {name, guard, apply},
  idempotent, with cheap guards first; LOG_ONLY (DRY_RUN) is the default
  mode. TRIGGER SUPERSEDED (owner, 2026-08-11, see
  DECISION_NOTE_thread3_manual_console.md and handoff/03 IMPLEMENTATION
  LOG): the thread-3 normalizer is a MANUAL CONSOLE PASS scoped by input
  set, not an item-added Actions & Tags event action. Running after imports
  settle removes the write-contention window that forced mandatory
  per-item retries and risked bulk serialization; it also collapsed the
  former event-action + backfill-runner into one script
  (console_js/normalize_items.js). The rules-table philosophy above is
  unchanged; only the trigger changed.
- D6: js files in this repository are canonical for Actions & Tags actions;
  actions-zotero.yml is a backup export.
- D7: Delivery model: work is batched per thread; each commit is delivered
  as a patch in an ordered series (git format-patch / git am) with an
  application note, reviewable before anything touches the repo.
- D8: Every load-bearing assumption about Zotero internals is verified by a
  spike before design freezes. Spike findings are committed into the
  relevant handoff document as "Verified facts" with the Zotero and plugin
  versions they were tested against. A thread's handoff holds that
  thread's specific measurements; reusable host-environment behavior (API
  semantics, filesystem behavior) is promoted to VERIFIED_ENVIRONMENT.md,
  version-stamped, so it outlives the thread. (Amended thread 2, 2026-07.)
- D9: All new files are ASCII-only.

## 4. Open questions

- Q1: Tag taxonomy refinement. RESOLVED (owner, 2026-08-11/12; folded into
  CONVENTIONS.md Part B, no longer DRAFT). Settled: opened-state set is
  {__unopened, __in_progress, __read} (name-match, auto counts); __unopened
  is exclusive with __in_progress/__read; __in_progress + __read may coexist
  (revisit); __unopened may coexist with __to_read and with __not_reading;
  __print is orthogonal ownership and marks "file not applicable". The
  normalizer's R1 guard and the tag-hygiene report's contradiction check are
  built on exactly these rules.
- Q2: Reporting standard for automatic actions. RESOLVED (S4, thread 3):
  Zotero.debug always; appended JSONL for run records needing later
  analysis; Zotero.ProgressWindow only for brief user-facing summaries,
  never per-item in a bulk pass. The thread-3 scripts follow this.
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
  natural fit alongside any thread's spike work. Thread 2 confirmed
  Zotero 9.0.6 for the console, attachment, DB, and IOUtils APIs
  (VERIFIED_ENVIRONMENT.md); the BBT export/key path is NOT yet
  re-confirmed on 9.0.6, so bbt_* script ceilings stay as they are until
  a run verifies them.
- Q7: Origin of the "undefined" top-level attachment folder (349 files,
  found by S2). Likely an older tool serializing a missing author as the
  literal string "undefined" (distinct from the intended "_" missing
  author folder). Owner does not currently know. Harmless to the orphan
  pipeline (surfaced in the per-folder breakdown); relevant to the future
  metadata-completeness thread. Not scheduled.

## 5. Spike track

Cheap throwaway console scripts run interactively (user pastes output back).
Spikes live in their threads, not in thread 1. Completed spike scripts are
kept in spikes/ with a STATUS header. Numbering matches this section; a
sub-spike that splits off mid-thread takes a letter suffix (e.g. S2b).

- S1 (thread 2): DONE (Zotero 9.0.6, 2026-07). Attachment introspection.
  Findings in handoff/02 and VERIFIED_ENVIRONMENT.md.
  spikes/spike_s1_attachment_introspection.js.
- S2 (thread 2): DONE (2026-07). IOUtils directory walk at scale.
  Findings in handoff/02 and VERIFIED_ENVIRONMENT.md.
  spikes/spike_s2_directory_walk.js.
- S2b (thread 2): DONE (2026-07). Dropbox placeholder move/hydration test
  (PowerShell). Move-Item within the Dropbox root preserves online-only
  placeholders. spikes/Spike-S2b-PlaceholderMove.ps1.
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
- Thread 2: orphan attachment pipeline. COMPLETE (2026-07/08). S1, S2,
  S2b, S2c done; audit_orphan_attachments.js, Move-OrphanFiles.ps1,
  Restore-OrphanFiles.ps1, collect_broken_links.js, and
  repair_attachment_paths.js all built. The sweep RAN: 7,412 orphan files
  quarantined, verified independently on both machines, orphan sediment
  6,972 -> 1, broken links unchanged at 72 throughout. Full outcome and
  the findings it surfaced are in handoff/02_orphan_pipeline.md.
  Residual owner tasks: run repair_attachment_paths.js (dry-run then
  apply) for the 5 stale-base and ~42 trailing-dot paths; delete the
  quarantine folder once satisfied.
- Thread 3: incoming-item automation, test-first. SPIKES COMPLETE
  (S3, S4 built, run, and written up). Mechanics are now settled by
  measurement -- see the verified findings in
  handoff/03_incoming_automation.md, summarized under "Cross-cutting
  verified facts" below. STILL BLOCKED ON: Q1 (tag taxonomy; owner
  decision) and the deferred large-bulk-import measurement. Then build
  the rules-table normalizer, backfill runner, and tag-hygiene report.
- Thread 4: annotation export. Deliberately under-specified until S5.
  S5 IS BUILT (spikes/spike_s5_annotation_introspection.js) and PENDING
  a run; nothing else in this thread should be designed until its
  results are pasted into handoff/04_annotation_export.md. Independent;
  can float.
- Thread 6 (NEW, unscheduled, HIGH VALUE): path-component sanitization in
  the file-naming pipeline. Windows silently strips trailing dots and
  spaces from path components, so every author with a suffix (Jr., Inc.,
  Ltd., Ph.D.) or a terminal initial produces a stored path that can
  never resolve. This is ACTIVE DATA LOSS, not historical sediment: the
  owner reports files "don't get saved sometimes and some are lost during
  renaming". 42 of 73 broken links share this signature. The REPAIR half
  exists (repair_attachment_paths.js, TRAILING_DOT strategy); the
  PREVENTION half does not and belongs with the Attanger/BBT naming work.
  Read the naming pipeline before proposing a fix. Full write-up under
  "FINDING: Windows strips trailing dots" in
  handoff/02_orphan_pipeline.md.
- Thread 5 (deferred, not yet specified): metadata completeness and
  citation-key integrity. Ensure items carry at least a date and some
  form of author, since citation keys (CONVENTIONS B3) are built from
  author + year + title and feed the owner's external knowledge system.
  Load-bearing constraint: backfilling author/year CHANGES the key and
  can break existing citations, so this thread must treat key stability
  as first-class and coordinate with bbt_citation_key_refresh.js. Data is
  collected opportunistically meanwhile by the orphan auditor's opt-in
  metadata-gap report (thread 2) and relates to the "_"/"undefined"
  attachment folders (B2, Q7). Owner has flagged this as possibly more
  important than it first appears; scope before starting.

Ordering (revised 2026-08-06, threads 1 and 2 complete):
1. Thread 6 (trailing-dot prevention) -- ranked first because it is the
   only item on this list causing ONGOING loss. Everything else is
   improvement; this is stopping a leak.
2. Q1 (tag taxonomy) -- an owner decision, not implementation work, and
   it is the sole remaining blocker on thread 3's largest deliverable.
   Cheap to settle, unblocks the most.
3. Thread 3 implementation, after Q1 and after one bulk-import
   measurement pass.
4. Thread 4, after S5 is run. Independent; can float earlier if the
   annotation work is more motivating.
5. Thread 5 (metadata completeness) -- now has real seed data from the
   thread-2 audit (944 missing creator, 1,481 missing date, 942 missing
   both, plus the "_"/"undefined" degenerate-key population). Note the
   owner has since done a large MANUAL metadata cleanup, so re-measure
   before scoping; the numbers above predate it.

Also outstanding, small: resolve the duplicate BBT refresher scripts
(see the file inventory) and fold in snippets/spikes from other threads
that have not yet been collected into zotero/console_js.

## 6b. Cross-cutting verified facts (2026-07/08)

Environment truths established by spikes, applicable to ANY script in
this repository. Recorded here rather than only in a thread handoff
because each was learned the hard way and is expensive to rediscover.

- IOUtils write mode 'append' REFUSES TO CREATE a missing file; use
  'appendOrCreate'. This silently produced an empty log directory and no
  file for a whole spike run (S3).
- Zotero returns parentItemID FALSE (not null) for a top-level item. A
  child-vs-top-level test must check both or it counts every top-level
  item as a child.
- Windows silently strips trailing dots and spaces from path components
  (see thread 6). Any code constructing a filesystem path from
  user/metadata text must sanitize per component.
- Console mojibake is NOT evidence of data corruption. PowerShell renders
  UTF-8 through a legacy codepage; verify with Test-Path against the real
  path before concluding anything is broken (S2c).
- An A&T action body: fires as event "Create Item" / operation "Script";
  receives the item as `item`; runs an async IIFE to completion with
  working await; keeps its scope ACROSS fires within a Zotero session
  (so module-level counters accumulate); does NOT fire for child
  attachments or notes; and is NOT re-triggered by its own saves.
- An awaited saveTx inside an action CAN STILL BE LOST, and fire-time
  state does NOT predict which writes will be lost. Read-back
  verification plus retry is mandatory and must be UNCONDITIONAL. One
  retry recovered every loss observed. Do not build a fast path that
  skips verification for "safe-looking" items (S4).
- Reporting standard (OQ3, settled): Zotero.debug always; appended JSONL
  in the data directory when a run needs after-the-fact analysis;
  ProgressWindow (~3000ms) only for events the user should NOTICE, never
  per-item during a bulk import.
- Reading file METADATA (IOUtils.stat/exists) does not hydrate Dropbox
  online-only placeholders; reading file CONTENT does. Only S5 reads
  content, deliberately and with a small sample.

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
