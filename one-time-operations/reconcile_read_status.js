// =============================================================================
// RECONCILE LEGACY Read_Status -> reading-state TAGS  (ONE-TIME)
// =============================================================================
// Version: 1.0.0
// Date:    2026-08-12
// Thread:  3 (incoming-item automation). ONE-TIME reconciliation, not recurring.
// Status:  owner action. MUST run BEFORE the first normalize_items.js pass.
//          This ordering is load-bearing: the normalizer adds __unopened to any
//          item with no opened-state tag, and 497 items have no state tag but a
//          Read_Status line saying they were engaged (in progress / read). If
//          the normalizer runs first it stamps __unopened on those 497, which
//          this pass would then have to undo. Tags-first, normalizer-last.
//
// Purpose: The pre-tag reading scheme recorded state in a "Read_Status:" line
//          in each item's extra field. Diagnosed 2026-08-12 over 3,556 items
//          carrying that line: current tags and the legacy line disagree far
//          more than they agree (agree 319, disagree 1,236). The owner's
//          disposition (2026-08-11): tags are authoritative and Read_Status is
//          legacy, BUT reconcile the cases where extra plausibly holds state
//          the tag lost, because doing so is straightforward. It is:
//
//   RECONCILABLE population (this pass acts on these):
//     A. 1,190 items: only opened-state tag is __unopened, extra maps to
//        __in_progress or __read. __unopened is a never-updated default and
//        extra is positive evidence of engagement. ACTION: add the mapped tag,
//        then remove __unopened (owner decision 2026-08-12: swap, not leave
//        both). End state: item carries the mapped state tag, no __unopened.
//     B. 497 items: NO opened-state tag at all, extra maps to __in_progress or
//        __read. ACTION: add the mapped tag. Nothing to remove.
//
//   NOT reconciled (this pass deliberately leaves these):
//     - 46 tag-wins disagreements: item already carries a deliberate
//       __in_progress/__read that differs from extra. Tag wins; extra is
//       stale. Left untouched.
//     - 319 agreements: nothing to do.
//     - "To Read" (1,481) and "Not Reading" (19) extra values: these map to
//       __to_read / __not_reading, which do NOT suppress __unopened (Q1) and
//       do NOT indicate engagement. They are not reconciliation targets; an
//       item that is "To Read" correctly gets __unopened from the normalizer.
//       They were mis-counted as "unmapped" in the first diagnostic run only
//       because the mapping table omitted them; they are included in the
//       mapping here so they are correctly classified as no-ops.
//
// This completes the intent of the abandoned convert_readstatus_to_tags.js,
// which drafted "replace __unopened with the mapped tag" but left every write
// commented out and never ran. Prior code is evidence of intent, not a
// verified operation (CONVENTIONS: docs/comments are evidence, not ground
// truth); this runs it under detect-then-write discipline (D2).
//
// extra is NOT modified. The Read_Status line stays in the extra field; only
// tags change. Stripping the legacy line is a separate, later, field-content
// operation, out of scope here (it edits field text, which per the thread-3
// decision note ships as its own spiked, backup-gated tool).
//
// Usage:   Tools > Developer > Run JavaScript. CHECK "Run as async function".
//          DRY_RUN is true by default: prints the full plan and per-item
//          intended actions (bounded sample) and writes nothing. Set
//          CONFIG.DRY_RUN = false to apply. Idempotent: a re-run after apply
//          finds the mapped tags already present (and __unopened already gone
//          for population A) and no-ops those items (CONVENTIONS A7).
//
// Reversibility: every touched item is added to a dated review collection.
//          Deleting the collection does not undo tag changes, but the
//          collection is the exact list of what was touched, and the run
//          returns the itemIDs by action, so a manual reversal is scoped. The
//          owner accepted the collection as sufficient backup (2026-08-12).
//
// Write strategy: per item, add/remove tags then saveTx, re-fetch, verify the
//          intended end state, retry once on a miss (S4 defence-in-depth). Not
//          batched into one transaction because verify needs a settled,
//          re-fetchable state between save and check. Collection membership is
//          batched separately.
//
// Scale (A5): the reconcilable population is ~1,687, larger than the /unread
//          migration. The scan reads 3,556 extra fields; the write touches
//          ~1,687 items with a saveTx each. Batched loads (never getAll),
//          event-loop yields, a checkpoint log every CHECKPOINT_EVERY writes,
//          and a consecutive-failure abort. START_INDEX allows resuming a
//          partial apply. Ramp caps (MAX_WRITES) allow a 100/500/full staged
//          first run before committing to all ~1,687.
// =============================================================================

// 1. CONFIGURATION
var CONFIG = {
    DRY_RUN: true,                        // false = apply. Read the plan first.

    UNOPENED_TAG: '__unopened',
    OPENED_STATE_TAGS: ['__unopened', '__in_progress', '__read'],

    // Legacy line marker and value -> tag mapping. Values matched
    // case-insensitively and trimmed. Includes To Read / Not Reading so they
    // classify as non-engagement no-ops rather than "unmapped".
    READ_STATUS_MARKER: /Read_Status:\s*(.+)/i,
    READ_STATUS_TO_TAG: {
        'new': '__unopened',
        'unopened': '__unopened',
        'unread': '__unopened',
        'to read': '__to_read',
        'not reading': '__not_reading',
        'in progress': '__in_progress',
        'reading': '__in_progress',
        'read': '__read',
        'finished': '__read'
    },
    // Only these mapped tags count as "engagement" that triggers reconciliation.
    // __unopened / __to_read / __not_reading are non-engagement: no action.
    ENGAGEMENT_TAGS: ['__in_progress', '__read'],

    COLLECTION_PREFIX: 'Read_Status reconciled',  // dated

    // Write-verify-retry (S4).
    RETRY_BACKOFF_MS: 800,
    RETRY_SETTLE_MS: 400,

    // Scale treatment (A5).
    LOAD_BATCH_SIZE: 500,
    YIELD_MS: 10,
    CHECKPOINT_EVERY: 200,          // Zotero.debug progress every N writes
    MAX_CONSECUTIVE_FAILURES: 20,   // abort if this many writes fail verification in a row
    START_INDEX: 0,                 // resume a partial apply from this index into the write list
    MAX_WRITES: 0,                  // 0 = no cap (full). Set 100 / 500 to ramp.

    DRY_RUN_SAMPLE_MAX: 40,         // per-action sample echoed in the plan

    MIN_ZOTERO_VERSION: '7.0',
    MAX_ZOTERO_VERSION: '9.0.6',
    BYPASS_VERSION_CHECK: false
};

// 2. STATE
var timing = { scriptStart: Date.now(), assertions: 0, scanMs: 0, writeMs: 0, yieldCount: 0 };
var result = {
    dryRun: CONFIG.DRY_RUN,
    candidatesScanned: 0,
    planSwapUnopened: [],   // A: { itemID, mappedTag }  add mappedTag, remove __unopened
    planAddOnly: [],        // B: { itemID, mappedTag }  add mappedTag (no state tag present)
    skippedTagWins: 0,
    skippedAgree: 0,
    skippedNonEngagement: 0,// To Read / Not Reading / etc.
    skippedNoMarker: 0,
    applied: {
        mappedTagAdded: 0,
        unopenedRemoved: 0,
        verifyRetries: 0,
        verifyFailuresAfterRetry: [],
        addedToCollection: 0,
        collectionName: null,
        collectionID: null,
        aborted: false,
        abortReason: null
    }
};

// 3. HELPERS
function assert(condition, message) {
    timing.assertions = timing.assertions + 1;
    if (!condition) {
        throw new Error(`reconcile_read_status pre-flight failed: ${message}`);
    }
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

// Save an item's pending tag changes and verify the end state.
//
// PERFORMANCE NOTE (learned the hard way, 2026-08-12): the first version of
// this re-fetched the item with Zotero.Items.getAsync on EVERY verify. That
// was both slow and wrong. Slow: getAsync triggers a full itemData load, and
// running ~1,687 of them serially took 2h42m (the Zotero debug log showed
// single-item loads taking up to 198s under contention). Wrong: getAsync
// returns the CACHED item object -- the same instance we just saved -- so the
// re-fetch did expensive DB work only to hand back an object whose in-memory
// tag state was already correct. It never actually tested persistence.
//
// saveTx() updates the in-memory item synchronously (repo idiom: mark-as-read
// and tag-google-books read fields off the same object right after saveTx), so
// verifying against `item` itself is free and correct for "did the change take
// in memory". The common path is therefore: save, verify in memory, done. The
// rare failure path re-fetches with getAsync (verified idiom) rather than a
// per-item re-fetch on every item.
async function saveVerifyRetry(item, expectedPresent, expectedAbsent) {
    await item.saveTx();

    var verifyInMemory = function (target) {
        for (var pi = 0; pi < expectedPresent.length; pi = pi + 1) {
            if (!target.hasTag(expectedPresent[pi])) { return false; }
        }
        for (var ai = 0; ai < expectedAbsent.length; ai = ai + 1) {
            if (target.hasTag(expectedAbsent[ai])) { return false; }
        }
        return true;
    };

    // Common path: the in-memory object reflects the save. Free check.
    if (verifyInMemory(item)) { return true; }

    // Rare miss: the intended change is not present in memory after a
    // successful saveTx, which should not happen. Treat as an anomaly: back
    // off, re-fetch a fresh handle (getAsync -- verified, in-repo idiom),
    // re-apply, save, settle, verify. This path pays getAsync's cost, but only
    // for genuine failures (the actual run had zero). getAsync returns the
    // cached object, which after the settle reflects the persisted state.
    result.applied.verifyRetries = result.applied.verifyRetries + 1;
    await new Promise(function (r) { setTimeout(r, CONFIG.RETRY_BACKOFF_MS); });
    var retryItem = await Zotero.Items.getAsync(item.id);
    for (var rp = 0; rp < expectedPresent.length; rp = rp + 1) {
        if (!retryItem.hasTag(expectedPresent[rp])) { retryItem.addTag(expectedPresent[rp]); }
    }
    for (var ra = 0; ra < expectedAbsent.length; ra = ra + 1) {
        if (retryItem.hasTag(expectedAbsent[ra])) { retryItem.removeTag(expectedAbsent[ra]); }
    }
    await retryItem.saveTx();
    await new Promise(function (r) { setTimeout(r, CONFIG.RETRY_SETTLE_MS); });
    return verifyInMemory(retryItem);
}

// 4. PRE-FLIGHT
assert(typeof Zotero !== 'undefined', 'Zotero global unavailable');
assert(typeof Zotero.Search === 'function', 'Zotero.Search unavailable');
assert(typeof Zotero.Collection === 'function', 'Zotero.Collection unavailable');
assert(typeof Zotero.Items.getAsync === 'function', 'Zotero.Items.getAsync unavailable');
var userLibraryID = Zotero.Libraries.userLibraryID;
assert(typeof userLibraryID === 'number', 'userLibraryID unavailable');

if (!CONFIG.BYPASS_VERSION_CHECK) {
    var zoteroVersion = Zotero.version;
    assert(
        Services.vc.compare(zoteroVersion, CONFIG.MIN_ZOTERO_VERSION) >= 0,
        `Zotero ${zoteroVersion} below tested floor ${CONFIG.MIN_ZOTERO_VERSION}`
    );
    if (Services.vc.compare(zoteroVersion, CONFIG.MAX_ZOTERO_VERSION) > 0) {
        Zotero.debug(`reconcile_read_status: Zotero ${zoteroVersion} above tested ceiling ${CONFIG.MAX_ZOTERO_VERSION}; confirm and bump.`);
    }
}

// 5. MAIN
try {
    var scanStart = Date.now();

    // Candidate set: top-level items whose extra contains "Read_Status". Same
    // defensive fallback as the diagnostic in case the 'extra' condition is
    // unavailable.
    var candidateIDs = [];
    var searchPath = 'extra-condition';
    try {
        var extraSearch = new Zotero.Search();
        extraSearch.libraryID = userLibraryID;
        extraSearch.addCondition('noChildren', 'true');
        extraSearch.addCondition('extra', 'contains', 'Read_Status');
        candidateIDs = await extraSearch.search();
    } catch (extraErr) {
        Zotero.debug(`reconcile_read_status: 'extra' condition unavailable (${extraErr.message}); full top-level scan.`);
        searchPath = 'full-scan-fallback';
        var allSearch = new Zotero.Search();
        allSearch.libraryID = userLibraryID;
        allSearch.addCondition('noChildren', 'true');
        candidateIDs = await allSearch.search();
    }

    var candidates = await loadItemsInBatchesFromIDs(candidateIDs);
    result.candidatesScanned = candidates.length;

    // Index the already-loaded candidate objects by id. The write path reuses
    // these instead of re-fetching each item with getAsync -- the scan already
    // paid to load them, and a second load per item is what made the first run
    // take hours (see saveVerifyRetry perf note). saveTx mutates these same
    // cached instances, so acting on them is correct.
    var itemsById = new Map();
    for (var mi = 0; mi < candidates.length; mi = mi + 1) {
        itemsById.set(candidates[mi].id, candidates[mi]);
    }

    for (var ci = 0; ci < candidates.length; ci = ci + 1) {
        var item = candidates[ci];
        var extra = item.getField('extra') || '';
        var match = extra.match(CONFIG.READ_STATUS_MARKER);
        if (!match) { result.skippedNoMarker = result.skippedNoMarker + 1; continue; }

        var mappedTag = CONFIG.READ_STATUS_TO_TAG[match[1].trim().toLowerCase()];
        // Unmapped or non-engagement (To Read / Not Reading / unopened): no action.
        if (!mappedTag || CONFIG.ENGAGEMENT_TAGS.indexOf(mappedTag) === -1) {
            result.skippedNonEngagement = result.skippedNonEngagement + 1;
            continue;
        }

        var stateTags = [];
        for (var oti = 0; oti < CONFIG.OPENED_STATE_TAGS.length; oti = oti + 1) {
            if (item.hasTag(CONFIG.OPENED_STATE_TAGS[oti])) { stateTags.push(CONFIG.OPENED_STATE_TAGS[oti]); }
        }

        if (stateTags.length === 0) {
            // B: no state tag; add the mapped engagement tag.
            result.planAddOnly.push({ itemID: item.id, mappedTag: mappedTag });
        } else if (stateTags.indexOf(mappedTag) !== -1) {
            // Already agrees.
            result.skippedAgree = result.skippedAgree + 1;
        } else if (stateTags.length === 1 && stateTags[0] === CONFIG.UNOPENED_TAG) {
            // A: only __unopened; swap for the mapped engagement tag.
            result.planSwapUnopened.push({ itemID: item.id, mappedTag: mappedTag });
        } else {
            // Deliberate __in_progress/__read that differs, or a multi-tag
            // state: tag wins, leave alone.
            result.skippedTagWins = result.skippedTagWins + 1;
        }
    }
    timing.scanMs = Date.now() - scanStart;

    // --- Plan (A4) ---
    var now = new Date();
    var pad2 = function (n) { return String(n).padStart(2, '0'); };
    var dateStamp = `${now.getFullYear()}-${pad2(now.getMonth() + 1)}-${pad2(now.getDate())}`;
    var collectionName = `${CONFIG.COLLECTION_PREFIX} ${dateStamp}`;
    result.applied.collectionName = collectionName;

    var plan = [];
    plan.push('=== reconcile_read_status PLAN ===');
    plan.push(`search path: ${searchPath}; candidates scanned: ${result.candidatesScanned}`);
    plan.push(`A. swap __unopened -> mapped engagement tag: ${result.planSwapUnopened.length} item(s)`);
    plan.push(`B. add mapped engagement tag (no state tag present): ${result.planAddOnly.length} item(s)`);
    plan.push(`skipped -- agree: ${result.skippedAgree}, tag-wins: ${result.skippedTagWins}, non-engagement (To Read/Not Reading/etc): ${result.skippedNonEngagement}, no marker: ${result.skippedNoMarker}`);
    plan.push(`review collection: "${collectionName}"  (all A+B items)`);
    plan.push('writes: TAGS only (add mapped tag; remove __unopened for A) + collection membership. extra field is NOT modified.');
    var sampleA = result.planSwapUnopened.slice(0, CONFIG.DRY_RUN_SAMPLE_MAX);
    for (var sa = 0; sa < sampleA.length; sa = sa + 1) {
        plan.push(`  A [${sampleA[sa].itemID}] +${sampleA[sa].mappedTag} -__unopened`);
    }
    var sampleB = result.planAddOnly.slice(0, CONFIG.DRY_RUN_SAMPLE_MAX);
    for (var sb = 0; sb < sampleB.length; sb = sb + 1) {
        plan.push(`  B [${sampleB[sb].itemID}] +${sampleB[sb].mappedTag}`);
    }
    for (var pl = 0; pl < plan.length; pl = pl + 1) { Zotero.debug(plan[pl]); }

    if (CONFIG.DRY_RUN) {
        Zotero.debug('DRY_RUN: nothing written. Set CONFIG.DRY_RUN = false to apply.');
    } else {
        var writeStart = Date.now();

        // One combined ordered write list so START_INDEX / MAX_WRITES apply
        // across both actions and a resume is deterministic. Each entry carries
        // its action so the write knows whether to remove __unopened.
        var writeList = [];
        for (var wa = 0; wa < result.planSwapUnopened.length; wa = wa + 1) {
            writeList.push({ itemID: result.planSwapUnopened[wa].itemID, mappedTag: result.planSwapUnopened[wa].mappedTag, removeUnopened: true });
        }
        for (var wb = 0; wb < result.planAddOnly.length; wb = wb + 1) {
            writeList.push({ itemID: result.planAddOnly[wb].itemID, mappedTag: result.planAddOnly[wb].mappedTag, removeUnopened: false });
        }

        var end = writeList.length;
        if (CONFIG.MAX_WRITES > 0) { end = Math.min(end, CONFIG.START_INDEX + CONFIG.MAX_WRITES); }

        var touchedIDs = [];
        var consecutiveFailures = 0;

        for (var wi = CONFIG.START_INDEX; wi < end; wi = wi + 1) {
            var entry = writeList[wi];
            // Reuse the object the scan already loaded. Only fall back to a
            // load if it is somehow absent (should not happen: every write-list
            // id came from the scan). The fallback keeps a resumed run correct.
            var writeItem = itemsById.get(entry.itemID);
            if (!writeItem) { writeItem = await Zotero.Items.getAsync(entry.itemID); }

            // Idempotency: if the mapped tag is already present and (for swaps)
            // __unopened already gone, this item was done on a prior run. Skip
            // the write but still collect it for the collection.
            var alreadyDone = writeItem.hasTag(entry.mappedTag)
                && (!entry.removeUnopened || !writeItem.hasTag(CONFIG.UNOPENED_TAG));
            if (!alreadyDone) {
                if (!writeItem.hasTag(entry.mappedTag)) { writeItem.addTag(entry.mappedTag); }
                if (entry.removeUnopened && writeItem.hasTag(CONFIG.UNOPENED_TAG)) { writeItem.removeTag(CONFIG.UNOPENED_TAG); }

                var expectedAbsent = entry.removeUnopened ? [CONFIG.UNOPENED_TAG] : [];
                var ok = await saveVerifyRetry(writeItem, [entry.mappedTag], expectedAbsent);
                if (ok) {
                    result.applied.mappedTagAdded = result.applied.mappedTagAdded + 1;
                    if (entry.removeUnopened) { result.applied.unopenedRemoved = result.applied.unopenedRemoved + 1; }
                    consecutiveFailures = 0;
                } else {
                    result.applied.verifyFailuresAfterRetry.push(entry.itemID);
                    consecutiveFailures = consecutiveFailures + 1;
                    if (consecutiveFailures >= CONFIG.MAX_CONSECUTIVE_FAILURES) {
                        result.applied.aborted = true;
                        result.applied.abortReason = `${consecutiveFailures} consecutive verification failures at index ${wi}; aborting. Fix the cause and resume with START_INDEX=${wi}.`;
                        Zotero.debug(`reconcile_read_status ABORT: ${result.applied.abortReason}`);
                        break;
                    }
                }
            }
            touchedIDs.push(entry.itemID);

            if ((wi - CONFIG.START_INDEX + 1) % CONFIG.CHECKPOINT_EVERY === 0) {
                Zotero.debug(`reconcile_read_status: ${wi - CONFIG.START_INDEX + 1} processed (index ${wi}), added=${result.applied.mappedTagAdded}, removed=${result.applied.unopenedRemoved}, retries=${result.applied.verifyRetries}`);
                await new Promise(function (r) { setTimeout(r, CONFIG.YIELD_MS); });
            }
        }

        // Review collection.
        if (touchedIDs.length > 0) {
            var collection = new Zotero.Collection();
            collection.libraryID = userLibraryID;
            collection.name = collectionName;
            result.applied.collectionID = await collection.saveTx();
            await Zotero.DB.executeTransaction(async function () {
                for (var ti = 0; ti < touchedIDs.length; ti = ti + 1) {
                    // Reuse the already-loaded object; only load if absent
                    // (resumed run whose scan did not cover this id).
                    var collItem = itemsById.get(touchedIDs[ti]);
                    if (!collItem) { collItem = await Zotero.Items.getAsync(touchedIDs[ti]); }
                    collItem.addToCollection(result.applied.collectionID);
                    await collItem.save();
                }
            });
            result.applied.addedToCollection = touchedIDs.length;
        }

        timing.writeMs = Date.now() - writeStart;
        Zotero.debug(`reconcile_read_status: writes done in ${timing.writeMs} ms. added=${result.applied.mappedTagAdded}, __unopened removed=${result.applied.unopenedRemoved}`);
        Zotero.debug(`Review collection "${collectionName}". extra fields untouched. To reverse a swap: re-add __unopened and remove the mapped tag on those items.`);
        if (result.applied.verifyFailuresAfterRetry.length > 0) {
            Zotero.debug(`WARNING: ${result.applied.verifyFailuresAfterRetry.length} item(s) failed verification after retry: ${result.applied.verifyFailuresAfterRetry.slice(0, 50).join(', ')}${result.applied.verifyFailuresAfterRetry.length > 50 ? ' ...' : ''}. Re-run (idempotent) to reconcile.`);
        }
    }
} catch (error) {
    Zotero.debug(`reconcile_read_status FAILED: ${error.message}\n${error.stack}`);
    throw error;
}

// 6. SUMMARY
timing.totalMs = Date.now() - timing.scriptStart;
result.timing = timing;
Zotero.debug(`reconcile_read_status done in ${timing.totalMs} ms (dryRun=${CONFIG.DRY_RUN}, scanMs=${timing.scanMs}, writeMs=${timing.writeMs}, assertions=${timing.assertions})`);
return result;
