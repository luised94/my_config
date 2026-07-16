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
