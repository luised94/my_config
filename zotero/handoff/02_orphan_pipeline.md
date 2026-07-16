# Thread 2 Handoff: Orphan Attachment Pipeline

Status: PLANNED (design to be finalized in-thread after spikes S1, S2)
Reads: MAINTENANCE_PLAN.md (D2, D3, D4, S1, S2), CONVENTIONS.md (A2-A8, B2)

## Objective

Find files in the linked-attachment base directory that no library item
links to (orphans), and items whose linked file is missing (broken
links), then quarantine reviewed orphans. This is the highest-priority
maintenance capability.

## Deliverables

1. console_js/audit_orphan_attachments.js -- detection, report-only.
2. powershell/Move-OrphanFiles.ps1 -- quarantine mover, consumes the
   auditor's output list. Ported from Backup-ZoteroStorage.ps1 scaffold.
3. Updated "Verified facts" section in this document (spike results).

## Decided design (from planning thread)

- Scope: linked-file base directory only; Zotero storage/ out of scope.
  My Library only. All attachment formats in scope (pdf, html, epub, ...).
- Ignore list (data-driven, CONFIG): OS/sync noise such as desktop.ini,
  thumbs.db, .dropbox*, ~$*, .tmp. Extend as discovered.
- Two-phase detection:
  Phase 1: collect attachment file paths from the library (linked-file
  linkMode only; exclude linked URLs and stored files -- exact linkMode
  constants confirmed by S1).
  Phase 2: enumerate the base directory via IOUtils (behavior confirmed
  by S2).
  Phase 3: set difference both ways on normalized paths.
- Path normalization: lowercase, unify separators; report original paths.
- Broken links bucketed: (a) stale known base path -- fixable with
  adjust_attachment_paths.js; (b) genuinely missing. Known historical
  bases listed in CONFIG.
- Outputs, written to the Zotero data directory with timestamps:
  orphans.txt and broken_links_missing.txt / broken_links_stale.txt
  (one absolute Windows path per line, UTF-8), run_summary.json
  (counts, durations, config snapshot, version stamps).
- Scale treatment mandatory (60k+ items, more files than items): batching
  on BOTH loops (item collection and directory walk), event-loop yields,
  adaptive backoff, checkpoint logging, hard caps, consecutive-failure
  abort, timing summary. Per CONVENTIONS.md A5.
- Mover (PS1): dry-run default, -Execute to act; validates every input
  path is under the base directory (containment check); moves to
  quarantine preserving relative subfolder structure; reconciliation
  counts after the move; append log. Quarantine: sibling folder
  "zotero-orphans" next to the base (D4).
- Dropbox online-only placeholders count as "exists" -- enumeration must
  not read file contents (would trigger mass hydration). State this in
  the script header.

## Spikes to run first (interactive; paste results back)

S1 attachment introspection (~50 items):
- Distinct linkMode values present and their counts.
- getFilePath() return for: linked file present, linked file missing,
  stored file, linked URL, snapshot, epub/html attachment.
- Any attachments with relative paths / base-directory setting in play?
Expected output committed here as Verified facts.

S2 directory walk at scale:
- IOUtils enumeration of the full base: wall time, apparent memory
  behavior, whether it returns entries incrementally or all at once.
- Confirm no Dropbox hydration is triggered by stat/enumerate.
- File count and total size (informs progress reporting granularity).

## Open questions (finalize in-thread)

- OQ1: exact known historical base paths to classify "stale" bucket.
- OQ2: should the auditor also emit a count of items with zero
  attachments (cheap while iterating; useful for __add-file workflow)?
- OQ3: retention policy for zotero-orphans (manual purge vs dated
  subfolders per run). Proposal: dated subfolder per run.
- OQ4: does the linked base contain intentional non-Zotero files that
  need a whitelist (e.g. README, folder art)?

## Acceptance criteria

- Auditor completes a full run in report-only mode with zero writes to
  the library, UI usable throughout, no crash; produces the three lists
  and run_summary.json; counts reconcile (library links = matched +
  broken; folder files = matched + orphans + ignored).
- Validation ramp observed: 1000 / 5000 / full.
- Mover dry-run prints an exact plan; -Execute moves only listed,
  contained paths; post-move reconciliation matches the plan; restore
  path verified once manually (move a file back).

## Verified facts (populated by spikes)

(empty -- fill with S1/S2 findings, stamped with Zotero version)
