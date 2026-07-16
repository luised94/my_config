# Thread 2 Handoff: Orphan Attachment Pipeline

Status: DESIGN FINALIZED (spikes S1, S2, S2b complete on Zotero 9.0.6,
2026-07). Ready for implementation.
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
3. This document's "Verified facts" section (DONE below) and finalized
   design (DONE below).

## Finalized design (post-spike)

The planning-thread design (preserved further down under "Original
planning design") stands, with the following refinements now that the
spikes have run. Where they differ, this section wins.

### Existence comes from the walk, not per-item disk checks

S1 established that for linked-file attachments getFilePath() returns the
intended absolute path whether or not the file exists on disk; it does
NOT stat the file. So the auditor does not perform 71k per-item existence
calls. Instead:

- Phase 1 collects each linked-file attachment's intended absolute path.
- Phase 2 walks the base directory (S2 method).
- Phase 3 does a two-way set difference on normalized paths.
  - On disk, not claimed by any item  -> orphan.
  - Claimed by an item, not on disk    -> broken link.
  - Both                               -> matched.

One comparison yields both orphans and broken links. getFilePathAsync()
(which returns false when the file is missing) and fileExists() are used
only on the small preflight validation sample, never across the library.
fileExists() must never be called on linked-URL attachments -- it throws
(S1).

### Phase 1 is DB-driven; no item objects materialized

S1: 71,437 of 71,442 linked-file attachments store a relative path of the
form "attachments:Author/File.ext". The auditor reads the itemAttachments
table directly (SELECT itemID, path FROM itemAttachments WHERE linkMode =
LINK_MODE_LINKED_FILE) and reconstructs the absolute path as
baseAttachmentPath + separator + (relative-part with "/" -> "\"). It does
NOT load Zotero item objects for the bulk pass (CONVENTIONS A10.7: loading
71k item objects anchors large graphs and defeats GC).

Trust-but-verify: in PRE-FLIGHT the auditor takes a random sample
(default 200) of linked-file attachments, loads them as items, and asserts
that the reconstructed absolute path equals getFilePath(). If any mismatch,
it aborts before the bulk pass. This keeps the DB shortcut honest.

The 5 linked-file attachments whose stored path is absolute (not
"attachments:") are read from the path column directly and classified by
base (see stale bucket).

### linkMode scope (S1)

Only LINK_MODE_LINKED_FILE (2) attachments live under the linked base and
are in scope. LINK_MODE_IMPORTED_FILE (0), IMPORTED_URL (1), and
EMBEDDED_IMAGE (4) all resolve into the Zotero storage/ directory
(out of scope, D3). LINK_MODE_LINKED_URL (3) has no file at all (empty
path). The auditor's Phase-1 query filters to linkMode = 2 and ignores the
rest; it records their counts in run_summary for reconciliation only.

### Stale-vs-missing broken-link bucket is tiny but kept

With baseAttachmentPath set to the current directory and 71,437/71,442
paths relative, the "stale historical base" bucket can contain at most the
5 absolute-path outliers. The bucket is still implemented (the historical
"Dropbox (MIT)" base in B2 is real and could reappear after a machine
switch), but we do not over-engineer it. Known historical bases live in
CONFIG (OQ1 resolved: the only confirmed current base is
"C:\Users\<user>\MIT Dropbox\<dropbox user>\zotero-storage"; the user
switches between two machines, so <user> and <dropbox user> are CONFIG
parameters, not hard-coded).

### Path normalization and the NFC decision

Both sides are normalized before comparison: lowercase, unify separators
("/" -> "\"), and Unicode NFC. S2 found 6,913 non-ASCII paths (~9% of the
library: Korean, Chinese, Hebrew-script, and Latin-with-diacritics author
folders), so normalization is load-bearing, not a corner case.

Decision (dated 2026-07, owner-confirmed reasoning): the owner has never
observed Dropbox changing a file's Unicode normalization between the two
machines but cannot rule it out. Rather than silently fold or build a
dedicated NFC pipeline, the auditor NFC-normalizes both sides so an
NFC-vs-NFD difference never produces a false orphan, AND when a library
path matches a disk path ONLY after NFC folding (their raw forms differed),
that pair is written to normalization_mismatches.txt with a count in
run_summary.json. These are matches, never orphans, so the mover never
touches them; there is no destructive risk. If the count is always zero,
the owner has evidence the problem does not occur in this setup and the
report costs nothing. If it is ever non-zero, the owner has the exact
files to inspect.

### Snapshot resource-folder false positives do not apply here

S2 found maxDepth 2 (base/author/file): every file sits directly in an
author folder, with no per-snapshot "_files/" resource subfolders. The
usual orphan-detection trap -- thousands of un-linked snapshot resource
files flagged as orphans -- does not exist in this library. No special
casing needed. (If depth ever exceeds 2 in a future run, revisit.)

### Metadata-gap side report (OQ2 resolved: yes)

While Phase 1 iterates attachments, the auditor joins to parent items and
counts, at near-zero cost, linked-file items whose parent is missing a
creator and/or a date -- the inputs to the owner's citation-key scheme
(auth.fold + year + title). This is an OPT-IN CONFIG flag (default on),
kept strictly off the orphan critical path. It emits counts plus a bounded
sample of offending item keys into run_summary.json. It does NOT fix
anything; the metadata-completion fixer is a separate future thread. The
"_" top-level folder (missing author) is expected per the owner; the
"undefined" folder (349 files, S2) is of unknown origin and is surfaced in
the per-folder breakdown for the owner to inspect, not assumed to be a bug.

### Per-top-level-folder breakdown (new)

The report breaks orphan and matched counts down by top-level (author)
folder. This makes the "_" (4,244 files) and "undefined" (349 files)
folders visible and lets the owner see whether orphans cluster anywhere
(e.g. the ".epu" truncation cases, or a specific import).

### Reconciliation identity

folder files = matched + orphans + ignored + stat-failures
library linked-file links = matched + broken (missing) + broken (stale)
                            + duplicate-link surplus

Duplicate links (two items linking the same file) and case-or-NFC
duplicate paths are counted separately (duplicateLinks in run_summary) so
the arithmetic closes. The auditor asserts the identity in SUMMARY and
flags any residual.

### Outputs (Zotero data directory, timestamped)

- orphans.txt                    (one absolute Windows path per line, UTF-8)
- broken_links_missing.txt
- broken_links_stale.txt
- normalization_mismatches.txt
- run_summary.json               (counts, durations, config snapshot,
                                  version stamps, metadata-gap sample,
                                  per-folder breakdown)

### Scale treatment (S2-informed)

The walk is getChildren-call-bound, not entry-bound: this library has
~28,700 directories, and the top-level base directory alone returns
~28,740 children in a single getChildren array (S2: getChildren buffers
per directory, it does not stream). Batching and event-loop yields key on
ENTRY count, not directory count (the S2 v1.0 bug slept ~34s by yielding
per-directory; v1.1 fixed it). Budget ~2 min worst case for the walk:
throughput was ~3,600-4,600 entries/s early, dropping to a stable
~1,300/s partway through a cold walk (NTFS/cloud-filter metadata cost;
not investigated further, stable not degrading). Mandatory per A5:
batching, yields, adaptive backoff, checkpoint logging, hard caps
(MAX_ENTRIES), consecutive-failure abort, timing summary.

### Mover (Move-OrphanFiles.ps1), S2b-informed

Plain Move-Item, NOT robocopy. S2b verified that Move-Item within the
Dropbox root (same NTFS volume) is a rename that preserves the online-only
placeholder exactly (no hydration, no byte read, no corruption).
robocopy /MOV copies-then-deletes even on the same volume and would
hydrate; a cross-volume Move-Item silently degrades to copy+delete and
would also hydrate. Therefore the mover:

- Dry-run by default; -Execute to act.
- Validates every input path is under the base directory (containment).
- Validates source and destination share the same volume root; aborts
  otherwise (prevents hydration).
- Moves into the quarantine preserving relative subfolder structure.
- Quarantine: sibling folder "zotero-orphans" next to the base, INSIDE the
  Dropbox root and on the same volume (D4). Dated subfolder per run
  (OQ3 resolved: dated subfolder, not manual purge).
- Post-move reconciliation counts; append-file run log.
- No dehydration step: moves never hydrate, so there is nothing to
  dehydrate. (S2b's attrib +U probe was inconclusive because the test file
  was already dehydrated; moot for this design.)

## Spikes (DONE)

S1 attachment introspection, S2 directory walk, and S2b placeholder-move
are complete; scripts are in zotero/spikes/. Findings below. S2b is the
PowerShell placeholder/hydration test (numbered S2b, not S3, because
MAINTENANCE_PLAN section 5 reserves S3 for thread 3).

## Open questions (RESOLVED)

- OQ1 (historical bases): current base is
  C:\Users\<user>\MIT Dropbox\<dropbox user>\zotero-storage, with <user>
  and <dropbox user> as CONFIG parameters (two machines). Historical
  "Dropbox (MIT)" base kept in CONFIG as a stale candidate.
- OQ2 (zero-attachment / metadata gap count): yes, opt-in side report,
  default on, off the critical path.
- OQ3 (quarantine retention): dated subfolder per run under zotero-orphans.
- OQ4 (whitelist for intentional non-Zotero files): not needed now. S2
  found zero ignore-list hits and no non-attachment files in the base; the
  ignore list is kept as cheap insurance and extended if a real audit
  surfaces intentional files.

## Acceptance criteria

- Auditor completes a full run in report-only mode with zero writes to
  the library, UI usable throughout, no crash; produces the output lists
  and run_summary.json; counts reconcile per the identity above.
- Validation ramp observed: 1000 / 5000 / full (A4).
- Mover dry-run prints an exact plan; -Execute moves only listed,
  contained, same-volume paths; post-move reconciliation matches the plan;
  restore path verified once manually (move a file back); a spot-checked
  online-only file remains online-only after the move.

## Verified facts

Stamped: Zotero 9.0.6, Windows (version TODO: owner to stamp), Dropbox
desktop client (version TODO: owner to stamp). Spike run 2026-07.

The reusable subset of these facts (attachment-API semantics, IOUtils and
Move-Item behavior) is promoted to VERIFIED_ENVIRONMENT.md; the
library-specific measurements below stay here.

### From S1 (attachment introspection)

- linkMode constants: IMPORTED_FILE=0, IMPORTED_URL=1, LINKED_FILE=2,
  LINKED_URL=3, EMBEDDED_IMAGE=4.
- My Library (libraryID 1) attachment counts: imported_file 10,
  imported_url 37, linked_file 71,442, linked_url 6,237,
  embedded_image 206. Zero attachments in trash.
- 71,437 of 71,442 linked-file paths are relative ("attachments:"). The
  other 5 are absolute.
- Relative path form: "attachments:Author/Author_Year_Title.ext".
  Absolute reconstruction: baseAttachmentPath + "\" + relative-with-"/"
  swapped to "\". Verified against getFilePath() on the sample.
- getFilePath(): returns the intended absolute path for file-backed
  linkModes REGARDLESS of whether the file exists on disk (does not stat).
  Returns false for linked-URL.
- getFilePathAsync(): returns the absolute path when the file exists,
  false when it is missing. (This is the disk-checking variant.)
- fileExists(): returns a boolean for file-backed attachments; THROWS on
  linked-URL attachments ("cannot be called on link attachments"). Never
  call it on linkMode 3.
- imported_file / imported_url / embedded_image all resolve into
  C:\Users\<user>\Zotero\storage\... (Zotero storage dir), NOT the linked
  base -- confirming they are out of scope (D3).
- Missing-file scan: 2,000 linked-file attachments (ordered prefix by
  itemID) checked, 0 missing. Most linked files are present; broken links
  are the minority case, consistent with the file-count surplus being
  mostly orphans rather than the library pointing at absent files.
- Content types (attachment table): pdf 56,611; html 19,702;
  epub+zip 1,277; png 206; null 89; octet-stream 33; then a long tail.
- Zotero.DB.queryAsync REJECTS an inline LIKE literal ("Please enter a
  LIKE clause with bindings"); the pattern MUST be a bound parameter.
  (Recorded in CONVENTIONS as a Zotero-DB note.)

### From S2 (directory walk)

- Base: C:\Users\Luised94\MIT Dropbox\Luis Martinez\zotero-storage.
- 78,152 files, 28,746 directories, 436.1 GB, maxDepth 2.
- Surplus vs library: 78,152 files on disk - 71,442 linked-file links =
  ~6,710 candidate files (before duplicate-link and broken-link
  adjustment). This surplus is the pipeline's reason to exist.
- IOUtils.getChildren returns a full array PER DIRECTORY (buffered, not
  streamed). Largest single call: the base itself, ~28,740 children. One
  "_" folder holds 4,244 files (missing-author bucket, expected). Author
  folders are otherwise small (max a few hundred). Per-call memory is thus
  bounded by the base directory's child count.
- IOUtils.stat is metadata-only; no file contents read. No Dropbox
  hydration observed during the walk (owner to spot-confirm badges).
- Wall time ~49s. Throughput ~3,600-4,600 entries/s early, dropping to a
  stable ~1,300/s partway through a cold walk. Budget ~2 min worst case.
- Zero ignore-list hits (no desktop.ini / thumbs.db / .dropbox / ~$ /
  .tmp anywhere in the base).
- 6,913 non-ASCII file paths (~9%): multiple scripts (Korean, Chinese,
  Hebrew, Latin-with-diacritics). Drives the NFC decision above.
- Extension histogram: .pdf 61,504; .html 14,030; .epub 1,198; .png 915;
  .txt 295; .epu 81 (truncated ".epub" -- candidate orphan/broken pairs);
  .jpg 52; .djvu 48; long tail. Mixed-case extensions (.PDF) exist in the
  wild; lowercasing handles them.
- "undefined" top-level folder: 349 files, origin unknown, surfaced for
  owner inspection (not assumed a bug).

### From S2b (placeholder move / hydration)

- Move-Item within the Dropbox root (same NTFS volume) preserves the
  online-only placeholder EXACTLY: raw attributes 0x00501620 identical
  before / at destination / after move-back; RecallOnDataAccess bit
  intact; LastWriteTime unchanged; file length unchanged. RESULT: PASS,
  no hydration, no corruption.
- Consequence: the mover uses Move-Item, enforces same-volume containment,
  and keeps the quarantine inside the Dropbox root. robocopy /MOV and
  cross-volume moves are rejected (both copy-then-delete -> hydration).
- Dehydration via attrib +U: INCONCLUSIVE (the test file was already
  dehydrated). Moot for the mover, since moves do not hydrate.

## Original planning design (preserved for provenance)

- Scope: linked-file base directory only; Zotero storage/ out of scope.
  My Library only. All attachment formats in scope (pdf, html, epub, ...).
- Ignore list (data-driven, CONFIG): OS/sync noise such as desktop.ini,
  thumbs.db, .dropbox*, ~$*, .tmp. Extend as discovered.
- Two-phase detection with a set difference on normalized paths; report
  original paths.
- Broken links bucketed: stale known base (fixable with
  adjust_attachment_paths.js) vs genuinely missing.
- Outputs written to the Zotero data directory with timestamps; one
  absolute Windows path per line, UTF-8, plus run_summary.json.
- Scale treatment mandatory (A5). Mover: dry-run default, containment
  check, quarantine preserving structure, reconciliation, append log.
- Dropbox online-only placeholders count as "exists"; enumeration must not
  read file contents. (Confirmed by S2.)
