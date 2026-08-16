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
S4 write reliability and reporting surfaces:
BUILT: spikes/spike_s4_write_reliability.js (v1.0.0), PENDING owner run.
RESCOPED after S3 run 2: the original question was only "which logging
surface" (OQ3), but the silent-write-loss finding outranks it, so S4 now
leads with write reliability. It tests, in priority order: whether an
async body runs to completion inside an action; whether an AWAITED save
lands on the high-risk case (an item arriving with an attachment, still
being written); whether read-back verification plus retry recovers a lost
write; and only then ProgressWindow behaviour (OQ3).
It deliberately avoids top-level await -- under a non-async host that is
a PARSE error, which would erase the spike's own evidence -- and puts all
async work in an async IIFE, with a two-line throwaway action in the
header for testing top-level await separately.
DECISION RULE the run produces: landedFirstTry only -> the rules engine
can simply await. Any landedAfterRetry -> read-back verification and
retry are MANDATORY. Any lostDespiteRetry -> writes at fire time are
unsafe and the engine must defer writes out of the handler entirely.
Original notes below.

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

### S3 RESULTS, run 2 (2026-08-06, Zotero 9.0.6, 7 fires, probe active)

Two sessions (a restart between them). Probes attempted on 4 items;
fires 4-6 of session 2 show probeAttempted false because the per-scope
cap of 3 was reached -- confirming scope persistence a second time.

- Q2 ANSWERED: A SAVE INSIDE THE HANDLER DOES NOT RE-TRIGGER THE ACTION.
  4 probes (tag added + saveTx), 0 re-fires across all 7 lines, every
  carriesMarkerTag false. Corroborated independently by the pre-existing
  __unopened action, which writes a tag on every created item and has
  never produced a second fire in 24 logged fires across both runs.
  CONSEQUENCE for OQ2: loop safety against SELF re-triggering is not
  required for the Create Item event. A marker tag or debounce set is
  still worth having as defence in depth and for backfill idempotency,
  but it is not load-bearing here. (Unverified for item-MODIFY events,
  which were never wired up; do not extrapolate.)

- CRITICAL, FOUND BY ACCIDENT: AN UNAWAITED WRITE AT FIRE TIME CAN BE
  SILENTLY LOST. The Google Books book (248773) logged
  probeAttempted true and probeError null, yet never received the marker
  tag, while journal items probed seconds later did. The distinguishing
  feature is concurrency: that item had attachmentCount 1 at fire time
  and was still being modified (dateModified 00:57:40, fire 00:57:41).
  The unawaited saveTx raced with the translator/attachment/other-action
  writes and lost. probeError stayed null because the spike's try/catch
  is synchronous and the rejection surfaced after the block returned.
  CONSEQUENCE, and this is the important one for the rules engine:
  normalize-incoming-item.js MUST await its save and MUST verify the
  write landed, rather than assuming a fire-and-forget save succeeded.
  A rule that silently fails to apply is worse than one that throws.
  Items arriving WITH attachments (connector saves, Google Books) are
  the high-risk case because they are still being written at fire time.
  FOLLOW-UP: confirm whether await is permitted in an A&T action body
  (see S4). If it is not, the action needs a different write strategy --
  a queued/deferred save, or a retry with verification.

- Q3 PARTIALLY ANSWERED: bulk adds produce ONE EVENT PER ITEM,
  sequentially, with no coalescing and none missed. Fires 4, 5, 6 share
  dateAdded 00:59:10 and fired at 00:59:11.282, .696, and 00:59:12.113 --
  roughly 415ms apart. Small N only (3); a larger import is still worth
  running to check for throttling or drops at scale.

- Q4 STILL PARTIAL, evidence strengthening: no attachment or note fire
  has appeared in 13 logged fires. Item 248773 HAD an attachment
  (attachmentCount 1) at its own fire time, and no separate fire was
  logged for that attachment. Suggests child attachments do NOT raise
  Create Item. Not yet conclusive -- a deliberate standalone attachment
  add and a child note add would settle it.

- parentItemID now logs as null for top-level items, confirming the
  v1.0.2 normalization fix.

### S3 RESULTS, run 3 (2026-08-06): Q4 settled, Q3 deferred

- Q4 ANSWERED (deliberate negative result): CHILD ATTACHMENTS AND NOTES
  DO NOT RAISE THE CREATE ITEM EVENT. The owner explicitly added a file
  attachment and a child note to an existing item; NO fire was logged for
  either. This upgrades run 2's circumstantial evidence (item 248773 had
  attachmentCount 1 with no corresponding fire) to a tested finding.
  CONSEQUENCE: normalize-incoming-item.js will only ever receive
  top-level items, so rules need no attachment/note filtering. The
  converse also holds and is a REAL LIMIT: any future rule that must act
  on an attachment or note CANNOT use this event and needs a different
  trigger. Do not design attachment-touching automation on Create Item.

- Q3 LARGE-BULK: NOT EXECUTED (deferred by the owner). What is known
  comes only from an incidental 3-item burst in run 2: one event per
  item, sequential, ~415ms apart, none coalesced or missed.
  UNKNOWNS THIS LEAVES OPEN, all of which scale with N:
  * Whether events are DROPPED or THROTTLED at larger N. A rules engine
    that silently skips items in a 200-item import is a correctness bug
    that only appears in production.
  * Whether the ~415ms spacing is a fixed per-item cost or contention.
    At 415ms x N a large import means minutes of action execution, which
    interacts with the awaited-write requirement below: slow, serialized,
    awaited writes over a long burst may degrade the UI.
  * Whether the persisted action scope accumulates state unboundedly
    across a large burst (an in-memory debounce set would grow with N).
  * Whether the silent-write-loss failure (run 2) becomes MORE likely
    under burst contention, since more writers compete per item.
  MITIGATION UNTIL RUN: treat large-import behavior as unverified. Do
  not enable a writing action on a bulk import path before testing it
  with a recorded N. A read-only logging pass over one real import is
  enough to close this.

### S4 RESULTS, run 1 (2026-08-06, 4 fires) -- PARTIAL, controls only

- T1 ANSWERED: AN ASYNC BODY RUNS TO COMPLETION INSIDE AN A&T ACTION AND
  await RESOLVES. asyncBodyCompleted and awaitResolved were true on all 4
  fires, and the async work (save, delay, read-back verification, log
  write) all completed. CONSEQUENCE: normalize-incoming-item.js may be
  written as an async IIFE performing awaited saves; it does NOT need a
  deferred-write architecture on account of async support. Top-level
  await remains untested (the two-line throwaway action in the S4 header
  tests it if it ever matters; the async IIFE makes it unnecessary).

- T4 ANSWERED (OQ3): Zotero.ProgressWindow WORKS from inside an action
  (progressWindowOk true on all 4) and the owner found it informative but
  too brief at 1500ms. PROGRESS_WINDOW_MS raised to 4000 in v1.0.1.
  Proposed OQ3 standard, pending the burst test: Zotero.debug always
  (cheap, always available, greppable); an appended JSONL file when a run
  must be analyzed after the fact (use mode 'appendOrCreate'); and
  ProgressWindow only for events the user should NOTICE -- not per-item
  during a bulk import, where N popups would be intolerable.

- T2/T3 NOT ANSWERED. All 4 fires were CONTROLS: attachmentCountAtFire 0
  and msSinceDateModified 5-10s, i.e. quiet, settled, uncontended items.
  The failure this spike exists to reproduce (S3 run 2) occurred on an
  item that arrived WITH an attachment and had been modified ~1s before
  the fire. Four landed_first_try results on uncontended items prove
  awaiting works when nothing competes; they say NOTHING about whether
  awaiting survives contention. DO NOT read this run as clearing the
  write strategy.
  v1.0.1 adds isHighRiskCase per fire and a coverageWarning in the
  analyzer so an all-control run can no longer be misread as a pass.
  TO CLOSE: re-run with items that arrive WITH attachments -- a Google
  Books save (the exact case that failed) or a connector save of a
  PDF-bearing article -- and confirm highRiskFires > 0 in the summary.

### S4 RESULTS, run 2 (2026-08-06, 6 fires) -- T2/T3 SETTLED

Decisive run. 2 of 6 writes were LOST on the first attempt and recovered
by a single retry (writeOutcome landed_after_retry, retryCount 1). No
write was lost permanently.

- T2/T3 ANSWERED: AWAITING ALONE IS NOT SUFFICIENT. An awaited saveTx can
  still be lost. READ-BACK VERIFICATION PLUS RETRY IS MANDATORY for
  normalize-incoming-item.js. One retry (800ms backoff, 400ms settle
  before verification) recovered every loss observed; lostDespiteRetry was
  0, so writes at fire time ARE safe with verification and do NOT need to
  be deferred out of the handler. Combined with S4 run 1 (async bodies run
  to completion, await resolves), the write strategy is now settled:
  async IIFE -> await save -> re-fetch and verify -> retry on failure.

- THE RISK HEURISTIC WAS DISPROVEN, and this is the more useful finding.
  Both lost writes were on items scored isHighRiskCase FALSE (Google Books
  "book" items, 5117ms and 4007ms since dateModified,
  attachmentCountAtFire 0), while BOTH items scored TRUE (790ms, 878ms)
  landed on the first try. Every journalArticle landed first try; both
  failures were Google Books saves.
  Mechanism: the heuristic measured PRE-fire settledness, but the
  contention window opens AFTER the action fires. attachmentCountAtFire 0
  on a Google Books save does not mean uncontended -- it means the
  attachment has not been created YET. A recently-modified item has
  already finished being written; a quiet one may be about to be written.
  CONSEQUENCE: fire-time state CANNOT predict which writes will be lost,
  so verification and retry must be applied UNCONDITIONALLY. Do not build
  a fast path that skips verification for "safe-looking" items. This is
  simpler than selective retry as well as more correct.
  Observed correlate for future investigation only (NOT a gate):
  libraryCatalog "Google Books" / itemType book. Now logged as
  libraryCatalogAtFire.

- OQ3 SETTLED: ProgressWindow at 4000ms was "a tad too long" but clearly
  noticeable; PROGRESS_WINDOW_MS settled at 3000. Standard for the rules
  engine: Zotero.debug always; appended JSONL (mode 'appendOrCreate')
  when a run needs after-the-fact analysis; ProgressWindow only for
  events the user should NOTICE, never per-item during a bulk import.

S4 is COMPLETE. Remaining thread-3 spike gap is the deferred large-bulk
import (see "S3 RESULTS, run 3"), which now carries extra weight: since
retries are mandatory and each adds ~1.2s (800ms backoff + 400ms
verification), a large import could serialize into minutes of action
execution. Measure before enabling a writing action on a bulk path.

### DECISION (owner, 2026-08-06): normalize-incoming-item.js SUBSUMES the
### existing __unopened action

S3 run 1 found that a pre-existing A&T action already adds __unopened to
every created item, so every logged fire arrived already tagged and draft
rule R1 ("if no reading-state tag, add __unopened") would have been a
permanent no-op. OWNER DECISION: normalize-incoming-item.js REPLACES that
action rather than racing it.

Consequences to carry into implementation:
- The old __unopened action must be DISABLED (not merely left enabled) as
  part of deploying normalize-incoming-item.js, or both will write and
  the no-op condition returns. Deployment is therefore a two-step change,
  not a pure addition; note it in the deployment steps.
- R1 becomes live rather than vestigial: the new action is the thing that
  establishes the initial reading state.
- The A&T yml backup must be refreshed after the swap (D6).
- Rollback = re-enable the old action and disable the new one. Keep the
  old action's script body in the repo before deleting it, so rollback
  does not depend on the Zotero profile.
- This does NOT change the S3 finding that actions chain and see each
  other's writes; other actions may still exist. It only removes this
  specific overlap.

---

## IMPLEMENTATION LOG (2026-08-12)

Thread-3 deliverables were built and the one-time passes run against the live
library. Trigger is a MANUAL CONSOLE PASS, not an A&T event action (see the
separate decision note DECISION_NOTE_thread3_manual_console.md). Files:

- one-time-operations/diagnose_thread3_tag_state.js  (read-only, 3 checks)
- one-time-operations/migrate_slash_unread.js        (one-time, ran OK)
- one-time-operations/reconcile_read_status.js       (one-time, ran OK)
- console_js/normalize_items.js                       (recurring, R1+R2, ran OK)

### Verified facts established during implementation

- Zotero.Search 'tag is X' matches by NAME across BOTH manual and auto tag
  types (probed: __unopened returned 58,482 = 21,647 manual + 36,835 auto).
  So the guard's name-match "auto counts" is free -- one condition, no union.
- item.getTags() elements carry {tag, type}; type 0 = manual, 1 = automatic
  (confirmed against Zotero source). No item carried the same reading-state
  name as BOTH types ("both" = 0 across __unopened/__in_progress/__revisit),
  so the 36,835 auto __unopened are auto-ONLY -- deleting them would strip the
  only __unopened and the normalizer would re-add it as manual (re-tag cost,
  not data loss). Deletion hazard, not urgent.
- saveTx() updates the in-memory item object synchronously. Verifying tag
  changes against the same object is free and correct for "did the change take
  in memory". getAsync returns the CACHED object, so a post-save re-fetch does
  DB work only to hand back an already-correct object -- it does NOT test
  persistence. Real persistence checks need a cache-bypassing reload (expensive)
  and are only worth it on a rare failure path.
- /unread population: 86 items, 84 clean + 2 contradictions (kept their real
  tag). Read_Status legacy field: 3,556 items; reconciled 1,190 swaps
  (__unopened -> mapped) + 497 adds; left 46 tag-wins + 319 agree; 1,500
  "To Read"/"Not Reading" are non-engagement no-ops. Mapping table MUST include
  'to read'->__to_read and 'not reading'->__not_reading or they miscount as
  unmapped.

### Run order (LOAD-BEARING)

migrate_slash_unread -> reconcile_read_status -> normalize_items. Reconcile
gives the 497 no-state-but-engaged items a real state, so R1 leaves them alone
instead of stamping __unopened. Running the normalizer first would cement 497
wrong __unopened defaults. Tags-first, normalizer-last.

### OUTSTANDING PERF ISSUE (not yet fixed -- deferred by owner to finish thread)

Two distinct performance problems surfaced, both from per-item DB cost at scale:

1. FIXED (commit "perf: drop per-item re-fetch"): saveVerifyRetry re-fetched
   each item with getAsync on every verify (+ write/collection loops re-loaded
   by id) -> ~4 full itemData loads per item, ~6,700 serial loads, single loads
   up to 198s under contention -> reconcile took 2h42m. Fix: verify in memory,
   reuse scan-loaded objects. getAsync now only on batched scan load, rare
   retry, and resume fallback.

2. STILL OPEN: even after fix 1, normalize_items on 5,178 writes took 43 min
   (~504ms/item). Cause is NOT redundant reads -- it is 5,178 sequential
   saveTx() calls. saveTx = save() wrapped in its OWN transaction, so each call
   opens/commits a transaction AND fires the notifier cascade (UI/sync/FTS) for
   one item. The cost is transaction+notifier overhead x N, serialized.

   FIX DIRECTION (for a future session -- a real write-strategy change across
   all three write-scripts, wants its own adversarial pass, NOT a hot patch):
   wrap the per-item writes in ONE Zotero.DB.executeTransaction, using
   item.save() (joins the outer transaction) instead of item.saveTx() (its own).
   One commit, one notifier batch, instead of N. This is the collect_broken_links
   collection-membership pattern, applied to the tag writes too. Verify the
   whole batch AFTER commit rather than per item -- safe because two live runs
   (~6,865 writes total) produced ZERO verify retries, confirming the S4 lost-
   write mode does not occur on SETTLED items (it was a mid-import contention
   effect, which the manual-pass design avoids by construction). Tradeoff to
   weigh: one big transaction rolls back wholly on failure -- but for idempotent
   additive tag writes, a clean re-run is fine, arguably better than partial
   per-item state. START_INDEX resume still applies for very large batches if
   the single transaction is itself chunked (e.g. 500/transaction).

   The writes ALREADY DONE are correct; this is forward-looking speed only.

### Scope still open at end of session

- R4 (missing author/editor -> __add-metadata): settled, next patch.
- R3 (missing-file -> __add-file): needs per-item-type linkMode classification;
  __print suppression infrastructure (FILE_FLAG_TAG / FILE_NOT_APPLICABLE_TAGS)
  already in place for it to reuse.
- R5 (DOI/date): DROPPED. DOI not required; date affects BBT key -> Thread 5.
- tag_hygiene_report.js (recurring, lean): not yet built.
- MAINTENANCE_PLAN.md D5 / thread-3 map: update to reflect manual-console-pass
  decision and the file list above.
- __print -> __have_in_print rename: optional, out of scope, one CONFIG line if
  done (FILE_NOT_APPLICABLE_TAGS).
