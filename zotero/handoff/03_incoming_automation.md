# Thread 3 Handoff: Incoming-Item Automation

Status: PLANNED (test-first: spikes S3, S4 precede any design freeze)
Reads: MAINTENANCE_PLAN.md (D5, D6, Q1, Q2, Q5, S3, S4),
CONVENTIONS.md (A7, A9, B1)

## Objective

Automatically apply cleanup and normalization to items as they enter
the library (item-added event) so manual per-item fixing disappears,
without measurably affecting Zotero performance. Item-added only for
now; the design should scaffold cleanly for future events.

## Deliverables

1. plugin_actions_and_tag_js/normalize-incoming-item.js -- Actions &
   Tags action, event: item added. Rules-table driven.
2. A shared rules definition (single source) usable by both the event
   action and a console backfill runner.
3. console_js/backfill_normalize_items.js -- runs the same rules over
   the whole library with full scale treatment (CONVENTIONS A5).
4. console_js/tag_hygiene_report.js -- recurring report salvaged from
   determine_readstatus_and_tag_combinations.js: counts per workflow
   tag, items with zero workflow tags, contradictory combinations.
5. Updated "Verified facts" here (S3, S4 results).

## Design constraints (decided)

- Rules are a data table: array of {name, guard, apply}. Evaluated in
  order; each rule independent; no shared mutable state; idempotent;
  cheapest guards first. No OOP, no dispatch indirection.
- Tag names referenced only via a TAGS constant sourced from
  CONVENTIONS.md B1. Taxonomy refinement (Q1) must be resolved before
  the final rule set lands; rule mechanics can be built against the
  draft taxonomy.
- LOG_ONLY mode is the default; applying changes is an explicit flag.
- Loop safety is designed from S3 findings, not assumed. Candidate
  mechanisms: marker tag, in-memory debounce set, event-type filtering.
- Reporting standard per S4 (proposal: Zotero.debug always; append-file
  run records; ProgressWindow for brief user-facing notices, possibly
  both file and popup). Decide and record here.

## Draft initial rule set (subject to Q1)

- R1: if item has no reading-state tag, add __unopened (or __to_read --
  decide with taxonomy).
- R2: if item is from Google Books (url or libraryCatalog), add
  __add-metadata and __add-file. (Salvage of tag-google-books logic.)
- R3: if item has no attachments, add __add-file.
- R4: flag missing DOI/date for relevant item types (report or tag --
  decide; may belong in hygiene report instead).
- R5+: title cleanup, publisher normalization, etc. -- collect real
  examples before writing rules.

## Spikes to run first (interactive; paste results back)

S3 event semantics (instrumented log-only action):
BUILT: spikes/spike_s3_event_semantics.js (v1.0.0), PENDING owner run.
It is an ACTIONS & TAGS ACTION, not a console script -- registration
steps, the two-pass run protocol (Pass A read-only, Pass B re-trigger
probe), and a console ANALYZE snippet are all in the script header.
Appends one JSON line per fire to <data dir>/spike_s3/s3_event_log.jsonl,
because an action fires across many separate invocations and
Zotero.debug alone would lose the record and make burst timing
unmeasurable. Read-only by default; the Q2 probe is opt-in, capped, and
guarded by a marker tag -- which makes the spike its own first test of
loop-safety candidate #1 (marker tag). The log also records a per-scope
sessionID, so "is the action re-evaluated in a fresh scope each fire?"
(which decides whether an in-memory debounce set is even viable as a
loop-safety mechanism) is answered as a side effect.
- When does item-added fire relative to translator metadata population?
  (Log field snapshot at fire time.)
- Does saveTx inside the handler re-trigger the event / an item-modified
  event? Does that re-run the action?
- Bulk import of N items: N events? Burst timing? Any missed events?
- Does the action receive child attachments/notes as separate "items"?
S4 logging surfaces:
- Ergonomics of Zotero.debug vs append-file (IOUtils) vs ProgressWindow
  from inside an A&T action; pick the standard (Q2).

## WSL/Windows transport (requirement + TODO)

The repository lives in WSL; Zotero (Windows) reads scripts from the
Windows filesystem. For now: manually copy the needed .js files to a
designated Windows-side folder; A&T actions are pasted/imported from
there; repository files remain canonical (D6) and the yml backup is
refreshed after changes. Recorded future feature (Q5): a sync step,
a Windows-side clone, or a \\wsl$ experiment. Any "script runner"
action (an A&T action that evals a .js from a fixed folder) depends on
this transport decision -- evaluate in-thread as optional deliverable.

## Open questions (finalize in-thread)

- OQ1: resolution of tag taxonomy (MAINTENANCE_PLAN Q1) -- prerequisite
  for final rules.
- OQ2: loop-safety mechanism (from S3).
- OQ3: logging standard (from S4).
- OQ4: do rules run on imported-in-bulk items identically, or should
  bursts be throttled?
- OQ5: script-runner action: adopt, defer, or reject.
- OQ6: where R4-type completeness checks live: rules vs hygiene report.

## Acceptance criteria

- Event action in LOG_ONLY mode logs correct intended actions for 20+
  real incoming items across at least 3 translators, zero writes.
- With applying enabled: idempotent (re-saving an item produces no
  further changes), no event loops observed, added-item latency impact
  imperceptible.
- Backfill runner passes the 1000/5000/full ramp with UI usable.
- Hygiene report runs full-library report-only and its counts are
  consistent with the backfill runner's view.

## Verified facts (populated by spikes)

(empty -- fill with S3/S4 findings, stamped with Zotero and A&T versions)

VERIFIED 2026-07 (A&T action mechanics, from the first S3 attempt):
- A&T action registration labels are Event "Create Item" and Operation
  "Script" (they appear in the debug log as event 1, operation 4).
- The action DOES fire on item creation and receives a trigger payload
  logged as {"itemID":NNN,"triggerType":1}.
- IOUtils write mode 'append' REFUSES TO CREATE a missing file (per the
  IOUtils WebIDL); use 'appendOrCreate'. This cost the first S3 run: the
  log directory was created, no file appeared, and the error was only
  visible in Zotero.debug. Any future file-appending script in this repo
  must use 'appendOrCreate'.
- Other A&T actions in the profile fire on the same items and modify
  tags (observed: an action adding __unopened plus BBT-sourced subject
  tags on a newly created item). Any S3 re-fire analysis must account
  for OTHER actions' writes as a re-trigger source, not just the probe.
- Zotero returns parentItemID FALSE (not null) for a top-level item.
  Any child-vs-top-level test must check both, or it counts every
  top-level item as a child.

### S3 RESULTS, run 1 (2026-08-05, Zotero 9.0.6, 6 logged fires)

Sample: 6 single-item adds (journalArticle, document, blogPost x2,
conferencePaper, webpage). No bulk import, no attachment/note adds in the
logged window. Fires 1-11 of the same session predate the appendOrCreate
fix and were not logged.

ANSWERED:

- Q1 FIELDS ARE POPULATED AT FIRE TIME (for translator saves). The Nature
  journalArticle fired with 14 creators, DOI, URL, abstract, and
  publicationTitle all present. Timing supports it: dateAdded 03:54:50,
  dateModified 03:54:54, action fired 03:55:02 -- roughly 12s after the
  item appeared and 8s after its last modification. The event is LATE, not
  early. CONSEQUENCE: rules MAY read fields at fire time. This removes the
  need for a deferred/re-check design, which was the main risk to the
  whole rules approach.
  Caveat: the empty cases are NOT a race. The "document" item fired with
  no title/creators/date because it was a genuinely empty manual item; the
  creator-less blogPost is a blog post without a listed author. Both are
  real data states, not timing artifacts. Rules must still tolerate empty
  fields -- just not because of the event timing.

- ACTION SCOPE PERSISTS ACROSS FIRES within a Zotero session: a single
  sessionID spans fireOrdinal 1..17 over several minutes. CONSEQUENCE for
  OQ2: an in-memory debounce set IS viable within a session, and does not
  need to be rebuilt per fire. It is NOT durable across restarts, so it
  cannot be the only guard for anything that must hold long-term -- but
  as loop safety (which only needs to span a single write cascade) it is
  sufficient and is the cheapest option.
  Side effect that bit this run: session.probeCount also persisted, so the
  probe cap consumed during the unlogged fires 1-11 blocked every probe in
  fires 12-17.

- A&T ACTIONS CHAIN, AND LATER ACTIONS SEE EARLIER ONES' WRITES. Every
  logged fire already carried the __unopened tag at fire time, added by a
  pre-existing action. CONSEQUENCE: the normalize action cannot assume it
  is first; R1 ("if no reading-state tag, add __unopened") would be a
  no-op on these items because another action already did it. Rule order
  is a cross-ACTION concern, not just an intra-rule one. Decide whether
  normalize-incoming-item.js SUBSUMES the existing __unopened action
  rather than racing it.

- Q4 (partial): NO attachment or note fires were observed. All 6 fires
  were top-level regular items. Note the Nature article logged
  attachmentCount 0 at fire time even though the connector normally saves
  a PDF -- so the attachment either had not been created yet or does not
  fire "Create Item". NOT CONCLUSIVE; see below.

UNANSWERED, needs a second short run:

- Q2 RE-TRIGGER: unresolved. probeAttempted was false on both
  probeEnabled fires because the persisted probe cap was already spent.
  Re-run after RESTARTING ZOTERO (fresh scope) or with a raised
  PROBE_MAX_ITEMS. NOTE: because other actions already write tags on
  create, a re-fire may be caused by THEIR saves, not the probe -- the
  __unopened writes are themselves a live instance of the
  write-inside-create pattern thread 3 must make safe. That no re-fire
  was observed across 17 fires while another action was writing tags is
  weak early evidence that tag writes do NOT re-trigger Create Item.

- Q3 BULK BURST: not exercised. Needs one N-item import with N recorded.

- Q4 CHILDREN: needs an explicit attachment add and a child note add.

CLEANUP: up to PROBE_MAX_ITEMS (3) items may carry the
__spike-s3-probe tag from the unlogged fires. Search that tag and remove
it; it has no meaning outside the spike.

