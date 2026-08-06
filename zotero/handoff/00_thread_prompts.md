# Start-of-thread prompts

Paste-ready openers for each remaining thread. They live here because the
repository, not a chat transcript, is the record -- a prompt that exists
only in a closed conversation is lost, which nearly happened to the
thread-4 opener in August 2026.

Every prompt follows the same rhythm, which has worked well:
sparse clone -> read the spine and the thread handoff -> state
understanding, strategy, and open questions WITHOUT writing code -> wait
for confirmation -> then build in reviewable batches.

Common preamble, used by all of them:

    Sparse clone:
        git clone --filter=blob:none --sparse <repo-url>
        cd my_config
        git sparse-checkout set zotero
    luised94/my_config from GitHub.

    Read MAINTENANCE_PLAN.md (especially section 6 Thread map, the
    revised ordering, and section 6b Cross-cutting verified facts) and
    CONVENTIONS.md. Then read the handoff document for this thread. For
    an example of how this repo works end to end -- spike protocol,
    detect-then-write separation, delivery as a patch series -- skim
    handoff/02_orphan_pipeline.md; thread 2 is complete and is the
    worked example. Do not re-derive anything already recorded.

---

## Thread 6: trailing-dot path sanitization (RANKED FIRST)

    [common preamble]

    This is THREAD 6: path-component sanitization. Read the section
    "FINDING: Windows strips trailing dots" in
    handoff/02_orphan_pipeline.md first -- that is the whole problem
    statement.

    Summary of what is already known: Windows silently strips trailing
    dots and spaces from path components, so an author folder like
    "Hughes Jr." can never exist on disk; the file lands elsewhere or is
    lost during rename. 42 of 73 broken links share this signature, and
    the owner confirms files "don't get saved sometimes and some are
    lost during renaming". This is ACTIVE loss, which is why it is
    ranked first.

    The REPAIR half already exists: repair_attachment_paths.js,
    TRAILING_DOT strategy. Do not rebuild it. This thread is about
    PREVENTION: stopping the naming pipeline from generating unreachable
    paths.

    Before proposing anything, READ the naming pipeline -- Attanger's
    configuration, any naming-related action scripts in
    plugin_actions_and_tag_js/, and the BBT key format -- and tell me
    where the path is actually constructed and where the sanitization
    belongs. Prior comments and docs are evidence, not ground truth.
    Then give me: your understanding of the task, a ranked set of
    options with a recommendation, what is out of scope, and open
    questions. No code that turn.

    Note this borders the BibTeX citation-key format work the owner has
    flagged (key format redesign, mass refresh). Flag anything sitting
    on that boundary and get a decision rather than folding it in.

## Thread 3: incoming-item automation (BLOCKED ON Q1)

    [common preamble]

    This is THREAD 3: incoming-item automation. Its spikes are DONE --
    S3 and S4 were built, run, and written up; do not re-run or re-derive
    them. Read the "Verified facts" and the S3/S4 RESULTS sections in
    handoff/03_incoming_automation.md carefully, because they constrain
    the design more than the original plan text does.

    The mechanics are settled: fields ARE populated at fire time; the
    action is not re-triggered by its own saves; only top-level items
    fire; async IIFEs with await work; and -- most importantly -- an
    awaited save CAN STILL BE LOST, so read-back verification plus retry
    is mandatory and must be unconditional.

    Also settled: normalize-incoming-item.js SUBSUMES the existing
    __unopened action, which makes deployment a two-step change (disable
    the old action) rather than a pure addition.

    BEFORE IMPLEMENTATION, two things are still open and I need to
    settle them with you:
    - Q1, the workflow tag taxonomy (CONVENTIONS.md Part B, still marked
      DRAFT): the reading-state vocabulary, whether the states are
      strictly mutually exclusive, and the transition rules. This is my
      decision, not yours -- ask me the questions that force it.
    - The deferred large-bulk-import measurement. Retries cost ~1.2s
      each and are mandatory, so a large import may serialize into
      minutes of action execution. Propose the smallest read-only pass
      that closes this.

    Start with understanding, strategy, and those questions. No code
    that turn.

## Thread 4: annotation export (S5 BUILT, PENDING RUN)

    [common preamble]

    This is THREAD 4: annotation export, and it is EXPLORATORY. The
    handoff forbids drafting implementation before spike S5 populates
    "Verified facts". S5 IS ALREADY BUILT --
    spikes/spike_s5_annotation_introspection.js -- so this thread opens
    by having me RUN it, not by writing it.

    Tell me what you understand the purpose to be, then walk me through
    running S5 (console script, "Run as async function" checked, strictly
    read-only, but note it reads file CONTENT and will hydrate the small
    sample of files it inspects -- the one place in this repo that does).

    When I paste the result, the most consequential thing to check is
    whether pdfContainsAttachmentKey / pdfContainsParentKey are false
    across every sample. If they are, exported PDFs do NOT carry the
    Zotero item id and the motivating premise of this thread needs
    revisiting BEFORE any design work. Say so plainly if that happens.

    Also push me on OQ1 early: rank the primary purpose -- backup of
    annotations, external reading of annotated PDFs, or feeding the notes
    workflow. The handoff says that ranking drives the shape, and I would
    rather settle it than have you build to a guess.

## Thread 5: metadata completeness and citation-key integrity (DEFERRED)

    [common preamble]

    This is THREAD 5: metadata completeness and citation-key integrity.
    It has never been scoped; scoping it is the job, not implementing.

    Context worth knowing before you start: the thread-2 audit collected
    seed data (944 parents missing creator, 1,481 missing date, 942
    missing both, plus the "_" and "undefined" degenerate-key attachment
    folders). BUT the owner has since done a large MANUAL metadata
    cleanup, so RE-MEASURE before scoping -- those numbers are stale and
    treating them as current would be exactly the mistake this repo's
    conventions exist to prevent.

    The load-bearing constraint is in the plan: backfilling author/year
    CHANGES the BBT citation key, and changing keys BREAKS EXISTING
    CITATIONS in documents already written. Key stability is
    first-class here. This also collides with the owner's intent to
    redesign the key format and mass-refresh keys, so sequencing between
    the two is a real decision to surface early, not a detail.

    Start by proposing how to re-measure cheaply, then a ranked scope
    with a recommendation. No code that turn.

---

## Dependency structure (2026-08-06)

Distinguish TRUE DEPENDENCIES (B needs A's output; constrains order)
from RESOURCE CONFLICTS (both mutate the same thing; either order works,
but not simultaneously).

True dependencies:
  Q1 -> thread 3 implementation
  bulk-import measurement -> thread 3 implementation
  S5 run -> thread 4 design
  thread 6 investigation -> thread 6 implementation
  BBT dedup -> key-format work
  re-measure -> thread 5 scoping

Resource conflicts (schedule apart, any order):
  thread 6 and key-format work both change generated FILENAMES, so both
    create fresh orphans; run one orphan sweep after the last of them
  thread 5 metadata backfill changes citation keys; collides with
    key-format work
  only ONE experimental A&T action enabled at a time, or logs interleave
  any two WRITING operations against the live library

Levels:
  L0 (startable now, in parallel): consolidation thread; S5 run;
     Q1 decision; bulk-import spike; BBT dedup; thread 6 investigation
  L1: thread 3 implementation; thread 6 implementation; key-format
     redesign; thread 4 design
  L2: thread 5 scoping; post-rename orphan sweep

Notes: Q1 is a DECISION, not a work thread -- settling it is cheap and
unblocks the largest deliverable. The consolidation thread is the most
parallel item on the list: it touches only the two broken-link scripts,
needs no Zotero run to develop, and blocks nothing. Spike RUNS share one
Zotero instance even when the threads are independent, so serialize the
runs, not the threads.

## Consolidation thread: merge collect_broken_links + repair_attachment_paths

    [common preamble]

    This is the CONSOLIDATION thread. Read the two decision blocks at the
    end of handoff/02_orphan_pipeline.md -- "DECISION: collection-first,
    repair de-emphasized" and "CONSTRAINT: this CANNOT run at item
    creation". The design is already agreed; do not relitigate it.

    Task: merge console_js/collect_broken_links.js and
    console_js/repair_attachment_paths.js into one script with ONE scan
    and ONE classification pass. They currently duplicate the
    reconstruct-and-classify logic, which wastes a ~7-8s scan but more
    importantly risks DRIFT -- two copies will diverge and then disagree
    about what is broken.

    Agreed design: MODE_REPORT (always on), MODE_COLLECT (normal mode),
    MODE_REPAIR (default OFF, off the recommended path). Separate gates
    because they have different reversibility profiles. Anything
    MODE_REPAIR changes must ALSO be collected into a "repaired, verify"
    collection so no data change escapes review.

    The real deliverable is REPORTING THAT STATES THE REQUIRED ACTION per
    item rather than leaving me to infer it -- the four buckets and their
    fixes are listed in the handoff.

    Two open questions I need you to put to me before building: whether
    repair-then-collect in one run is desirable (one run would then do
    both a write and a survey), and whether the old scripts become thin
    deprecated wrappers or are deleted.

    Start with understanding, strategy, and those questions. No code that
    turn.

## Bulk-import measurement (small, read-only)

    [common preamble]

    Small scoped task, not a full thread. Read the "S3 RESULTS, run 3"
    section of handoff/03_incoming_automation.md, specifically the
    deferred large-bulk unknowns.

    Everything else in thread 3's spike work is done. The one gap is
    behaviour at large N: whether events are DROPPED or THROTTLED,
    whether the ~415ms per-item spacing holds at scale, whether the
    persisted action scope accumulates state unboundedly, and whether
    the silent-write-loss failure gets MORE likely under burst
    contention. This matters more than it did because verification and
    retry are now mandatory and cost ~1.2s per recovered item, so a
    large import could serialize into minutes.

    Propose the SMALLEST read-only pass that closes this -- likely a
    stripped-down variant of spike_s4_write_reliability.js with writes
    disabled. I will run one real import and record N. Do not enable a
    writing action on a bulk path before this is measured.

## BBT script dedup (small)

    [common preamble]

    Small scoped task. The file inventory in MAINTENANCE_PLAN.md flags
    two near-identical scripts: bbt_citation_key_refresh.js (346 lines,
    substantive work 2026-01-23 -- GC batch alignment, START_INDEX and
    MAX_TO_PROCESS interaction) and bbt_refresh_citation_keys.js (169
    lines, added 2026-08-03, presumed newer and canonical).

    Read BOTH. Tell me whether the newer one carries the older one's
    batching, GC, and START_INDEX resume behaviour, or whether that work
    was lost in the rewrite. Then recommend: delete the old one, port
    missing behaviour forward first, or keep both with distinct roles.

    Do this BEFORE any citation-key format work, so that work does not
    get built against the wrong script.

## Citation-key format redesign (owner-initiated, not yet scoped)

    [common preamble]

    I want to redesign the BBT citation key format (more unique and
    descriptive -- I have hit collisions and ambiguity) and mass-refresh
    keys. This has never been scoped. Read MAINTENANCE_PLAN.md on thread
    5 for the load-bearing constraint.

    Before proposing a format, surface the consequences I need to weigh:
    changing keys BREAKS EXISTING CITATIONS in documents already written;
    a mass refresh RENAMES ATTACHMENT FILES, which strands the old names
    as fresh orphans (the thread-2 sweep cleared 7,412 of exactly that
    kind of sediment); and this collides with both thread 5's metadata
    backfill and thread 6's path sanitization, all three of which touch
    generated names.

    Prerequisite: the BBT script dedup task must be done first.
    Sequencing question I need answered: do the naming/key changes
    together, then ONE orphan sweep afterwards.

    Start with understanding, the consequence list, and a ranked set of
    options with a recommendation. No code that turn.
