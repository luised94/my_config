# Citation-key collision experiment: full plan and slice sequence

Written to be transferable to fresh threads. Self-contained. Read top to bottom.
Every slice is independently startable given this document plus the previous
thread's carry-forward note (fixed CARRY-FORWARD v1 template, defined below).
Note before starting: the reconciliation gates are scripts the HUMAN runs in WSL,
not checks the assistant performs in its sandbox -- a fresh thread cannot see prior
artifacts on its own. See "Who checks what" immediately below.

---

## How to use this document across threads

The experiment runs as a sequence of slices. Slices accumulate state (files,
decisions, discovered surprises), and a fresh thread does not automatically know
what changed. Two mechanisms handle that.

**Who checks what -- read this first.** A fresh thread starts with an empty
container. It CANNOT see the corpus file, the manifest, or any artifact from a
prior slice, because those live on the human's WSL disk, not in the assistant's
sandbox. Therefore the drift-reconciliation gate is *code the human runs in their
own environment*, and its printed output is what gets pasted into the new thread.
The assistant does not "check the file exists"; the assistant emits a small
reconciliation script, the human runs it in WSL, and the human pastes back the
result. Every artifact path in this document is a path in the human's repo, never
in the assistant's sandbox.

**Slice-to-thread mapping is a choice, not a rule.** A thread may cover one slice
or several. The gate/carry-forward discipline applies at *thread boundaries*, not
at every slice boundary. If a thread finishes Slice 0 and has room, it may carry
straight into Slice 1 without a handoff -- the handoff is only needed when work
actually moves to a new thread. Small adjacent slices that share state (0 and 1)
are natural to combine; a large slice (3) may warrant its own thread or a split.

### Mechanism 1 -- Carry-forward note (fixed schema)

The last thing a thread produces before handing off is a carry-forward note in
EXACTLY this template, so the next thread's gate can parse it mechanically. Fill
every field; write `none` where empty. Do not reword the field names.

```
CARRY-FORWARD v1
status: complete | halted
thread-covered-slices: <e.g. 0-1>
next-slice: <slice id, or the slice that must be re-attempted if halted>
snapshot-identity: <zotero.sqlite size in bytes + mtime, or "n/a before slice 1">
artifacts-written:
  - path: <absolute WSL path>
    kind: <corpus | manifest | metric-table | plot | export>
    rows-or-bytes: <row count for data files, byte size otherwise>
    checksum: <sha256 of the file, first 12 hex chars>
values:
  <named number or fact the next gate reconciles against, one per line>
  <e.g. corpus-row-count: 58231>
  <e.g. empty-author-rate: 0.014>
surprises:
  <anything the plan did not predict, one per line, or "none">
assumptions-next-slice-rests-on:
  <one per line>
open-decisions-still-owed:
  <question -> which slice needs it, one per line, or "none">
halt-reason:
  <if status is halted: the exact mismatch that stopped work, else "none">
```

The `checksum` + `rows-or-bytes` pair is what makes a lost or truncated artifact
visible: the next gate recomputes them and compares. A missing file or a changed
checksum halts the gate before any content is trusted.

### Mechanism 2 -- Drift-reconciliation gate (runs first in every thread)

Before any new work, the thread emits a reconciliation script the human runs in
WSL. The script, in order:

1. Confirms every file in the prior note's `artifacts-written` exists at its path.
2. Recomputes each artifact's checksum and row count; compares to the note.
3. Re-reads the `values` block's source-of-truth where cheap (e.g. re-counts corpus
   rows) and compares.
4. Confirms `snapshot-identity` still matches (or records the delta if the library
   was chosen to move).

If all match, work proceeds. On ANY mismatch the thread stops and emits a
carry-forward note with `status: halted` and the exact mismatch in `halt-reason`,
so the human can fix it and the *next* attempt reconciles against a known-bad
state rather than re-discovering the problem. A halt is a normal, expected output,
not a failure of the process -- it is the process working.

The reason for all this: unknowns compound. Each slice exposes fields, edge cases,
and library quirks the previous slice could not see. Treating each thread boundary
as a checkpoint that must be re-validated -- rather than trusting inherited state --
keeps a late surprise from silently corrupting everything downstream.

---

## Open-decisions ledger (what the human still owes, and which slice needs it)

A fresh thread should treat everything else in this document as decided and this
list as the outstanding input. Resolve the item before or at the start of the
slice that needs it; record the answer in the environment manifest or the relevant
carry-forward note so later threads see it as settled.

- Repo working directory path in WSL -> Slice 0.
- Zotero data directory path on Windows (or confirm default) -> Slice 0.
- Copy mechanism: script cold copy via PowerShell-from-WSL, or manual on Windows
  each time -> Slice 0.
- Corpus file format: JSONL (recommended) vs CSV -> Slice 1.
- Snapshot discipline: frozen snapshot (recommended) vs moving library -> Slice 1.
- Acceptable to copy BBT's actual skipword/fold lists verbatim for parity -> Slice 2.
- Query models acceptable, and whether a from-memory model (author-forward vs
  title-forward, per how the human actually recalls items) replaces the neutral
  mixed model -> Slice 3.
- Disproof margin: what reduction in worst-case fzf rank counts as "meaningful"
  for regime routing to beat the best global formula; decide BEFORE looking at the
  result -> Slice 4.
- Willingness to re-key pinned items (stated low-cost; confirm) -> Slice 4.
- Whether, after the descriptive map, to open a separate optimization task with a
  chosen target axis -> Slice 5 (and beyond, out of current scope).

---

## Working-style constraints (carried from the parent thread, apply to every slice)

- Plan first, no code in the first turn of a slice, wait for agreement, run an
  adversarial pass over the agreed plan before implementing.
- Present alternatives ranked and scored with a one-line rationale each, ending in
  a single recommendation. Never an unranked list.
- Flat procedural code. Full descriptive names, no abbreviations, no single-letter
  names including loop variables. ASCII only. Comments state *why*, not *what*. No
  abstraction before a second real call site.
- State what is out of scope and stay in it. Flag boundary items and get a
  decision rather than folding them in.
- Verify by executing and showing output, not by asserting.
- Every Python key-generation strategy carries, beside it, the Better BibTeX (BBT)
  formula string it corresponds to. Python is for measurement; the BBT string is
  what gets deployed. They must be kept in parity (see Slice 2).
- Dependency ceiling: no more than five Python packages outside the standard
  library across the whole experiment. Track usage; flag before crossing.

---

## The experiment in one picture

Pipeline stages, each carrying the open question that governs it:

    Export  ->  Formulas  ->  Collisions  ->  Proxies  ->  Answers
    (corpus)   (gen keys)    (count)         (score)      (plot, survey)

The central hypothesis: the corpus fractures into *regimes* (convention-named
works, reference works, high-volume same-author clusters, ordinary long tail) that
want different things from a key, so a single global formula optimizes a
meaningless average. This hypothesis must be *disproved or confirmed by data*, not
assumed -- see the disproof condition in Slice 4.

The reframe that makes the whole thing cheap: generating a key from an item's
fields is a pure read. Measuring collisions is counting buckets. Nothing is saved.
So write-safety and Zotero's per-save performance problem are both off the
critical path. Only a future opt-in write-back task (deploying a chosen formula)
would need its own safety design; that is out of scope here.

---

## Environment facts (the ground truth every slice assumes)

- Host: Windows with WSL. Zotero runs on the Windows side. Code lives in a repo on
  the WSL side. Python is managed with `uv` in WSL. Any Zotero-console JavaScript
  runs in Zotero on Windows. PowerShell is available on the Windows side.
- Library: single personal library (no group libraries). To be verified, not
  trusted, by counting distinct `libraryID` in Slice 1.
- Library size: ~60,000 items. Large enough that collision pressure is real and
  that no-date / same-author pileups likely dominate the collision count.
- Current key formula (the baseline everything must beat):
  `auth.fold + year + title.lower.skipwords().select(1,1)`
- Retrieval workflow: nvim reads a BibTeX file (first line `@citekey`), selection
  via telescope, which uses fzf-style fuzzy subsequence matching, not prefix
  matching. This makes retrieval cost measurable and is the strongest reason to
  ground the "citability" proxy experimentally.
- Known pain: the `a`/`b`/`c` disambiguation tail is opaque -- when two items get
  tailed keys, they cannot be told apart in telescope at selection time. This is
  the concrete failure the experiment exists to fix.

---

## The two control axes

**Formula axis** -- what gets concatenated. Sampled as dimensions:

- Author component: `auth.fold` (current, first author folded to ASCII);
  `authEtal` (first author + `EtAl` when multiple); `authauth` (first two authors);
  raw last-name (reference only, to measure what folding costs).
- Year component: `year` (current); `year || 'nd'` (explicit no-date marker so
  undated items cluster visibly); `year || firstpage || 'nd'` (borrow a page when
  year absent).
- Title component: `select(1,1)` (current, first content word -- the source of the
  tail pain when two same-author-same-year titles share a first content word);
  `select(1,2)` (first two content words); `select(1,1)+lastword`; `shorttitle`
  (Zotero's short-title field when present).
- Disambiguation tail: positional `a`/`b`/`c` (current, opaque, unreproducible
  across import order); none (force discrimination into the formula); numeric tail
  from a stable field such as DOI/ISBN digits (reproducible, order-independent).

**Context axis** -- semantically meaningful discrimination pulled from fields, so a
disambiguated key *tells you what the item is* instead of appending an opaque
letter. Candidate sources, ranked by discrimination value and semantic payload:

- High value: item type (book/thesis/chapter); publication venue (journal or
  publisher short form); title-keyword flag (handbook / encyclopedia / dictionary /
  proceedings / collected -- the convention-named signals).
- Medium: editor-vs-author (the R4 `itemHasAuthorshipCreator` predicate, which
  detects the reference-work regime); volume/edition; creator count.
- Reproducible but low semantic payload: DOI/ISBN digits; first page; language.

Key insight tying the axes together: the tail pain and the context idea are the
same problem from two sides. The `a`/`b`/`c` tail discriminates *without
informing*. Context discriminates *by informing*. So context is not a fourth thing
bolted on -- it is the *right kind of tail*. The real question the experiment
answers: "when author+year+word collides, what is the cheapest discriminator that
also tells me what the item is?"

---

## The strategies to measure (ranked; strategy 1 is the baseline to beat)

1. **Current + item-type context on collision only.** Base formula; when it
   collides, append item type (Book/Thesis/Chapter) instead of `a`/`b`/`c`.
   Smallest change from status quo, directly fixes the pain, item type always
   present. Front-runner and baseline.
2. **Current + second title word on collision.** Disambiguate with the next
   content word rather than a tag. Keeps keys phrase-readable; wins when colliding
   items have genuinely different titles, loses when titles start identically.
3. **Current + editor/title-flag regime routing.** Normal items use the base
   formula; items failing the R4 authorship predicate OR matching a title keyword
   get keyed on title instead of author. This is the regime hypothesis made
   operational, and the one most likely to be disproven -- which is why it earns a
   slot.
4. **Current + reproducible numeric tail.** Disambiguate with stable DOI/ISBN
   digits rather than positional letters. The only option that kills key
   *instability* (keys never renumber when items are added). Costs readability.
5. **`authEtal` + two title words, no tail.** Push entropy into the formula so
   disambiguation rarely fires. Prevention over cure; longer keys, potentially best
   telescope-prefix behavior.
6. **Stock BBT `auth.lower + year`.** The floor. If the current formula does not
   beat this on collisions, the measurement is broken.

Recommendation carried forward: build around strategy 1 as baseline; measure 2, 3,
5 against it first; treat 4 and 6 as instruments (stability probe, floor) rather
than contenders.

---

## The metrics

- **Raw collision rate** (pre-disambiguation): same key string for two distinct
  items. Tests the *formula's* design.
- **Needed-patching rate** (post-disambiguation): fraction of items that required a
  tail. Tests the *system's* churn.
- **Key length** distribution: a formula can be disqualified on length before
  retrieval cost matters.
- **Shortest-unique-prefix** distribution: cheap deterministic reference metric.
  Assumes typing from the start; penalizes shared prefixes; understates context
  tags. Role: floor.
- **fzf-rank** distribution under a disclosed query model: the metric to trust,
  because it matches how telescope actually retrieves. Rewards distinctive
  word-boundary tokens, so it credits context tags fairly. Must be run under 2-3
  query models (author-forward, title-forward, mixed) and reported as
  ranking-stability across models -- a formula that wins under all is genuinely
  good; one that wins under a single model is winning on the query assumption.
- **Fold-collision count**: how often two distinct names fold to the same ASCII
  string, inflating apparent collisions. Measured, not prevented.
- **Empty-author-component** and **empty-title-component** counts: first-class
  metrics because a spike signals extraction breakage, not formula behavior.

Legibility ("can I tell what I am citing from the key alone") is a real property
that none of the combinatorial metrics capture. It is routed explicitly to the
end-stage self-survey rather than approximated by a weak proxy.

---

## Growth analysis

Do not simulate growth by random subsampling -- it dilutes the dense same-author
clusters that actually drove the collisions, making growth look gentler than
reality. Instead *replay* growth using `dateAdded`: sort items by `dateAdded`, take
the first 10k/20k/40k added, giving the library as it genuinely was at those sizes.

Caveat: `dateAdded` is when the item entered *this database*, not your life. A
library migration or bulk import creates a `dateAdded` cliff that compresses early
history. Detect it by histogramming `dateAdded`; read the growth curve only where
the histogram shows organic accretion. Report the histogram beside the curve.

---

## Out of scope (stated, held across all slices)

- Any write-back of keys (pinning, deploying a chosen formula). Separate later task
  with its own safety design.
- The Zotero per-save performance investigation. Off this experiment's path.
- Choosing a winning formula / building an optimizer before a target axis is
  chosen. First deliverable is descriptive.
- Edition handling (same work, different editions). Decided out for current
  purposes; relevant only to future historical research.
- The qualitative self-survey until the objective metrics are in.

---
---

## Applies to every slice below

- The **drift-reconciliation gate** at the top of each slice is executed as a
  script the human runs in WSL (see "Who checks what"). Its output is pasted into
  the thread. The assistant never assumes it can see prior artifacts in its own
  sandbox.
- The **carry-forward note** each slice emits uses the fixed CARRY-FORWARD v1
  template. Each slice's "must emit" list names the slice-specific content that
  fills the template's `values` / `artifacts-written` / `surprises` /
  `open-decisions-still-owed` fields -- it is not a separate note format.
- Every artifact a slice writes is listed in `artifacts-written` with a checksum
  and row count, so the next gate can prove the file is present and intact before
  trusting its contents.
- A slice that cannot proceed emits the same template with `status: halted` and the
  mismatch in `halt-reason`. Halting is expected behavior, not failure.

---
---

# SLICE 0 -- Environment prologue and prerequisite gate

**Purpose.** Establish and verify a stable environment before any real work.
Nothing in later slices is allowed to run until this passes. This is the
preamble/checklist that catches "it broke because the tool was not installed" and
"it broke because the path was wrong" up front, where they are cheap.

**Drift-reconciliation gate (Slice 0 is the origin, so this is the baseline
capture).** Record the actual observed values so later slices have something to
reconcile against:

- Confirm WSL is reachable and identify the repo working directory path.
- Confirm `uv` is installed and runs; record its version.
- Confirm Python version under `uv`; record it.
- Confirm the Windows-side Zotero data directory path (where `zotero.sqlite` and
  `better-bibtex.sqlite` live). Record it.
- Confirm PowerShell is reachable from WSL (`powershell.exe -c "..."` returns) OR
  confirm the human will run the copy on the Windows side manually. Record which.
- Confirm the stdlib modules needed are present (`sqlite3`, `unicodedata`, `csv`,
  `json`, `collections`, `random`). These ship with Python; the check is that the
  interpreter actually imports them (a broken/minimal build would not).

**Claim.** After Slice 0, there exists a versioned repo directory with a working
`uv`-managed Python environment, a recorded and verified path to the Zotero data
directory, a verified copy mechanism (PowerShell-from-WSL or manual), and a
one-line environment manifest committed so later slices can reconcile against it.

**Assumptions.**
- `uv` is the chosen environment manager and will manage every dependency.
- The five-dependency ceiling applies from here on; Slice 0 installs zero external
  dependencies (only verifies stdlib), leaving the whole budget for later.
- The Zotero data directory is stable (not moved between slices). If it moves, the
  Slice 1 gate catches it.

**Probe / experiment required.**
- `uv --version`; create the project (`uv init` or equivalent) in the repo dir;
  `uv run python -c "import sqlite3, unicodedata, csv, json, collections, random;
  print('stdlib ok')"`.
- From WSL: `powershell.exe -c "Get-Process zotero -ErrorAction SilentlyContinue"`
  to confirm the cross-boundary process query works at all (result may be empty;
  the point is that the call succeeds).
- Locate `zotero.sqlite`: check the default Windows Zotero data dir, confirm the
  file exists and its size is plausible for ~60k items.

**Quantified uncertainty.**
- Whether PowerShell-from-WSL works in this specific setup: unknown until probed.
  Fallback is manual copy on Windows; record which path is taken.
- Whether the Zotero data dir is in the default location: unknown; if relocated,
  the human supplies the path.
- `zotero.sqlite` size: recorded as a sanity anchor for Slice 1's cold-copy check.

**Failure modes.**
- `uv` absent or wrong version -> stop, install, re-run.
- Cross-boundary process query fails -> fall back to manual-copy discipline, record
  it, and Slice 1's copy guard adapts.
- Zotero data dir not found -> ask the human, do not guess.
- Stdlib import fails (unusual minimal build) -> stop; the whole approach assumes
  stdlib sqlite3.

**Data / logic / code to implement.**
- Project scaffold under `uv` in the repo working dir (pyproject, lockfile).
- An environment manifest file (plain text or JSON) recording: repo path, uv
  version, python version, Zotero data dir path, zotero.sqlite size and mtime,
  copy mechanism chosen (powershell-from-wsl vs manual). Committed to the repo.
- A tiny verification script that imports the stdlib modules and prints ok. No
  external dependencies.

**Questions to address (need human input).**
- Repo working directory path in WSL?
- Zotero data directory path on Windows (or confirm default)?
- Copy mechanism preference: script the cold copy via PowerShell-from-WSL, or run
  it manually on Windows each time?

**Carry-forward note this slice must emit.** (Fill the CARRY-FORWARD v1 template
from the top of this document. The items below are its `values`, `artifacts`, and
`surprises` content, not a separate freeform note. The manifest file itself is an
`artifacts-written` entry with a checksum.)
- The environment manifest values (so Slice 1 can reconcile).
- Which copy mechanism was chosen.
- Any surprise (uv quirk, relocated data dir, PowerShell-from-WSL unavailable).

---
---

# SLICE 1 -- Cold-copy guard and creator-correct field extraction

**Drift-reconciliation gate (run first, before anything else).**
- Load the Slice 0 environment manifest. Reconcile: does the Zotero data dir still
  exist at the recorded path? Is `zotero.sqlite` size/mtime changed (library grew
  between slices -- expected, but note the delta)? Is `uv`/Python still the recorded
  version?
- If the copy mechanism recorded by Slice 0 was "manual", confirm the human has
  produced a cold copy; if "powershell-from-wsl", confirm the guard still runs.
- Mismatch on any -> stop and hand back. Do not extract against an unexpected DB.

**Purpose.** Produce one versioned flat corpus file containing exactly the fields
the six strategies consume, extracted from a *cold copy* of `zotero.sqlite`, with
creator order and role provably correct, filtered to real bibliographic items in
the single library. Everything downstream reads this file and never touches Zotero
again.

**Claim.** A stdlib `sqlite3` read of a cold-copied `zotero.sqlite`, joining
items / itemCreators / creators / itemData / itemDataValues / fields with correct
`orderIndex` and `creatorType` handling, yields a corpus whose author/year/title/
type/dateAdded fields match the Zotero UI for a hand-checked sample, and whose row
count after filtering is a defensible "real bibliographic items" number.

**Assumptions.**
- Zotero fully closed, no lingering process, before the copy. Guarded, not trusted.
- One library; verified by counting distinct `libraryID`.
- `dateAdded` approximates organic growth except across import bursts; validated by
  histogram, not assumed.
- Current Zotero schema (single `zotero.sqlite`, itemData/itemDataValues). Old
  Zotero differs; detectable on first query failure.
- This slice extracts *raw* fields only -- no transforms yet. It extracts the raw
  `date` string (free-text: `2003-05`, `c1998`, `n.d.`) and defers year-parsing to
  Slice 2, so the real messiness is visible before a parser is committed.

**Probe / experiment required (the gate before bulk work).**
Pull 15-20 items by hand, deliberately including: a multi-author paper, an edited
volume, an institutional/single-field author, a no-date item, a non-ASCII author,
and a book with a distinctive title. Record what Zotero's UI shows. Confirm the
extraction reproduces first-author, full ordered author list, role, year, title,
and item type for all of them. No downstream work until all sampled items match.

**Quantified uncertainty.**
- Row count after filtering: expected ~60k; report the funnel (raw rows -> after
  excluding attachments/notes/annotations -> after excluding trashed -> after
  dedup) with a number at each stage.
- Empty-author-component rate: expected small; a spike (>a few percent) means
  extraction breakage on single-field creators. Single most important sanity
  number in the slice.
- Empty-title-component rate: same treatment (some manuscripts legitimately have no
  title).
- `dateAdded` import-burst fraction: quantified by histogram.
- Non-ASCII author fraction: sets expectations for Slice 2 fold-collision risk.

**Failure modes.**
- `orderIndex` dropped -> first author randomized, keys plausible-but-wrong. Caught
  by the multi-author probe item.
- `creatorType` conflated -> editors counted as authors, regime detector misfires
  later. Caught by the edited-volume probe item.
- Single-field (institutional) creators mishandled -> empty author component.
  Caught by the institutional-author probe item and the empty-rate metric.
- Trashed/duplicate items not filtered -> inflated corpus and collisions. Caught by
  the funnel.
- Copy made while Zotero alive -> inconsistent read, possibly undetectable. Caught
  by the process guard refusing to run.
- Reading across the `/mnt/c` mount -> boundary/locking quirks. Mitigated by
  copying the DB into the WSL filesystem before reading, not reading in place.

**Data / logic / code to implement.**
- Copy step with a hard process guard: enumerate Windows processes; refuse if any
  Zotero process exists; else copy `zotero.sqlite` (and note `better-bibtex.sqlite`
  for Slice 2 parity work) into the WSL-side working dir. The guard clause is the
  substance.
- One extraction query (or a small set) joining item/creator/data tables,
  selecting: itemID, itemType, ordered creators with role, raw date string,
  title, shorttitle if present, and context-candidate fields (venue/publisher,
  editor flags via creatorType, DOI/ISBN, dateAdded). Read-only.
- Filter logic: real bibliographic item types only (exclude attachment, note,
  annotation); exclude trashed (`deletedItems`); collapse duplicates if any. Each
  filter reported as a funnel stage.
- Writer to a flat, diffable, versioned file. JSONL preferred over CSV because the
  ordered author list is variable-length and titles contain commas/newlines that
  break naive CSV; a flattened CSV convenience view optional.
- Hand-check harness: print the extracted record for the probe itemIDs for eyeball
  comparison against Zotero.
- Dependencies: `sqlite3`, `json` only. Zero external. (Budget untouched.)

**Questions to address (need human input or a probe answer).**
- Confirm single library (verified by distinct `libraryID`, but confirm the prior).
- JSONL for the corpus (recommended) vs CSV?
- Fixed snapshot (copy once, freeze for the whole experiment -- recommended for
  reproducibility) vs re-copy each extraction (tracks a moving library)?

**Things the spec might be forgetting (surfaced).**
- Titles with newlines/tabs/commas -> argues for JSONL or strict quoting.
- Zotero "year" is free-text inside a `date` field -> extract raw, defer parsing.
- Items legitimately without a title -> empty-title metric, first-class.
- `dateAdded` timezone (UTC vs local) -> irrelevant at coarse 10k buckets; noted so
  it does not resurface.

**Adversarial findings carried into this slice (from the design pass).**
- Creator extraction is where silent lies live; the hand-check gate is mandatory.
- The empty-author rate is the breakage tripwire; treat it as a headline number.

**Carry-forward note this slice must emit.**
- Corpus file path, format, exact row count, and the full funnel numbers.
- Empty-author and empty-title rates (breakage tripwires for Slice 2 to watch).
- Non-ASCII author fraction (sets Slice 2 fold expectations).
- `dateAdded` histogram summary and where the organic-growth region begins.
- The raw-date-string messiness sample (what year-parsing in Slice 2 must handle).
- Snapshot decision (frozen vs moving) and the snapshot's identity (size/mtime).
- Any schema surprise (unexpected item types, extra libraries, missing fields).

---
---

# SLICE 2 -- Formula engine, BBT parity, and year/fold transforms

**Drift-reconciliation gate (run first).**
- Load the Slice 1 carry-forward. Reconcile: does the corpus file exist at the
  recorded path with the recorded row count? Do the empty-author/empty-title rates
  match (a change means the corpus was regenerated differently)?
- Confirm the raw-date messiness sample is available -- the year parser is built
  against it. If Slice 1 did not capture it, go back.
- Mismatch -> stop and hand back.

**Purpose.** Turn raw corpus fields into keys for all six strategies, with the
year-parser and ASCII-fold implemented, and each Python strategy paired with its
deployable BBT formula string and verified for parity on the baseline.

**Claim.** For each strategy, a flat-procedural Python key generator produces keys
from the corpus, and for the *current* formula those keys match the keys already in
a BBT BibTeX export of the same items -- proving the Python reproduction is faithful
and the paired BBT strings are trustworthy for the variants.

**Assumptions.**
- BBT's skipwords list and fold table are the authorities; copy them verbatim
  rather than inventing, or the Python and BBT diverge on edge cases and parity
  fails for reasons unrelated to formula design.
- The raw `date` field parses to a usable year for most items; the no-date fallback
  is load-bearing and is itself a measured behavior.
- ASCII folding via `unicodedata` NFKD + combining-mark strip matches what
  `auth.fold` / BBT do closely enough that fold-collisions are rare; measured, not
  assumed.

**Probe / experiment required.**
- Retain one BBT BibTeX export of the corpus items as ground truth. Ignore its
  content except the `@citekey` line.
- Generate the *current* formula's keys in Python; compare to the export's keys.
  Report match rate. Investigate every mismatch -- each is either a fold/skipword
  discrepancy (fixable by copying BBT's list) or a genuine parity bug.

**Quantified uncertainty.**
- Baseline parity match rate: target near-total; the residual reveals fold/skipword
  edge cases.
- Year-parse success rate: fraction of items yielding a clean year vs falling to
  the no-date path. A high no-date fraction means the no-date fallback dominates
  collisions and must be designed carefully.
- Fold-collision rate: how often distinct names collapse to one ASCII string.

**Failure modes.**
- Positional-tail order mismatch: BBT assigns `a`/`b`/`c` in import/alphabetical
  order; Python assigns in its own order. So Python `Smith2020a` and BBT
  `Smith2020a` may point at different items. Consequence: needed-patching *rate* is
  trustworthy, but *which specific item got which tail* is NOT reproducible from
  Python alone. This is a second, independent reason to prefer semantic/numeric
  discrimination (strategies 1, 3, 4) over positional tails -- record it as a
  finding, and validate specific tailed keys only against real BBT output.
- Skipword/fold list drift -> spurious parity mismatches. Fixed by copying BBT's
  lists.
- Year parser overfit to the probe sample -> silent misparse on unseen formats.
  Mitigated by parsing raw and reporting the no-date rate as a headline.

**Data / logic / code to implement.**
- Year parser over the raw `date` strings (handles `YYYY`, `YYYY-MM`, `cYYYY`,
  `n.d.`, ranges, seasons).
- ASCII fold helper (`unicodedata`), or confirm stdlib-only suffices (likely zero
  external deps here).
- One key generator per strategy, flat procedural, each with its paired BBT formula
  string documented immediately beside it.
- Parity harness comparing current-formula Python keys to the BBT export keys.
- Dependencies: likely still stdlib-only (`unicodedata`). If a fuzzy library is
  pulled forward for Slice 3, note it against the five-dep budget now.

**Questions to address.**
- Confirm the BBT export can be produced for the corpus items (one export, retained
  as ground truth).
- Where BBT built-ins cannot be trivially mirrored, confirm copying BBT's actual
  skipword/fold lists is acceptable.

**Carry-forward note this slice must emit.**
- Baseline parity match rate and the nature of any residual mismatches.
- Year-parse success rate and no-date fraction.
- Fold-collision rate.
- The finding that positional tails are non-reproducible from Python (constrains
  what Slice 3 can claim about specific tailed keys).
- Any dependency added and remaining budget.

---
---

# SLICE 3 -- Collision and retrieval-cost metrics

**Drift-reconciliation gate (run first).**
- Load Slice 2 carry-forward. Reconcile: do all six key generators exist and run?
  Is baseline parity confirmed? Is the no-date fraction as recorded (it drives
  collision counts)?
- Confirm the fzf-scoring dependency choice from Slice 2 (if any) is installed and
  within the five-dep budget.
- Mismatch -> stop and hand back.

**Purpose.** Compute the full metric set for every strategy over the corpus.

**Claim.** For each strategy the pipeline reports raw collision rate,
needed-patching rate, key-length distribution, shortest-unique-prefix
distribution, and fzf-rank distribution under multiple query models -- enough to
rank strategies on retrieval cost, not just aesthetics.

**Assumptions.**
- The fzf metric depends on a *query model*, and the query model is a choice that
  can bias the ranking exactly as a proxy can. No neutral model exists; only a
  disclosed one. Therefore run 2-3 models and report ranking stability across them.
- Shortest-unique-prefix is the cheap deterministic floor; when it and fzf-rank
  disagree, the disagreement is itself a finding (the formula's discriminating
  information is not at the front of the key).

**Probe / experiment required.**
- Implement the fzf scoring to match telescope-fzf-native (public algorithm; a
  compiled option such as rapidfuzz or a pure-Python port). Validate the scorer on
  a handful of known query/key pairs before trusting the distribution.
- Run each metric per strategy; run fzf-rank under author-forward, title-forward,
  and mixed-distinctive-token query models.

**Quantified uncertainty.**
- Collision rates per strategy, reported *stratified by author-cluster density*
  (collisions among authors with more than N works), not just globally -- because
  collisions concentrate in dense clusters and a single global number misleads.
  This stratification also directly tests the high-volume-same-author regime.
- fzf-rank distributions per strategy per query model; the headline is the
  worst-case rank (how far you'd scroll for the hardest item) and cross-model
  stability.

**Failure modes.**
- Query model rigs the ranking (favors formulas front-loading its tokens).
  Mitigated by the multi-model robustness report.
- Random-subsampling growth curve understates cluster-driven collision growth.
  Mitigated by using the `dateAdded` replay from Slice 4, not random subsampling.
- fzf scorer subtly wrong -> whole trusted metric is off. Mitigated by validating
  the scorer on known pairs first.

**Data / logic / code to implement.**
- Collision bucketing (group items by generated key; count buckets with >1 item),
  pre- and post-disambiguation.
- Shortest-unique-prefix computation (for each key, shortest leading substring
  unique across the corpus).
- fzf scorer + query-model generators (author-forward, title-forward, mixed).
- Cluster-density stratification of collision rates.
- Dependencies: at most one fuzzy-match library; keep total <= 5.

**Questions to address.**
- Confirm the query models are acceptable, and whether a from-memory model (how you
  actually recall items: author-forward vs title-forward) should replace the
  neutral mixed model later.

**Carry-forward note this slice must emit.**
- Per-strategy metric tables, including cluster-stratified collision rates.
- fzf-rank cross-model stability per strategy (which strategies win robustly).
- Any prefix-vs-fzf disagreements (findings about where key entropy sits).
- Dependency count and remaining budget.

---
---

# SLICE 4 -- Regime classification, disproof test, and growth replay

**Drift-reconciliation gate (run first).**
- Load Slice 3 carry-forward. Reconcile: are the per-strategy metric tables present
  and is the cluster stratification available (the regime test reuses it)?
- Confirm the `dateAdded` histogram / organic-growth region from Slice 1 is
  available (growth replay depends on it).
- Mismatch -> stop and hand back.

**Purpose.** Decide, from data, whether regimes are real for this library, and
measure how collisions grow as the library grew.

**Claim.** Classifying items by cheap signals (item type, editor-vs-author, title
keyword, creator count) and comparing per-regime retrieval cost either shows that
regime routing (strategy 3) meaningfully beats the best global strategy, or it does
not -- and the disproof condition makes that a clean, falsifiable result.

**Assumptions.**
- Item type alone is a poor proxy for "convention-named" (a book can be a novel or
  the Bible), so regime classification uses the combination of cheap signals, not
  item type alone.
- The pinned set (the Bible etc.) is evidence of a regime whose boundary can be
  *detected*, not a hardcoded exception list. Pinned items are treated as data:
  measure what key strategy 3 would assign them and whether it is acceptable.

**Probe / experiment required.**
- Classify every item by the cheap regime signals.
- **Disproof condition (operational):** per-regime routing (strategy 3) does NOT
  reduce worst-case fzf rank versus the best global formula (strategy 1 or 2) by a
  meaningful margin. If strategy 3 does not beat the best global option on the
  trusted metric, the regime hypothesis is disconfirmed *for this library* -- a
  clean result, not a failure, and the experiment ships one global formula.
- **Growth replay:** using `dateAdded`, compute collision rate at the library's
  actual historical sizes (first 10k/20k/40k added), reading the curve only in the
  organic-growth region identified in Slice 1.

**Quantified uncertainty.**
- Whether the regimes separate: measured as the margin by which strategy 3 beats
  (or fails to beat) the best global strategy on worst-case fzf rank.
- Collision growth trajectory: linear / sub-linear / super-linear as the library
  grew, which predicts safety at future sizes.

**Failure modes.**
- Confirmation bias drawing regime boundaries around whatever clusters appear.
  Prevented by fixing the disproof condition *before* looking.
- `dateAdded` import cliff corrupting the early growth curve. Mitigated by reading
  only the organic region.
- Strategy 3's regime router assigns garbage to pinned items -> pin by hand (a
  handful); if it naturally produces `Bible`/`KJV` via title routing, the regime
  hypothesis pays for itself.

**Data / logic / code to implement.**
- Regime classifier over cheap signals.
- Disproof comparison (strategy 3 worst-case fzf rank vs best global).
- `dateAdded`-ordered growth replay reusing Slice 3's collision bucketing.
- Dependencies: no new ones expected.

**Questions to address.**
- What margin counts as "meaningful" for the disproof (decide before looking)?
- For pinned items, confirm the willingness to re-key (stated: low cost at this
  stage, only the Bible had a real reason, even that adjustable).

**Carry-forward note this slice must emit.**
- Regime separation result (regimes real, or disproved) with the margin.
- Growth trajectory and its safety implication at projected future sizes.
- What strategy 3 assigns to the current pinned items.

---
---

# SLICE 5 -- Descriptive synthesis, plots, and the self-survey

**Drift-reconciliation gate (run first).**
- Load Slice 4 carry-forward. Reconcile: are the regime result and growth
  trajectory present? Are the Slice 3 metric tables intact?
- Mismatch -> stop and hand back.

**Purpose.** Produce the first (descriptive) deliverable: a collision-vs-proxy map
per regime across strategies, plus the qualitative self-survey that captures the
one property the objective metrics cannot (legibility at selection time).

**Claim.** The synthesis presents, per regime (or globally if regimes were
disproved), how each strategy trades collisions against retrieval cost, length, and
stability -- descriptive, not an optimizer, because no target axis has been chosen.

**Assumptions.**
- The deliverable is descriptive. No winning formula is selected and no optimizer is
  built here; those await a chosen target axis and are out of scope.
- The self-survey measures *your own* judgments (this is a personal knowledge base),
  not other people's.

**Probe / experiment required.**
- Plot collision-vs-fzf-cost per strategy, faceted by regime (or global).
- Growth curve with the `dateAdded` histogram beside it.
- Self-survey: present N colliding-item key sets per strategy and rate whether the
  correct item is identifiable from the key alone -- the legibility measure routed
  here from the metric design.

**Quantified uncertainty.**
- Legibility scores per strategy (the only subjective metric; the survey is
  load-bearing exactly here).

**Failure modes.**
- Over-plotting / over-claiming from a single library. Every rate reported "at
  current library size"; growth curve carries the trajectory.
- Survey questions leading the witness. Keep them neutral (identify the item, do
  not rate the formula).

**Data / logic / code to implement.**
- Plotting (at most one tabular/plotting dependency; keep total <= 5).
- Survey harness presenting key sets and recording judgments.

**Questions to address.**
- Whether, after the descriptive map, a target axis should be chosen (which would
  open a *separate*, later optimization task -- out of scope here).

**Carry-forward note this slice must emit.**
- The descriptive map and its headline findings.
- Legibility survey results.
- Whether a target axis emerged worth a follow-on optimization task (with its own
  scope and, if it involves write-back, its own safety design).

---
---

## Dependency budget tracker (update as slices consume it)

Ceiling: 5 external Python packages. Expected consumption:
- Slices 0-1: 0 (stdlib only: sqlite3, json, unicodedata, csv, collections, random).
- Slice 2: 0-1 (unicodedata is stdlib; a fold/normalize helper only if needed).
- Slice 3: 1 (fuzzy-match library for the fzf scorer, e.g. rapidfuzz).
- Slice 5: 1 (tabular/plotting).
Projected total: 1-3, comfortably under 5. Flag immediately if a slice threatens
the ceiling.

## Snapshot discipline

If Slice 1 chose a frozen snapshot, every later slice reconciles against that same
snapshot identity (size/mtime). If it chose a moving library, every slice records
the current identity so a mid-experiment library change is visible, not silent.
