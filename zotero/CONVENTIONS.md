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
- Spikes live in spikes/, one file per spike, named spike_sN_desc.js
  (console) or Spike-SN-Desc.ps1 (PowerShell), with N the number from
  MAINTENANCE_PLAN section 5 and a letter for sub-spikes (S2b). Each
  spike is committed with a STATUS header (completed, thread, version,
  what it verified). A spike script: is report-only by default (a spike
  never mutates the library or files except a single explicitly-named
  test target); in the Zotero console, uses the "Run as async function"
  checkbox with top-level await, not an async IIFE (A10.2); wraps its
  body in try/catch that logs via Zotero.debug and rethrows so failures
  are loud; and returns a plain summary object as its result (also
  mirrored to Zotero.debug line by line, since the console log survives
  even when the return value does not). When a spike's findings involve
  non-ASCII data (e.g. file paths), the write-up DESCRIBES and COUNTS
  them rather than pasting the raw characters, to keep docs ASCII (A8).
  Reusable host-environment facts (as opposed to a single library's
  measurements) are promoted from the handoff to VERIFIED_ENVIRONMENT.md.

### A9. Actions & Tags scripts

- Repository .js files are canonical; actions-zotero.yml is an exported
  backup refreshed after changes.
- One action per file, single purpose, named for what it does.
- Event-triggered actions must be idempotent, guard-first (cheapest
  checks earliest), and loop-safe (must not re-trigger themselves via
  their own saves; mechanism per spike S3 findings).

### A10. JavaScript style

Baseline philosophy: boring and explicit beats clever, whenever
performance and memory are equal. Evaluated against the Zotero 7
console environment (privileged Firefox sandbox, single-file pasted
scripts, no build step, no module system, no web DOM) and against the
proven scripts in console_js/.

A10.1 Adopted rules (required in new JS):

- === and !== always. For null-or-undefined, write both checks
  explicitly or use a documented == null with a comment; default to
  the explicit pair.
- Semicolons required. No ASI reliance.
- One declaration per line. No comma declarations.
- No classes, no this, no prototypes, no new for own code. State is
  plain objects passed explicitly or closed over. Factories (functions
  returning plain objects) where construction is needed.
- No generators. Return arrays.
- for...of is the default loop. Plain indexed for where the index is
  needed. No forEach for control flow (break/continue do not work).
- No long map/filter/reduce chains. Break into explicit steps with
  named intermediate variables. Single-step map or filter is fine.
- Early exit: a for loop with if + break, not some/find acrobatics.
  (find for a simple lookup is acceptable.)
- Named function declarations for multi-line bodies. Arrow functions
  only for short, pure, single-expression callbacks.
- No && / || as statement-level control flow. Use if.
- switch: no fall-through ever; every case breaks or returns. Prefer
  if/else chains or a lookup table (data-driven) in JS.
- Errors: throw only Error instances. Never swallow exceptions; catch
  blocks log and count (see A6) or rethrow. Expected failures use
  return values; try/catch is for exceptional cases (JSON.parse, IO).
- assert(condition, message) helper throwing Error, used in PRE-FLIGHT;
  assertion count recorded in the timing object.
- Ban: with, void, new Function. eval is banned with one possible
  documented exception pending the script-runner decision
  (handoff/03 OQ5); if adopted, it gets a named wrapper, a fixed
  source directory, and a header warning.
- No implicit globals; every binding declared.

A10.2 Zotero-console-specific deviations (documented, intentional):

- var at the TOP LEVEL of console scripts is allowed and preferred.
  Reason: re-running a script in the same Run JavaScript window with
  top-level let/const throws redeclaration errors; var tolerates
  re-runs. Inside functions and blocks: const by default, let when
  reassigned, never var. Do not "modernize" top-level var away.
- To obtain await at the top level, use the Run JavaScript window's
  "Run as async function" checkbox and write top-level await directly.
  Do NOT wrap the script in an async IIFE.
  Changed 2026-07 (was: "async IIFE wrapper is allowed solely to obtain
  await"). Thread 2 spikes S1/S2 established that the Zotero 9.0.6 console
  does not await a returned Promise: an async IIFE causes the console to
  print "undefined / completed successfully" immediately while the script
  runs on in the background, the script's return value is lost, and any
  thrown error becomes a silent unhandled rejection (output simply stops
  mid-run). The checkbox awaits the body, so `return x;` becomes the
  displayed result and errors surface. Wrap the body in try/catch that
  logs via Zotero.debug and rethrows, so failures are loud either way.
  No other IIFEs; use blocks or named functions for scoping.
- Optional chaining ?. and nullish coalescing ?? are allowed for
  probing host/plugin APIs that legitimately vary by version
  (e.g. Components.utils?.forceGC, block?.content?.[0]?.text) and for
  reaching into externally-shaped data. They are not a substitute for
  explicit validation of our own data structures.
- Template literals are the DEFAULT for any string with interpolation,
  especially log lines. This diverges from advice preferring
  concatenation: for a logging-heavy codebase, template literals are
  the boring option (no escaping bugs, no + chains). Plain quotes for
  static strings; single quotes preferred.

A10.3 Tradeoffs decided (defaults; revisit only with reason):

- Ternary: allowed only as a single-line simple assignment
  (x = cond ? a : b). Anything nested or multi-line becomes if/else.
- Truthiness: new code writes explicit comparisons
  (arr.length > 0, x !== null, s !== ""). Existing truthy checks in
  kept scripts are grandfathered; fix opportunistically.
- Default parameters: allowed. The signature is the explicit, visible
  place for a default; an undefined-check in the body hides it.
- Destructuring: avoided. Write const a = obj.a;. Exception: none
  needed so far.
- Object copies: Object spread ({ ...src, extra }) allowed; building
  property-by-property preferred when the shape matters to the reader.
- Computed keys: assign after creation (obj[key] = value) rather than
  { [key]: value }.
- Async: async/await only; no .then chains. Sequential awaits by
  default; Promise.all only when parallelism is intentional and
  commented as such.
- Callbacks: no anonymous callback nested inside another anonymous
  callback; extract and name.
- No premature helpers. Added 2026-07 (thread 2). Do not extract a
  function until at least one of these holds: (a) it has three or more
  textual call sites; (b) it is a clear, pure generalization worth naming
  on its own; or (c) it is genuinely shared across files (and even then,
  inlining at each site is often still better than abstracting). "Textual
  call sites" means places it is written in the source, not runtime
  invocation count: a one-line filter written once but run 78k times in a
  loop stays inlined. Side-effecting helpers (that read or write files,
  the DB, or the library) state so in the name so a reader knows a call is
  not pure. The reference scripts' assert(), report()/log(), and a
  yield-to-event-loop helper qualify by call-site count and stay; single
  textual-use helpers like a one-off path-basename or ignore-list match
  are inlined. Rationale: in single-file console scripts, indirection
  costs more than the duplication it removes; a reader should follow the
  work top to bottom without chasing one-call-site functions.

A10.4 Dormant rules (activate only if a real plugin with UI and a
build step is ever built -- MAINTENANCE_PLAN thread map, tier 3):

- All DOM guidance: getElementById / single data-attribute selectors,
  no innerHTML with interpolated strings (XSS), createElement +
  textContent, explicit classList add/remove over toggle-with-flag.
- Module guidance: named exports only, no default exports, no barrel
  re-exports, no dynamic import().
- Tooling: ESLint wired to these rules. Nothing to attach it to today
  (console scripts have no build); revisit with the plugin.

A10.5 Not applicable to this codebase (recorded so we do not re-litigate):

- Event-listener architecture, "use strict" pragmas (console sandbox
  and function bodies make it moot; no implicit globals rule covers
  the risk), ES5 arguments-object patterns, IIFE-for-privacy (module
  closures and blocks cover it).

A10.6 Call-site clarity (substitutes for named arguments):

JavaScript has no named arguments and no import provenance in console
scripts. The substitutes:

- Options object: any own function with more than two parameters, or
  with ANY boolean parameter, takes a single options object:
  runAudit({ dryRun: true, limit: 500 }). The call site then reads
  like named arguments. Bare boolean positional arguments
  (doSomething(true, false)) are banned in own code.
- Inline argument comments for host APIs we cannot reshape:
  Zotero.Items.getAsync(id, /* options */ null).
- Provenance by full qualification: never alias or rename host APIs.
  Write Zotero.Items.getAsync(...) at every call site; no
  const get = Zotero.Items.getAsync. In a single-file console script
  every callable is then one of exactly two obvious origins: defined
  above in this file, or a fully qualified host/plugin API
  (Zotero.*, IOUtils.*, PathUtils.*, Services.*, Components.*).
- No magic literals at call sites; values that mean something come
  from CONFIG or a named constant block (TAGS, PATHS).

A10.7 Performance, memory, and behavior notes (why some rules exist;
ranked by how likely they are to matter at 60k items):

- forEach with an async callback DOES NOT await: it fires every
  callback immediately and returns. This silently launches thousands
  of concurrent promises and breaks batching. for...of with await is
  sequential and correct. This alone justifies the for...of rule.
- await in a loop is sequential BY DESIGN and that is usually what we
  want: Promise.all over thousands of item operations spikes memory,
  floods the DB, and starves the UI thread. Parallelism is opt-in,
  small, and commented (A10.3).
- Do not accumulate full Zotero item objects across the whole run;
  they anchor large object graphs and defeat GC (the reason for
  GC_EVERY in the BBT scripts). Accumulate ids, keys, paths, or small
  summary objects; let per-batch references die with the batch.
- Zotero.Items.getAll(libraryID) materializes the entire library in
  memory. Prefer Zotero.Search (or a DB id query) to get IDs, then
  load in batches with getAsync. The BBT scripts model this.
- Zotero.DB.queryAsync REJECTS an inline LIKE literal with the error
  "Please enter a LIKE clause with bindings" (a built-in injection
  guard). The pattern must be a bound parameter: write
  queryAsync('... WHERE path LIKE ?', ['attachments:%']), not the pattern
  inline. Discovered by thread 2 spike S1 on Zotero 9.0.6.
- One saveTx per item means one transaction per item: slow, and each
  fires notifications/sync bookkeeping. Batch writes inside
  Zotero.DB.executeTransaction (USE_TRANSACTION_WRAPPER pattern).
  Behavior note: notifications may be deferred/coalesced inside a
  transaction -- relevant to thread 3 loop-safety.
- Each stage of a map/filter/reduce chain allocates a full
  intermediate array. At tens of thousands of elements an explicit
  single-pass loop does the same work with zero intermediates. (For
  small arrays this is irrelevant; the ban is for clarity there.)
- Spread into calls or push -- fn(...bigArray),
  arr.push(...bigArray) -- passes every element as an argument and can
  exceed engine argument limits (order 100k, engine-dependent) or blow
  the stack. Use a loop or concat for large arrays. [...smallThing]
  is fine.
- Object/array spread and Object.assign copies are SHALLOW. Nested
  objects remain shared; mutating a "copy" mutates the original one
  level down. When a real copy matters, copy explicitly per field or
  structuredClone and say so.
- Per-item Zotero.debug or ProgressWindow updates dominate runtime at
  scale (string formatting + UI). Log and update at intervals
  (LOG_EVERY / progress every N items), totals in SUMMARY.
- try/catch has no meaningful cost in modern engines; the old
  "deoptimizes the function" advice is obsolete. Never contort code
  to avoid a catch block. The rule against try/catch for expected
  failures is about clarity, not speed.
- Building large report strings: collect lines in an array and join
  once at the end. (Engines handle += better than they used to, but
  array-join is predictably linear and reads as intent.)
- Template literals, optional chaining, destructuring, const vs var:
  performance is identical for our purposes. Every choice among these
  is made on clarity grounds alone; never justify a deviation from
  A10 with micro-performance claims.
- Closures capture their whole enclosing scope for as long as they
  live. A long-lived callback defined inside a loop over items can
  pin those items in memory. Prefer top-level named functions taking
  explicit parameters for anything with a lifetime.

A10.8 Rule-change protocol:

Some of these rules will eventually bite. When one does, do not
silently violate it. Either (a) add a dated exception here with the
rationale and the specific site it applies to, or (b) change the rule
here in the same change that violates it. Grandfathered code is fixed
opportunistically, never in bulk sweeps mixed with feature changes.

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

Ownership tags, prefix "__", orthogonal to reading-state (CONFIRMED):

- __print        physical copy of the item is owned

Known open points (Q1 in MAINTENANCE_PLAN.md):
- Are reading-state tags strictly mutually exclusive, and what is the
  resolution order when multiple are present? (convert_readstatus_to_tags.js
  implies: __unopened is replaced by stronger states; __to_read may
  coexist with __unopened.)
- Any renames, additions, or retirements desired?
- Read_Status in the extra field is legacy; tags are the source of truth.

### B2. Linked attachments (base path CONFIRMED; rest OBSERVED, thread 2)

- Base directory (CONFIRMED, S1 pref + S2 walk):
  C:\Users\<Windows user>\MIT Dropbox\<Dropbox user>\zotero-storage
  The owner switches between two machines, so <Windows user> and
  <Dropbox user> are CONFIG parameters, never hard-coded. Observed values
  on the primary machine: Luised94 / Luis Martinez.
- Attachments are linked files (LINK_MODE_LINKED_FILE = 2). Paths are
  stored relative ("attachments:Author/File.ext"): 71,437 of 71,442
  linked-file attachments are relative, 5 absolute (S1). Absolute
  reconstruction: base + "\" + relative-part with "/" -> "\".
  saveRelativeAttachmentPath is true.
- linkMode inventory (S1, My Library): linked_file 71,442; linked_url
  6,237; embedded_image 206; imported_url 37; imported_file 10; zero in
  trash. Only linked_file lives under this base; imported_* and
  embedded_image resolve into the Zotero storage/ directory (out of
  scope). linked_url has no file.
- Formats OBSERVED on disk (S2, by extension): pdf ~61.5k, html ~14k,
  epub ~1.2k, png ~900, txt ~300, jpg, djvu, mhtml, hocr, doc, mobi, rtf,
  plus 81 ".epu" (a truncated ".epub" -- filename truncation clips the
  extension in a few cases). Content types (S1): application/pdf,
  text/html, application/epub+zip, image/png, some null and
  application/octet-stream, a short tail. Total ~78,152 files, ~28,746
  folders, ~436 GB, folder depth 2 (base/author/file: no per-snapshot
  resource subfolders).
- Filename/folder pattern OBSERVED (S1 samples; owner to confirm the
  exact truncation length): top-level folder is the first author's
  surname with spaces PRESERVED (e.g. "de Luca"); surnames with
  diacritics keep their accented form (see the non-ASCII note below);
  the file is
  "Surname_Year_TitleWords.ext" with spaces replaced by underscores and
  the title truncated mid-word at roughly 45-50 characters (e.g.
  "..._An_Overvie.pdf", "..._Single_Notion,_Multiple_My.pdf"). Missing
  author lands in a "_" top-level folder (CONFIRMED by owner, expected).
  A separate "undefined" top-level folder (349 files) is of unknown
  origin (likely an older tool serializing a missing author as the
  literal string "undefined"); see MAINTENANCE_PLAN Q7.
- Non-ASCII paths are ~9% of the library (6,913 files, S2): Korean,
  Chinese, Hebrew-script, Latin-with-diacritics. Path comparison must
  normalize Unicode (NFC) as well as case and separators. Owner has not
  observed Dropbox changing a file's normalization between machines but
  cannot rule it out; the orphan auditor flags NFC-only matches rather
  than treating them as orphans (handoff/02 decision, 2026-07).
- Historical base paths exist in the wild (e.g. "Dropbox (MIT)"); scripts
  comparing paths must account for stale-but-fixable bases. With the
  current setup nearly all paths are relative, so the stale bucket is
  tiny, but adjust_attachment_paths.js remains the fixer.
- Quarantine convention: sibling folders next to the base for staged
  deletions, INSIDE the Dropbox root and on the same NTFS volume so moves
  stay rename-only (existing: pdf_to_delete; orphan pipeline:
  zotero-orphans, with a dated subfolder per run). Move-Item within the
  Dropbox root preserves Dropbox online-only placeholders (no hydration,
  no corruption -- S2b); robocopy and cross-volume moves do not and are
  banned for quarantine moves.

### B3. Citation keys (scheme described by owner; exact BBT string TBD)

- Managed by Better BibTeX. citationKey field is authoritative.
- Conceptual scheme (owner-described, thread 2): folded first-author
  surname + year + first significant title word (title lowercased,
  stopwords skipped, first word selected). Written by the owner as
  "auth.fold + year + title.lower.skipwords().select(1, 1)". The exact
  BBT formatter string is still TO BE FILLED IN from the live BBT config
  (Q6's environment-report spike is the natural place to capture it).
- Keys are used as citation anchors in the owner's external knowledge
  system. ENTAILMENT (load-bearing): a key is a function of author, year,
  and title, so any change to those fields changes the key. Backfilling a
  missing author or year (see B5) is therefore NOT a free metadata fix --
  it mutates the citation key and can break existing references in the
  knowledge system unless they are updated in lockstep. The filename
  analog of a degenerate key is the "_" / "undefined" attachment folder
  (B2). Any future metadata-completion work must treat key stability as a
  first-class constraint and coordinate with bbt_citation_key_refresh.js.

### B4. Notes and annotations (DRAFT)

- Better Notes templates in better_notes_templates/ are the standard
  note formats (comprehensive, recall-after-reading variants).
- Annotation export conventions: TO BE DEFINED in thread 4 after spike S5.

### B5. To be written by owner

Placeholders for conventions the owner intends to record:

- Collection structure and naming: TODO
- Item-type-specific metadata requirements (what counts as complete for
  a book vs an article): TODO. Seeded by owner (thread 2): every item
  should have at least a date and some form of author, because the
  citation key (B3) is built from author + year + title. Items lacking
  these produce degenerate keys and land in the "_" / "undefined"
  attachment folders (B2). The orphan auditor emits a metadata-gap count
  and a sample of offending keys as an opt-in side report, to collect
  data for this work without acting on it. Deferred to a dedicated future
  thread (MAINTENANCE_PLAN thread map); see the key-stability entailment
  in B3 before any backfill.
- Backup cadence and retention: TODO
- Anything else: TODO
