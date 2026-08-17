// =============================================================================
// NORMALIZE ITEMS  (recurring manual console pass)
// =============================================================================
// Version: 1.0.0  (rules R1 + R2)
// Date:    2026-08-12
// Thread:  3 (incoming-item automation).
// Status:  the normalizer. Owner runs it manually over a chosen input set on a
//          cadence (decision note 2026-08-11: manual console pass, NOT an
//          Actions & Tags event action -- running after imports are settled
//          removes the write-contention window that made an event action pay
//          for mandatory retries and bulk serialization). This one script
//          subsumes the former "Create Item / Add Tags / __unopened" action
//          AND the former separate backfill runner: same rules, scoped by
//          CONFIG.
//
// Deployment (owner): DISABLE the old "Create Item / Add Tags / __unopened"
//          action (note its settings in the repo first for trivial rollback),
//          refresh actions-zotero.yml (D6), then run this on a cadence. The old
//          action is disabled, not rewritten. Nothing establishes __unopened at
//          fire time anymore -- this pass does, after items settle. Accepted
//          tradeoff (owner, 2026-08-11): a forgotten run leaves new items
//          without __unopened until the next run; benign and self-healing,
//          strictly better than the event path's silently-lost writes.
//
// ORDER: run migrate_slash_unread.js and reconcile_read_status.js BEFORE the
//          first normalizer pass (one-time-operations/). Load-bearing: the
//          reconcile pass adds __in_progress/__read to items that had no state
//          tag but were engaged per legacy Read_Status; if the normalizer ran
//          first it would stamp __unopened on those. After reconcile they carry
//          a real state, so R1's guard correctly leaves them alone. Tags-first,
//          normalizer-last.
//
// RULES (data-driven, D5). Each rule is { name, description, guard, apply }.
// guard(item) -> bool decides whether the rule acts; apply(item) mutates the
// item's TAGS in memory (never saves -- the driver saves once per item after
// all matching rules have applied). Rules are TAG-ONLY: they may READ any field
// to decide, but never EDIT field content (decision note: tag-only write
// authority; field-content mutation ships later as a separate spiked tool).
// Cheapest guard first.
//   R1  initial state: if the item has no opened-state tag
//       ({__unopened,__in_progress,__read}, name-match so auto counts), add
//       __unopened. Subsumes the old action. __not_reading and __to_read do
//       NOT count as opened-state (Q1), so an item with only those still gets
//       __unopened.
//   R2  Google Books: if url matches a google-books pattern or libraryCatalog
//       says "google books", add __add-metadata and __add-file (they enter the
//       metadata-completion and file-attachment workflows). Generalized from
//       tag-google-books.js into a small pattern table so new sites are data,
//       not code.
//
// NOT in this version (deliberate scope, owner 2026-08-12):
//   R3 (missing file -> __add-file): "has a file" is item-type-dependent -- a
//      PDF is expected for journal articles and books, but a URL snapshot is
//      sufficient for blogs/webpages. That needs per-type attachment-kind
//      (linkMode) classification (cf. thread 2) and gets its own patch + pass.
//   R4 (missing author/editor -> __add-metadata): settled, ships as the next
//      patch; held out only to keep R1's subsumption unblocked and commits
//      one-concern.
//   R5 (DOI/date): dropped. DOI not required at this stage; date completeness
//      affects the BBT citation key and belongs to Thread 5, not a reading
//      tagger.
//
// Write strategy: per item, all matching rules mutate tags in memory, then ONE
//      saveTx, then verify IN MEMORY (saveTx updates the in-memory object
//      synchronously -- repo idiom mark-as-read / tag-google-books). Do NOT
//      re-fetch per item to verify: getAsync triggers a full itemData load, and
//      per-item re-fetch is what made an earlier pass take 2h42m on ~1,687
//      items (see reconcile_read_status.js perf note). Rare verify miss ->
//      getAsync re-fetch + re-apply once (S4 defence-in-depth; expected zero on
//      settled items).
//
// WRITE PERF (FIXED 2026-08-13): the write loop no longer does one saveTx per
//      changed item. It commits in chunks of CONFIG.WRITE_CHUNK_SIZE items inside
//      ONE Zotero.DB.executeTransaction via item.save() (joins the txn), then
//      verifies each chunk against DISK by a single SQL read. The P3 probe found
//      per-item saveTx cost ~1747ms median, of which ~1728ms (99%) was the
//      transaction boundary paid once PER ITEM; amortizing the boundary across a
//      chunk drops it to ~41ms/item (~42x). The boundary, not the notifier
//      cascade, was the cost, so no notifier batching was needed. A 5,178-item
//      backfill projects from ~151 min to ~4 min. Rollback on a thrown commit was
//      verified (rollback probe: a cached-object read had earlier masqueraded as a
//      failed rollback, so verification now reads disk truth via SQL, not
//      item.hasTag). A verify miss is REPORTED for an idempotent re-run, not
//      retried in-transaction. See zotero/probe/ for the probes and their results.
//
// Idempotent (A7): every guard is "does this need doing", so a re-run over the
//      same items is a no-op. Safe to run on a cadence and safe to re-run after
//      a partial pass.
//
// Usage:  Tools > Developer > Run JavaScript. CHECK "Run as async function".
//      DRY_RUN default: prints the plan (per-rule counts + bounded samples),
//      writes nothing. Set CONFIG.DRY_RUN = false to apply. Choose the input
//      set with CONFIG.INPUT_MODE.
// =============================================================================

// 1. CONFIGURATION
var CONFIG = {
    DRY_RUN: true,

    // Input set. 'library' = all top-level regular items (the backfill / first
    // run) -- the only mode implemented in v1, built on the verified
    // itemType-isNot enumeration (bbt_export.js idiom). 'collection' and
    // 'added_since' are declared but NOT yet implemented: their Zotero search
    // condition names ('collectionID', 'dateAdded', operator 'isAfter') are not
    // confirmed against a live library, and shipping unverified condition
    // strings means a code path that throws the first time it is used. They
    // land as a follow-up patch, verified against a real run, when cadence
    // scoping is actually needed. For now the cadence story is: run 'library';
    // it is idempotent, so re-running only touches items that still need it.
    INPUT_MODE: 'library',
    COLLECTION_NAME: '',              // reserved for the future 'collection' mode (not implemented in v1)
    ADDED_SINCE: '',                  // reserved for the future 'added_since' mode (not implemented in v1)

    UNOPENED_TAG: '__unopened',
    OPENED_STATE_TAGS: ['__unopened', '__in_progress', '__read'],  // R1 guard set (name-match)

    // The tag that flags "this item needs a file attached", and the tags that
    // mean "a file is NOT APPLICABLE to this item" and therefore suppress the
    // file flag. __print means the owner holds a physical copy: there is no
    // file to attach, so flagging __add-file would create a worklist entry that
    // can never be actioned (owner decision 2026-08-12). __print suppresses
    // ONLY the file flag, not __add-metadata -- a physical book can still have
    // incomplete metadata. If __print is later renamed (e.g. __have_in_print),
    // change it here only. This suppression is used by R2 and will be used by
    // the future R3 (missing-file), so it lives in CONFIG, not inside a rule.
    FILE_FLAG_TAG: '__add-file',
    FILE_NOT_APPLICABLE_TAGS: ['__print'],

    // R4: an item is missing authorship if it has NO creator whose type is in
    // AUTHORSHIP_ROLES. Owner decision 2026-08-12: author and/or editor. Types
    // are compared by NAME (getCreatorJSON returns creatorType as a string like
    // 'author'/'editor'), so no id resolution is needed. Items with only other
    // roles (translator, contributor, etc.) and no author/editor are flagged
    // __add-metadata -- the same tag R2 uses, since both mean "metadata needs
    // completion".
    METADATA_FLAG_TAG: '__add-metadata',
    AUTHORSHIP_ROLES: ['author', 'editor'],

    // R2 site table. Each entry: match if url includes any urlIncludes OR
    // libraryCatalog (lowercased) includes any catalogIncludes; then add tags.
    // New sites are new rows here, not new code. The file flag among addTags is
    // suppressed per-item when a FILE_NOT_APPLICABLE_TAGS tag is present.
    SITE_RULES: [
        {
            name: 'google_books',
            urlIncludes: ['www.google.com/books', 'books.google.com'],
            catalogIncludes: ['google books'],
            addTags: ['__add-metadata', '__add-file']
        }
    ],

    // A5 scale treatment.
    LOAD_BATCH_SIZE: 500,
    YIELD_MS: 10,
    CHECKPOINT_EVERY: 500,
    // M1 (2026-08-13): the write loop commits in chunks of this many items inside
    // ONE executeTransaction instead of one saveTx per item (see WRITE PERF in the
    // header). 500 matches LOAD_BATCH_SIZE/CHECKPOINT_EVERY. Smaller bounds the
    // rollback blast radius and keeps START_INDEX resume on a chunk boundary;
    // larger is marginally faster. Rollback on a thrown commit is confirmed, so a
    // failed chunk leaves nothing partial.
    WRITE_CHUNK_SIZE: 500,
    START_INDEX: 0,                   // resume a partial apply
    MAX_WRITES: 0,                    // 0 = no cap; set 1000/5000 to ramp
    DRY_RUN_SAMPLE_MAX: 40,

    MIN_ZOTERO_VERSION: '7.0',
    MAX_ZOTERO_VERSION: '9.0.6',
    BYPASS_VERSION_CHECK: false
};

// 2. STATE
var timing = { scriptStart: Date.now(), assertions: 0, scanMs: 0, writeMs: 0 };
var result = {
    dryRun: CONFIG.DRY_RUN,
    inputMode: CONFIG.INPUT_MODE,
    candidatesScanned: 0,
    ruleMatchCounts: {},              // ruleName -> count of items the rule would act on
    itemsWithAnyChange: 0,
    planSample: [],                   // { itemID, rules: [names] } bounded
    applied: {
        itemsChanged: 0,
        tagsAddedByRule: {},          // ruleName -> tags added count (committed chunks only)
        // M1: verification is post-commit and per-chunk (disk-truth SQL). There is no
        // in-transaction retry -- you cannot re-save mid-transaction, and misses were
        // expected-zero over ~6,865 settled-item writes. A miss is REPORTED here for an
        // idempotent re-run to reconcile, not retried. { itemID, missing: [tagNames] }.
        verifyMisses: [],
        aborted: false,
        abortReason: null
    }
};

// 3. HELPERS
function assert(condition, message) {
    timing.assertions = timing.assertions + 1;
    if (!condition) { throw new Error(`normalize_items pre-flight failed: ${message}`); }
}

async function loadItemsInBatchesFromIDs(itemIDs) {
    var loaded = [];
    for (var start = 0; start < itemIDs.length; start = start + CONFIG.LOAD_BATCH_SIZE) {
        var batch = await Zotero.Items.getAsync(itemIDs.slice(start, start + CONFIG.LOAD_BATCH_SIZE));
        for (var bi = 0; bi < batch.length; bi = bi + 1) { loaded.push(batch[bi]); }
        await new Promise(function (r) { setTimeout(r, CONFIG.YIELD_MS); });
    }
    return loaded;
}

// (M1, 2026-08-13) The former per-item saveVerifyRetry is gone. It did one saveTx
// per item -- the transaction boundary the P3 probe found was 99% of the ~1747ms
// per-item cost -- and verified IN MEMORY, which the rollback probe proved
// unreliable (a stale cached object disagreed with committed disk state). Writes
// now happen in chunked transactions with a post-commit disk-truth SQL verify;
// see the write loop in MAIN. No in-transaction retry exists: you cannot re-save
// mid-transaction, and the idempotent re-run is the reconciliation path for the
// (expected-zero) miss.

// --- Rule table (D5). guard reads only; apply mutates tags in memory only. ---
// Each apply returns the array of tag names it added (for accounting), or [].
//
// R2 helper: given an item, compute the set of tags the site rules WOULD add,
// after removing any that are already present and any file flag suppressed by a
// file-not-applicable tag (__print). Pure read. Used by both R2's guard ("would
// this add anything") and R2's apply ("add exactly these"), so the two can
// never diverge -- the earlier version duplicated the site-match logic in guard
// and apply, which is exactly where a suppression added to one but not the
// other would silently break. Extracted per the >=3-call-site rule.
function computeSiteTagsToAdd(item) {
    var url = (item.getField('url') || '').toLowerCase();
    var catalog = (item.getField('libraryCatalog') || '').toLowerCase();

    var fileNotApplicable = false;
    for (var ni = 0; ni < CONFIG.FILE_NOT_APPLICABLE_TAGS.length; ni = ni + 1) {
        if (item.hasTag(CONFIG.FILE_NOT_APPLICABLE_TAGS[ni])) { fileNotApplicable = true; break; }
    }

    var toAdd = [];
    for (var si = 0; si < CONFIG.SITE_RULES.length; si = si + 1) {
        var siteRule = CONFIG.SITE_RULES[si];
        var matches = false;
        for (var ui = 0; ui < siteRule.urlIncludes.length; ui = ui + 1) {
            if (url.includes(siteRule.urlIncludes[ui].toLowerCase())) { matches = true; }
        }
        for (var cti = 0; cti < siteRule.catalogIncludes.length; cti = cti + 1) {
            if (catalog.includes(siteRule.catalogIncludes[cti].toLowerCase())) { matches = true; }
        }
        if (!matches) { continue; }
        for (var ti = 0; ti < siteRule.addTags.length; ti = ti + 1) {
            var tag = siteRule.addTags[ti];
            // Suppress the file flag on file-not-applicable items (__print).
            if (tag === CONFIG.FILE_FLAG_TAG && fileNotApplicable) { continue; }
            if (item.hasTag(tag)) { continue; }               // already present
            if (toAdd.indexOf(tag) === -1) { toAdd.push(tag); }
        }
    }
    return toAdd;
}

// R4 helper: does the item have at least one creator whose type is an authorship
// role (author/editor)? Pure read. Named because it is used by R4's guard and is a
// clear predicate; kept out of the guard body so the "missing authorship" logic
// reads as one line there.
//
// The type match is ROBUST to how getCreatorJSON reports creatorType on a given
// build (this bit us: items with a visible author -- Abbott, Abrash -- were flagged
// __add-metadata because the raw creatorType did not === 'author'). The old code
// compared creator.creatorType directly against ['author','editor'], which fails if
// the build returns a capitalized/localized string ('Author') or a numeric
// creatorTypeID instead of the lowercase name. Resolution order:
//   1. If creatorType is a usable string, lowercase it and compare.
//   2. Else resolve creatorTypeID -> name via Zotero.CreatorTypes.getName() (guarded;
//      if that API is absent or throws, skip this creator rather than crash).
// An undeterminable type falls through to "not authorship" -- we never treat "could
// not determine" as a match, so genuinely authorless items are still flagged.
// AUTHORSHIP_ROLES stays ['author','editor']: the bug was matching, not membership.
function itemHasAuthorshipCreator(item) {
    // Lowercase the configured roles once for case-insensitive comparison.
    var roles = [];
    for (var ri = 0; ri < CONFIG.AUTHORSHIP_ROLES.length; ri = ri + 1) {
        roles.push(String(CONFIG.AUTHORSHIP_ROLES[ri]).toLowerCase());
    }
    var count = item.numCreators();
    for (var i = 0; i < count; i = i + 1) {
        var creator = item.getCreatorJSON(i);
        if (!creator) { continue; }
        // 1. creatorType as a string (the common case).
        var typeName = null;
        if (typeof creator.creatorType === 'string' && creator.creatorType.length > 0) {
            typeName = creator.creatorType.toLowerCase();
        } else if (creator.creatorTypeID !== undefined && creator.creatorTypeID !== null) {
            // 2. Resolve numeric id -> name, guarded: the CreatorTypes API is an
            //    assumption; if it is missing or throws, skip rather than crash.
            try {
                if (typeof Zotero.CreatorTypes !== 'undefined' && typeof Zotero.CreatorTypes.getName === 'function') {
                    var resolved = Zotero.CreatorTypes.getName(creator.creatorTypeID);
                    if (typeof resolved === 'string' && resolved.length > 0) { typeName = resolved.toLowerCase(); }
                }
            } catch (e) {
                // leave typeName null -> this creator does not count; do not throw.
            }
        }
        if (typeName !== null && roles.indexOf(typeName) !== -1) { return true; }
    }
    return false;
}

var RULES = [
    {
        name: 'R1_initial_state',
        description: 'add __unopened if no opened-state tag present',
        guard: function (item) {
            for (var i = 0; i < CONFIG.OPENED_STATE_TAGS.length; i = i + 1) {
                if (item.hasTag(CONFIG.OPENED_STATE_TAGS[i])) { return false; }
            }
            return true;
        },
        apply: function (item) {
            item.addTag(CONFIG.UNOPENED_TAG);
            return [CONFIG.UNOPENED_TAG];
        }
    },
    {
        name: 'R2_site_flags',
        description: 'flag items from known sites (Google Books) for metadata/file workflows; __print suppresses the file flag',
        guard: function (item) {
            // Match only if there is at least one tag actually left to add after
            // suppression and already-present filtering. This means a __print
            // Google Books item that already has __add-metadata does NOT match
            // (nothing to do), rather than matching and adding nothing.
            return computeSiteTagsToAdd(item).length > 0;
        },
        apply: function (item) {
            var toAdd = computeSiteTagsToAdd(item);
            for (var ti = 0; ti < toAdd.length; ti = ti + 1) { item.addTag(toAdd[ti]); }
            return toAdd;
        }
    },
    {
        name: 'R4_missing_authorship',
        description: 'flag __add-metadata if the item has no author/editor creator',
        guard: function (item) {
            // Already flagged -> nothing to do (idempotent).
            if (item.hasTag(CONFIG.METADATA_FLAG_TAG)) { return false; }
            return !itemHasAuthorshipCreator(item);
        },
        apply: function (item) {
            item.addTag(CONFIG.METADATA_FLAG_TAG);
            return [CONFIG.METADATA_FLAG_TAG];
        }
    }
];

// 4. PRE-FLIGHT
assert(typeof Zotero !== 'undefined', 'Zotero global unavailable');
assert(typeof Zotero.Search === 'function', 'Zotero.Search unavailable');
assert(typeof Zotero.Items.getAsync === 'function', 'Zotero.Items.getAsync unavailable');
var userLibraryID = Zotero.Libraries.userLibraryID;
assert(typeof userLibraryID === 'number', 'userLibraryID unavailable');
assert(['library', 'collection', 'added_since'].indexOf(CONFIG.INPUT_MODE) !== -1, `unknown INPUT_MODE ${CONFIG.INPUT_MODE}`);
assert(CONFIG.INPUT_MODE === 'library',
    `INPUT_MODE '${CONFIG.INPUT_MODE}' is declared but not implemented in v1 (search condition names unverified). Use 'library'; it is idempotent, so re-running only touches items still needing normalization. Cadence scoping ships as a follow-up patch.`);

if (!CONFIG.BYPASS_VERSION_CHECK) {
    var zoteroVersion = Zotero.version;
    assert(Services.vc.compare(zoteroVersion, CONFIG.MIN_ZOTERO_VERSION) >= 0,
        `Zotero ${zoteroVersion} below tested floor ${CONFIG.MIN_ZOTERO_VERSION}`);
    if (Services.vc.compare(zoteroVersion, CONFIG.MAX_ZOTERO_VERSION) > 0) {
        Zotero.debug(`normalize_items: Zotero ${zoteroVersion} above tested ceiling ${CONFIG.MAX_ZOTERO_VERSION}; confirm and bump.`);
    }
}
for (var ri = 0; ri < RULES.length; ri = ri + 1) {
    result.ruleMatchCounts[RULES[ri].name] = 0;
    result.applied.tagsAddedByRule[RULES[ri].name] = 0;
}

// 5. MAIN
try {
    var scanStart = Date.now();

    // Build the input-set search. v1 supports 'library' only: all top-level
    // regular items (isNot attachment/note/annotation), matching what the event
    // action would have received (S3 top-level-only finding) so the
    // normalizer's view is consistent with it and with the hygiene report.
    // (collection / added_since modes are blocked in pre-flight until their
    // condition names are verified; no unverified condition code lives here.)
    var search = new Zotero.Search();
    search.libraryID = userLibraryID;
    search.addCondition('itemType', 'isNot', 'attachment');
    search.addCondition('itemType', 'isNot', 'note');
    search.addCondition('itemType', 'isNot', 'annotation');

    var itemIDs = await search.search();
    var candidates = await loadItemsInBatchesFromIDs(itemIDs);
    result.candidatesScanned = candidates.length;

    // Index by id so the write path reuses scan-loaded objects (no re-fetch).
    var itemsById = new Map();
    for (var mi = 0; mi < candidates.length; mi = mi + 1) { itemsById.set(candidates[mi].id, candidates[mi]); }

    // Plan: evaluate guards (read-only) to see which rules would act. Does not
    // mutate anything -- apply happens only in the write phase.
    var workList = [];   // { itemID, ruleNames: [...] }
    for (var pi = 0; pi < candidates.length; pi = pi + 1) {
        var item = candidates[pi];
        var matched = [];
        for (var rj = 0; rj < RULES.length; rj = rj + 1) {
            if (RULES[rj].guard(item)) {
                matched.push(RULES[rj].name);
                result.ruleMatchCounts[RULES[rj].name] = result.ruleMatchCounts[RULES[rj].name] + 1;
            }
        }
        if (matched.length > 0) {
            workList.push({ itemID: item.id, ruleNames: matched });
            result.itemsWithAnyChange = result.itemsWithAnyChange + 1;
            if (result.planSample.length < CONFIG.DRY_RUN_SAMPLE_MAX) {
                result.planSample.push({ itemID: item.id, rules: matched });
            }
        }
    }
    timing.scanMs = Date.now() - scanStart;

    // Plan output (A4).
    var plan = [];
    plan.push('=== normalize_items PLAN ===');
    plan.push(`input mode: ${CONFIG.INPUT_MODE}; candidates scanned: ${result.candidatesScanned}`);
    for (var rk = 0; rk < RULES.length; rk = rk + 1) {
        plan.push(`  ${RULES[rk].name} would act on: ${result.ruleMatchCounts[RULES[rk].name]} item(s) -- ${RULES[rk].description}`);
    }
    plan.push(`items with at least one change: ${result.itemsWithAnyChange}`);
    plan.push('writes: TAGS only. No field content, no collection, no removal.');
    for (var ps = 0; ps < result.planSample.length; ps = ps + 1) {
        plan.push(`  [${result.planSample[ps].itemID}] ${result.planSample[ps].rules.join('+')}`);
    }
    for (var pl = 0; pl < plan.length; pl = pl + 1) { Zotero.debug(plan[pl]); }

    if (CONFIG.DRY_RUN) {
        Zotero.debug('DRY_RUN: nothing written. Set CONFIG.DRY_RUN = false to apply.');
    } else {
        var writeStart = Date.now();
        var end = workList.length;
        if (CONFIG.MAX_WRITES > 0) { end = Math.min(end, CONFIG.START_INDEX + CONFIG.MAX_WRITES); }

        // Chunked single-transaction writes (M1). Each chunk of up to
        // CONFIG.WRITE_CHUNK_SIZE items is applied in memory, committed in ONE
        // executeTransaction via item.save() (joins the txn), then verified against
        // DISK by a single SQL read per chunk. Continue-and-report on a verify miss:
        // owner decision 2026-08-13, since misses were expected-zero over ~6,865
        // settled-item writes and the pass is idempotent (a re-run reconciles). There
        // is no abort path and no per-item retry.
        for (var chunkStart = CONFIG.START_INDEX; chunkStart < end; chunkStart = chunkStart + CONFIG.WRITE_CHUNK_SIZE) {
            var chunkEnd = Math.min(chunkStart + CONFIG.WRITE_CHUNK_SIZE, end);

            // Per-item expected tags for THIS chunk, captured during apply so the
            // post-commit disk verify knows what to check. Keyed by itemID.
            var expectedByItemID = new Map();
            var chunkItemIDs = [];

            // Per-rule tag counts held CHUNK-LOCAL and folded into the global result
            // only if the chunk commits. A chunk whose commit throws rolls back whole
            // (rollback confirmed), so its counts must not leak into the totals --
            // holding them local keeps tagsAddedByRule honest rather than an upper bound.
            var chunkTagCountByRule = {};
            for (var rk = 0; rk < RULES.length; rk = rk + 1) { chunkTagCountByRule[RULES[rk].name] = 0; }

            // Apply all matched rules for every item in the chunk, in memory, inside
            // one transaction, then commit once. save() joins the open transaction.
            try {
                await Zotero.DB.executeTransaction(async function () {
                    for (var wi = chunkStart; wi < chunkEnd; wi = wi + 1) {
                        var work = workList[wi];
                        var writeItem = itemsById.get(work.itemID);
                        if (!writeItem) { writeItem = await Zotero.Items.getAsync(work.itemID); }

                        // Re-check each rule's guard on the current object, so a re-run
                        // or concurrent change cannot double-apply (idempotent).
                        var expectedPresent = [];
                        for (var rl = 0; rl < RULES.length; rl = rl + 1) {
                            if (work.ruleNames.indexOf(RULES[rl].name) === -1) { continue; }
                            if (!RULES[rl].guard(writeItem)) { continue; }   // already satisfied
                            var addedTags = RULES[rl].apply(writeItem);
                            for (var at = 0; at < addedTags.length; at = at + 1) {
                                if (expectedPresent.indexOf(addedTags[at]) === -1) { expectedPresent.push(addedTags[at]); }
                                chunkTagCountByRule[RULES[rl].name] = chunkTagCountByRule[RULES[rl].name] + 1;
                            }
                        }

                        if (expectedPresent.length > 0) {
                            expectedByItemID.set(work.itemID, expectedPresent);
                            chunkItemIDs.push(work.itemID);
                            await writeItem.save();   // joins the outer txn; boundary amortized
                        }
                    }
                });
            } catch (commitError) {
                // Rollback works (rollback probe Cases A/B, verified against disk): a
                // thrown commit rolled the whole chunk back, nothing partial persisted.
                // Chunk-local counts are discarded (never folded in). Report and let the
                // idempotent re-run redo the chunk. Not an abort -- a recoverable failure.
                Zotero.debug(`normalize_items: chunk [${chunkStart},${chunkEnd}) commit failed and rolled back: ${commitError.message}. Re-run (idempotent) to redo this chunk. Resume hint START_INDEX=${chunkStart}.`);
                continue;
            }

            // Chunk committed: fold its per-rule counts into the global totals now.
            for (var fk = 0; fk < RULES.length; fk = fk + 1) {
                result.applied.tagsAddedByRule[RULES[fk].name] =
                    result.applied.tagsAddedByRule[RULES[fk].name] + chunkTagCountByRule[RULES[fk].name];
            }

            if (chunkItemIDs.length === 0) { continue; }   // nothing was written this chunk

            // ---- Disk-truth verify: ONE SQL read for the whole chunk. ----
            // Read every tag currently on disk for the chunk's items, then reconcile in
            // memory against expectedByItemID. One round-trip per chunk, not per item
            // (killing per-item round-trips is the whole point of the fix). In-memory
            // hasTag is NOT used: the rollback probe showed a cached object can disagree
            // with disk. Bound params: one placeholder per itemID (ids are integers we
            // control, but binding is the house convention and handles types correctly).
            var placeholders = [];
            for (var ph = 0; ph < chunkItemIDs.length; ph = ph + 1) { placeholders.push('?'); }
            var verifySql = 'SELECT itemTags.itemID AS itemID, tags.name AS name '
                + 'FROM itemTags JOIN tags ON tags.tagID = itemTags.tagID '
                + `WHERE itemTags.itemID IN (${placeholders.join(',')})`;
            var diskRows = await Zotero.DB.queryAsync(verifySql, chunkItemIDs);

            // Build itemID -> Set(tag names on disk).
            var diskTagsByItemID = new Map();
            for (var dr = 0; dr < diskRows.length; dr = dr + 1) {
                var row = diskRows[dr];
                if (!diskTagsByItemID.has(row.itemID)) { diskTagsByItemID.set(row.itemID, new Set()); }
                diskTagsByItemID.get(row.itemID).add(row.name);
            }

            for (var ci = 0; ci < chunkItemIDs.length; ci = ci + 1) {
                var verifyItemID = chunkItemIDs[ci];
                var expected = expectedByItemID.get(verifyItemID);
                var onDisk = diskTagsByItemID.get(verifyItemID) || new Set();
                var missingTags = [];
                for (var ei = 0; ei < expected.length; ei = ei + 1) {
                    if (!onDisk.has(expected[ei])) { missingTags.push(expected[ei]); }
                }
                if (missingTags.length > 0) {
                    result.applied.verifyMisses.push({ itemID: verifyItemID, missing: missingTags });
                } else {
                    result.applied.itemsChanged = result.applied.itemsChanged + 1;
                }
            }

            Zotero.debug(`normalize_items: chunk [${chunkStart},${chunkEnd}) committed; changed so far=${result.applied.itemsChanged}, verifyMisses so far=${result.applied.verifyMisses.length}`);
            await new Promise(function (r) { setTimeout(r, CONFIG.YIELD_MS); });
        }

        timing.writeMs = Date.now() - writeStart;
        Zotero.debug(`normalize_items: writes done in ${timing.writeMs} ms. itemsChanged=${result.applied.itemsChanged}`);
        if (result.applied.verifyMisses.length > 0) {
            Zotero.debug(`WARNING: ${result.applied.verifyMisses.length} item(s) had a verify miss on disk: ${JSON.stringify(result.applied.verifyMisses.slice(0, 50))}. Re-run (idempotent) to reconcile.`);
        }
    }
} catch (error) {
    Zotero.debug(`normalize_items FAILED: ${error.message}\n${error.stack}`);
    throw error;
}

// 6. SUMMARY
timing.totalMs = Date.now() - timing.scriptStart;
result.timing = timing;
Zotero.debug(`normalize_items done in ${timing.totalMs} ms (dryRun=${CONFIG.DRY_RUN}, mode=${CONFIG.INPUT_MODE}, scanMs=${timing.scanMs}, writeMs=${timing.writeMs})`);
return result;
