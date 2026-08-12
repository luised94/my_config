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

    // R2 site table. Each entry: match if url includes any urlIncludes OR
    // libraryCatalog (lowercased) includes any catalogIncludes; then add tags.
    // New sites are new rows here, not new code.
    SITE_RULES: [
        {
            name: 'google_books',
            urlIncludes: ['www.google.com/books', 'books.google.com'],
            catalogIncludes: ['google books'],
            addTags: ['__add-metadata', '__add-file']
        }
    ],

    // Write-verify-retry (S4 defence-in-depth; common path verifies in memory).
    RETRY_BACKOFF_MS: 800,
    RETRY_SETTLE_MS: 400,

    // A5 scale treatment.
    LOAD_BATCH_SIZE: 500,
    YIELD_MS: 10,
    CHECKPOINT_EVERY: 500,
    MAX_CONSECUTIVE_FAILURES: 20,
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
        tagsAddedByRule: {},          // ruleName -> tags added count
        verifyRetries: 0,
        verifyFailuresAfterRetry: [],
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

// Save pending tag changes, verify IN MEMORY (free -- saveTx updates the
// in-memory object synchronously), retry once via getAsync on the rare miss.
// expectedPresent is the set of tag names that must be present after the write.
// The normalizer only ADDS tags, so there is no expectedAbsent.
async function saveVerifyRetry(item, expectedPresent) {
    await item.saveTx();
    var verifyInMemory = function (target) {
        for (var pi = 0; pi < expectedPresent.length; pi = pi + 1) {
            if (!target.hasTag(expectedPresent[pi])) { return false; }
        }
        return true;
    };
    if (verifyInMemory(item)) { return true; }
    result.applied.verifyRetries = result.applied.verifyRetries + 1;
    await new Promise(function (r) { setTimeout(r, CONFIG.RETRY_BACKOFF_MS); });
    var retryItem = await Zotero.Items.getAsync(item.id);
    for (var rp = 0; rp < expectedPresent.length; rp = rp + 1) {
        if (!retryItem.hasTag(expectedPresent[rp])) { retryItem.addTag(expectedPresent[rp]); }
    }
    await retryItem.saveTx();
    await new Promise(function (r) { setTimeout(r, CONFIG.RETRY_SETTLE_MS); });
    return verifyInMemory(retryItem);
}

// --- Rule table (D5). guard reads only; apply mutates tags in memory only. ---
// Each apply returns the array of tag names it added (for accounting), or [].
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
        description: 'flag items from known sites (Google Books) for metadata/file workflows',
        guard: function (item) {
            var url = (item.getField('url') || '').toLowerCase();
            var catalog = (item.getField('libraryCatalog') || '').toLowerCase();
            for (var si = 0; si < CONFIG.SITE_RULES.length; si = si + 1) {
                var siteRule = CONFIG.SITE_RULES[si];
                for (var ui = 0; ui < siteRule.urlIncludes.length; ui = ui + 1) {
                    if (url.includes(siteRule.urlIncludes[ui].toLowerCase())) { return true; }
                }
                for (var cti = 0; cti < siteRule.catalogIncludes.length; cti = cti + 1) {
                    if (catalog.includes(siteRule.catalogIncludes[cti].toLowerCase())) { return true; }
                }
            }
            return false;
        },
        apply: function (item) {
            var url = (item.getField('url') || '').toLowerCase();
            var catalog = (item.getField('libraryCatalog') || '').toLowerCase();
            var added = [];
            for (var si = 0; si < CONFIG.SITE_RULES.length; si = si + 1) {
                var siteRule = CONFIG.SITE_RULES[si];
                var matches = false;
                for (var ui = 0; ui < siteRule.urlIncludes.length; ui = ui + 1) {
                    if (url.includes(siteRule.urlIncludes[ui].toLowerCase())) { matches = true; }
                }
                for (var cti = 0; cti < siteRule.catalogIncludes.length; cti = cti + 1) {
                    if (catalog.includes(siteRule.catalogIncludes[cti].toLowerCase())) { matches = true; }
                }
                if (matches) {
                    for (var ti = 0; ti < siteRule.addTags.length; ti = ti + 1) {
                        if (!item.hasTag(siteRule.addTags[ti])) {
                            item.addTag(siteRule.addTags[ti]);
                            added.push(siteRule.addTags[ti]);
                        }
                    }
                }
            }
            return added;
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
        var consecutiveFailures = 0;

        for (var wi = CONFIG.START_INDEX; wi < end; wi = wi + 1) {
            var work = workList[wi];
            var writeItem = itemsById.get(work.itemID);
            if (!writeItem) { writeItem = await Zotero.Items.getAsync(work.itemID); }

            // Apply each matched rule (re-checking its guard on the current
            // object, so a re-run or concurrent change cannot double-apply).
            // Collect the union of tags the rules expect present, for verify.
            var expectedPresent = [];
            for (var rl = 0; rl < RULES.length; rl = rl + 1) {
                if (work.ruleNames.indexOf(RULES[rl].name) === -1) { continue; }
                if (!RULES[rl].guard(writeItem)) { continue; }   // already satisfied (idempotent)
                var addedTags = RULES[rl].apply(writeItem);
                for (var at = 0; at < addedTags.length; at = at + 1) {
                    if (expectedPresent.indexOf(addedTags[at]) === -1) { expectedPresent.push(addedTags[at]); }
                    result.applied.tagsAddedByRule[RULES[rl].name] = result.applied.tagsAddedByRule[RULES[rl].name] + 1;
                }
            }

            if (expectedPresent.length === 0) { continue; }   // nothing to do (idempotent skip)

            var ok = await saveVerifyRetry(writeItem, expectedPresent);
            if (ok) {
                result.applied.itemsChanged = result.applied.itemsChanged + 1;
                consecutiveFailures = 0;
            } else {
                result.applied.verifyFailuresAfterRetry.push(work.itemID);
                consecutiveFailures = consecutiveFailures + 1;
                if (consecutiveFailures >= CONFIG.MAX_CONSECUTIVE_FAILURES) {
                    result.applied.aborted = true;
                    result.applied.abortReason = `${consecutiveFailures} consecutive verification failures at index ${wi}; resume with START_INDEX=${wi}.`;
                    Zotero.debug(`normalize_items ABORT: ${result.applied.abortReason}`);
                    break;
                }
            }

            if ((wi - CONFIG.START_INDEX + 1) % CONFIG.CHECKPOINT_EVERY === 0) {
                Zotero.debug(`normalize_items: ${wi - CONFIG.START_INDEX + 1} processed (index ${wi}), changed=${result.applied.itemsChanged}, retries=${result.applied.verifyRetries}`);
                await new Promise(function (r) { setTimeout(r, CONFIG.YIELD_MS); });
            }
        }

        timing.writeMs = Date.now() - writeStart;
        Zotero.debug(`normalize_items: writes done in ${timing.writeMs} ms. itemsChanged=${result.applied.itemsChanged}`);
        if (result.applied.verifyFailuresAfterRetry.length > 0) {
            Zotero.debug(`WARNING: ${result.applied.verifyFailuresAfterRetry.length} item(s) failed verification after retry: ${result.applied.verifyFailuresAfterRetry.slice(0, 50).join(', ')}. Re-run (idempotent) to reconcile.`);
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
