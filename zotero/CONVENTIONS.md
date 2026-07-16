# Conventions

Two parts. Part A: engineering conventions for all scripts in zotero/,
extracted from the proven patterns in console_js/bbt_export.js and
console_js/bbt_citation_key_refresh.js. Part B: library conventions --
the semantics of the library itself (tags, filenames, keys). Part B
entries marked DRAFT await confirmation by the library owner.

Guiding philosophy: maximum explicitness and transparency. No hidden
control flow, no indirection, no coupling. Data-driven programming over
object-oriented programming. Plain functions and plain data tables.
Every knob visible in one place. Every destructive action gated and
announced.

## Part A: Engineering conventions

### A1. Languages and where code runs

- Zotero console JavaScript (Tools > Developer > Run JavaScript) for
  anything that reads or writes the Zotero library or uses Zotero APIs.
- PowerShell for anything on the Windows filesystem outside Zotero
  (moving files, backups, verification). Scaffold new PS1 tools from
  powershell/Backup-ZoteroStorage.ps1.
- Bash only for trivial WSL-side developer utilities. Never for the live
  library or attachment files.

### A2. Script layout (console JS)

Numbered sections, in order, with banner comments:

    1. CONFIGURATION  - single CONFIG object; every knob lives here
    2. STATE          - timing object, counters, accumulators
    3. HELPERS        - small plain functions; no classes
    4. PRE-FLIGHT     - assertions before any work
    5. MAIN           - the work, batched
    6. SUMMARY        - return a summary object; print totals

Header block at the top: name, version, purpose, usage, features,
validation protocol, output description. See bbt_export.js for the
reference format.

### A3. CONFIG object rules

- All tunables in one CONFIG object at the top. No magic numbers below.
- Safety limits are explicit: HARD_CAP / LIMIT for library size,
  MAX_TO_PROCESS for partial runs, START_INDEX for resume.
- Every guard has an explicit, single, named bypass flag (e.g.
  BYPASS_VERSION_CHECK). Bypassing is a visible decision, never a default.
- Version guards record a tested ceiling (MIN_/MAX_ZOTERO_VERSION and
  plugin versions). When a script is confirmed on a newer version, bump
  the ceiling in the same change.

### A4. Safety defaults

- Report-only / dry-run is the default mode. Destructive behavior
  requires an explicit flag (DRY_RUN=false, -Execute, etc.).
- Before any destructive step, print the full plan (what will be
  touched, counts, destinations) and, where interactive, require
  confirmation.
- Detection and destruction are separate tools. A reporter never
  deletes. A deleter consumes a reviewed input list, validates every
  path (containment check under the expected base), and quarantines
  (move) rather than deletes where possible.
- Validation ramp for library-scale scripts: run at 1000 items, then
  5000, then 10000, then full. Record stability at each step.

### A5. Scale patterns (mandatory at ~60k items)

- Batch processing with an explicit BATCH_SIZE.
- Yield to the event loop between batches (await a delay) to keep the
  UI responsive.
- Adaptive backoff: if a batch runs slow, increase the yield, capped.
- Per-item timeout guards for operations that can hang.
- Checkpoint logging every N items so a crashed run can resume via
  START_INDEX. Process in a stable order (sort IDs) so resume is valid.
- Consecutive-failure abort to detect an unhealthy state early.
- Optional periodic forced GC where available.
- Progress reporting: Zotero.debug at intervals; ProgressWindow when a
  user is watching.

### A6. Observability

- timing/stats object accumulates counts and durations; returned as the
  script result and printed in SUMMARY.
- Failures are collected (ids, reasons), not swallowed; a bounded sample
  is included in the result.
- Long-running or scheduled tools append a run record (timestamp, mode,
  counts, outcome) to a log file. Proposed standard (pending spike S4):
  Zotero.debug always; append-file in the data directory for run
  records; ProgressWindow only for brief user-facing summaries.

### A7. Data-driven style

- Behavior variation lives in data tables (arrays of plain objects), not
  in class hierarchies or dispatch trees. Example: automation rules are
  {name, guard, apply} entries evaluated in order, each independent, no
  shared mutable state between rules.
- Rules and operations must be idempotent: running twice changes nothing
  the second time.
- Constants that encode library semantics (tag names, base paths) are
  defined once in a named block (e.g. TAGS) and referenced, never inlined.

### A8. Files, encoding, delivery

- ASCII-only in all new files.
- Interchange between tools: one absolute Windows path per line in a
  UTF-8 text file, plus a JSON summary (counts, run metadata). Consumers
  validate paths before acting.
- Work is delivered as ordered patch series (git format-patch, applied
  with git am), one concern per commit, each commit independently
  sensible.
- Handoff documents under handoff/ carry design decisions and a
  "Verified facts" section populated by spikes, stamped with the tested
  Zotero/plugin versions. Threads commit finalized designs back into
  their handoff document before implementation commits begin.

### A9. Actions & Tags scripts

- Repository .js files are canonical; actions-zotero.yml is an exported
  backup refreshed after changes.
- One action per file, single purpose, named for what it does.
- Event-triggered actions must be idempotent, guard-first (cheapest
  checks earliest), and loop-safe (must not re-trigger themselves via
  their own saves; mechanism per spike S3 findings).

## Part B: Library conventions (owner-authored)

Every entry below is DRAFT unless marked CONFIRMED. Inferred from the
repository; confirm, correct, or extend.

### B1. Workflow tags (DRAFT)

Reading-state tags, prefix "__", intended to be mutually exclusive:

- __unopened     item ingested, file never opened
- __to_read      queued for reading
- __in_progress  currently reading (auto-added on file open)
- __read         finished (replaces __in_progress)
- __not_reading  deliberately not reading

Action/maintenance tags, prefix "__", may coexist with reading-state:

- __add-metadata item needs metadata completion (e.g. Google Books)
- __add-file     item needs a file attached

Known open points (Q1 in MAINTENANCE_PLAN.md):
- Are reading-state tags strictly mutually exclusive, and what is the
  resolution order when multiple are present? (convert_readstatus_to_tags.js
  implies: __unopened is replaced by stronger states; __to_read may
  coexist with __unopened.)
- Any renames, additions, or retirements desired?
- Read_Status in the extra field is legacy; tags are the source of truth.

### B2. Linked attachments (DRAFT)

- Base directory: <Windows user>/MIT Dropbox/<Dropbox user>/zotero-storage
- Attachments are linked files (not stored copies).
- Formats in use: pdf, html, epub, possibly others.
- Filename pattern: Author_Year_Title (underscores for spaces), as
  implied by find_files.sh patterns like "Bishop_2006_*". Confirm the
  exact rule (first author only? title truncation? produced by ZotFile,
  Attanger, or manual?).
- Historical base paths exist in the wild (e.g. "Dropbox (MIT)"); scripts
  comparing paths must account for stale-but-fixable bases.
- Quarantine convention: sibling folders next to the base for staged
  deletions (existing: pdf_to_delete; new: zotero-orphans).

### B3. Citation keys (DRAFT)

- Managed by Better BibTeX. citationKey field is authoritative.
- Exact BBT key format string: TO BE FILLED IN by owner.

### B4. Notes and annotations (DRAFT)

- Better Notes templates in better_notes_templates/ are the standard
  note formats (comprehensive, recall-after-reading variants).
- Annotation export conventions: TO BE DEFINED in thread 4 after spike S5.

### B5. To be written by owner

Placeholders for conventions the owner intends to record:

- Collection structure and naming: TODO
- Item-type-specific metadata requirements (what counts as complete for
  a book vs an article): TODO
- Backup cadence and retention: TODO
- Anything else: TODO
