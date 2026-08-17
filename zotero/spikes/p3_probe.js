// =============================================================================
// P3 PROBE  transaction-boundary vs residual (notifier + save) cost split
// =============================================================================
// P1 measured saveTx median ~1679ms/item on the test library -- far above the
// header's 504ms baseline -- and could NOT split transaction cost from notifier
// cost because the Zotero.Notifier.begin/end batch API is absent on this build.
// P3 does the split a different way, one that does not need that API.
//
// THE SPLIT (amortized-transaction timing):
//   saveTx(item)      = save() wrapped in its OWN executeTransaction. Pays the
//                       transaction-boundary cost ONCE PER ITEM, plus the notifier
//                       cascade, plus the save itself.
//   save(item) inside
//   ONE open outer     = the transaction boundary is opened once for the whole
//   executeTransaction   batch and amortized across N items -> ~0 per item. Each
//                        item still pays the save + whatever notifier work fires
//                        inside the txn.
//
//   median(saveTx) - median(amortized save) ~= the PER-ITEM TRANSACTION-BOUNDARY
//   cost. The remaining amortized-save time = save + notifier residual.
//
// INTERPRETATION:
//   - If the boundary cost is most of the 1679ms -> M1 (single executeTransaction)
//     is the fix: collapsing N boundaries to one removes the dominant term.
//   - If the residual (amortized save) is still ~1679ms -> the cost is NOT the
//     boundary; it is save-internal work, most likely the notifier cascade firing
//     per item even inside one txn. Then M1 barely helps and M2 (notifier
//     batching / suppression) is the real fix -- and since the begin/end API is
//     absent, M2 needs a different suppression mechanism (own probe).
//
// DEPENDENCY ON THE ROLLBACK PROBE: P3's amortized path puts many item.save()
// calls inside ONE executeTransaction. If the rollback probe found the txn layer
// does not roll back on throw, that does NOT affect P3 (P3 never throws inside the
// txn -- it returns cleanly), so P3's TIMING is valid regardless. But the DECISION
// P3 informs (build a batched-write M1) is only SAFE to act on given the rollback
// probe's verdict. Run the rollback probe first for the safety story; P3's numbers
// are independent and can be read on their own.
//
// This probe only WRITES (adds a unique tag per item to force a real save) and
// then DELETES those tags. Tag-only via the item API. Scratch clone only.
//
// Usage: Tools > Developer > Run JavaScript. CHECK "Run as async function".
// =============================================================================

var CONFIG = {
    I_UNDERSTAND_THIS_WRITES: false,

    // Items per timing arm. Two arms (saveTx, amortized) each touch this many
    // DISTINCT items with a distinct unique tag, so no arm ever re-saves a no-op.
    SAMPLE_SIZE: 150,

    LOG_EVERY: 50,

    MIN_ZOTERO_VERSION: '7.0',
    MAX_ZOTERO_VERSION: '9.0.6',
    BYPASS_VERSION_CHECK: false
};

var PROBE_TAG_BASE = '__p3_probe_' + Date.now();

var report = {
    probeTagBase: PROBE_TAG_BASE,
    sampleSize: CONFIG.SAMPLE_SIZE,
    saveTxMs: { median: null, p90: null, min: null, max: null },
    amortizedSaveMs: { median: null, p90: null, min: null, max: null, wholeTxnMs: null },
    boundaryCostPerItemMs: null,   // median(saveTx) - median(amortized)
    verdict: null,
    cleanup: { itemsTouched: 0, tagRemoved: 0, failures: [] }
};

function assert(condition, message) {
    if (!condition) { throw new Error('p3_probe pre-flight failed: ' + message); }
}

function percentile(sortedAscending, p) {
    if (sortedAscending.length === 0) { return null; }
    var rank = Math.ceil(p * sortedAscending.length) - 1;
    if (rank < 0) { rank = 0; }
    if (rank >= sortedAscending.length) { rank = sortedAscending.length - 1; }
    return sortedAscending[rank];
}

// --- PRE-FLIGHT --------------------------------------------------------------
assert(typeof Zotero !== 'undefined', 'Zotero global unavailable');
assert(typeof Zotero.Search === 'function', 'Zotero.Search unavailable');
assert(typeof Zotero.Items !== 'undefined' && typeof Zotero.Items.getAsync === 'function',
    'Zotero.Items.getAsync unavailable');
assert(typeof Zotero.DB !== 'undefined' && typeof Zotero.DB.executeTransaction === 'function',
    'Zotero.DB.executeTransaction unavailable -- amortized arm not possible');
var userLibraryID = Zotero.Libraries.userLibraryID;
assert(typeof userLibraryID === 'number', 'userLibraryID unavailable');

if (!CONFIG.BYPASS_VERSION_CHECK) {
    var zoteroVersion = Zotero.version;
    assert(Services.vc.compare(zoteroVersion, CONFIG.MIN_ZOTERO_VERSION) >= 0,
        'Zotero ' + zoteroVersion + ' below tested floor ' + CONFIG.MIN_ZOTERO_VERSION);
    if (Services.vc.compare(zoteroVersion, CONFIG.MAX_ZOTERO_VERSION) > 0) {
        Zotero.debug('p3_probe: Zotero ' + zoteroVersion + ' above tested ceiling '
            + CONFIG.MAX_ZOTERO_VERSION + '; confirm and bump.');
    }
}

assert(CONFIG.I_UNDERSTAND_THIS_WRITES === true,
    'this probe writes and deletes real tags; set CONFIG.I_UNDERSTAND_THIS_WRITES = true '
    + 'and run it on a SCRATCH / COPIED library, not your real one');

var touchedItemIDs = new Set();

try {
    var search = new Zotero.Search();
    search.libraryID = userLibraryID;
    search.addCondition('itemType', 'isNot', 'attachment');
    search.addCondition('itemType', 'isNot', 'note');
    search.addCondition('itemType', 'isNot', 'annotation');
    var candidateIDs = await search.search();
    // Two disjoint arms of SAMPLE_SIZE each: the same item must not be reused across
    // arms, or the second arm's save might differ (already-warm object). Need 2xN.
    assert(candidateIDs.length >= (CONFIG.SAMPLE_SIZE * 2),
        'need at least ' + (CONFIG.SAMPLE_SIZE * 2) + ' top-level items for two disjoint arms; found '
        + candidateIDs.length + '. Lower CONFIG.SAMPLE_SIZE.');

    var arm1IDs = candidateIDs.slice(0, CONFIG.SAMPLE_SIZE);                          // saveTx arm
    var arm2IDs = candidateIDs.slice(CONFIG.SAMPLE_SIZE, CONFIG.SAMPLE_SIZE * 2);     // amortized arm
    var arm1Items = await Zotero.Items.getAsync(arm1IDs);
    var arm2Items = await Zotero.Items.getAsync(arm2IDs);

    var tagArm1 = PROBE_TAG_BASE + '_tx';
    var tagArm2 = PROBE_TAG_BASE + '_am';

    // =========================================================================
    // ARM 1 -- saveTx per item. Boundary paid once PER ITEM. Timing window wraps
    // only the saveTx call.
    // =========================================================================
    var saveTxTimings = [];
    for (var i = 0; i < arm1Items.length; i = i + 1) {
        var item1 = arm1Items[i];
        if (item1.hasTag(tagArm1)) { continue; }   // unique tag; never true, guards no-op
        item1.addTag(tagArm1);
        touchedItemIDs.add(item1.id);
        var t0 = Date.now();
        await item1.saveTx();
        saveTxTimings.push(Date.now() - t0);
        if ((i + 1) % CONFIG.LOG_EVERY === 0) {
            Zotero.debug('p3_probe ARM1 saveTx: ' + (i + 1) + ' timed');
        }
    }
    saveTxTimings.sort(function (a, b) { return a - b; });
    report.saveTxMs.median = percentile(saveTxTimings, 0.50);
    report.saveTxMs.p90 = percentile(saveTxTimings, 0.90);
    report.saveTxMs.min = saveTxTimings.length ? saveTxTimings[0] : null;
    report.saveTxMs.max = saveTxTimings.length ? saveTxTimings[saveTxTimings.length - 1] : null;

    // =========================================================================
    // ARM 2 -- N item.save() inside ONE executeTransaction. Boundary paid ONCE
    // for the whole batch. Two timings captured:
    //   perItemInsideTxn: time of each save() call inside the open txn (isolates
    //                     save + in-txn notifier work, boundary already amortized).
    //   wholeTxnMs:       wall time of the entire executeTransaction (includes the
    //                     single boundary + all saves + commit).
    // The per-item medians are what the boundary-cost subtraction uses; wholeTxnMs
    // is the real-world "what would the batched write actually take" number.
    // =========================================================================
    var amortizedTimings = [];
    var wholeTxnStart = Date.now();
    await Zotero.DB.executeTransaction(async function () {
        for (var j = 0; j < arm2Items.length; j = j + 1) {
            var item2 = arm2Items[j];
            if (item2.hasTag(tagArm2)) { continue; }
            item2.addTag(tagArm2);
            touchedItemIDs.add(item2.id);
            var s0 = Date.now();
            await item2.save();          // joins the open outer txn; no per-item boundary
            amortizedTimings.push(Date.now() - s0);
            if ((j + 1) % CONFIG.LOG_EVERY === 0) {
                Zotero.debug('p3_probe ARM2 amortized save: ' + (j + 1) + ' timed');
            }
        }
    });
    report.amortizedSaveMs.wholeTxnMs = Date.now() - wholeTxnStart;
    amortizedTimings.sort(function (a, b) { return a - b; });
    report.amortizedSaveMs.median = percentile(amortizedTimings, 0.50);
    report.amortizedSaveMs.p90 = percentile(amortizedTimings, 0.90);
    report.amortizedSaveMs.min = amortizedTimings.length ? amortizedTimings[0] : null;
    report.amortizedSaveMs.max = amortizedTimings.length ? amortizedTimings[amortizedTimings.length - 1] : null;

    // =========================================================================
    // SPLIT + VERDICT
    // =========================================================================
    var txMed = report.saveTxMs.median;
    var amMed = report.amortizedSaveMs.median;
    report.boundaryCostPerItemMs = (txMed !== null && amMed !== null) ? (txMed - amMed) : null;

    // What fraction of the per-item saveTx cost is the boundary?
    var boundaryShare = (txMed && txMed > 0 && report.boundaryCostPerItemMs !== null)
        ? (report.boundaryCostPerItemMs / txMed) : null;

    // wholeTxnMs is the CONFOUND-FREE headline: the actual wall time to write
    // SAMPLE_SIZE items in one transaction, no subtraction, no population caveat.
    // Project the full backfill directly from it.
    var perItemInBatchMs = report.amortizedSaveMs.wholeTxnMs / CONFIG.SAMPLE_SIZE;
    var projectedBatchMin = Math.round(perItemInBatchMs * 5178 / 60000);
    var projectedSaveTxMin = txMed ? Math.round(txMed * 5178 / 60000) : null;

    // CAVEAT stated in-verdict: the two arms use DISJOINT item sets (to avoid
    // warm-cache pollution from re-saving the same object). So the boundary-cost
    // SUBTRACTION carries a population-variance caveat -- it assumes the two 150-item
    // subsets have similar median save cost. wholeTxnMs does NOT depend on the
    // subtraction and is the number to trust most.
    if (boundaryShare === null) {
        report.verdict = 'INCONCLUSIVE: could not compute medians. Check arm sample sizes.';
    } else if (boundaryShare >= 0.5) {
        report.verdict = 'TRANSACTION-BOUNDARY-DOMINATED. Boundary ~' + report.boundaryCostPerItemMs
            + 'ms of the ~' + txMed + 'ms saveTx median (' + Math.round(boundaryShare * 100)
            + '%; subtraction carries a population-variance caveat, disjoint arms). CONFOUND-FREE '
            + 'evidence: ' + CONFIG.SAMPLE_SIZE + ' items committed in ONE txn in '
            + report.amortizedSaveMs.wholeTxnMs + 'ms = ~' + Math.round(perItemInBatchMs)
            + 'ms/item, vs ~' + txMed + 'ms/item via saveTx. M1 (single executeTransaction) IS THE '
            + 'FIX. Projected 5178-item backfill: ~' + projectedSaveTxMin + ' min (saveTx) -> ~'
            + projectedBatchMin + ' min (single txn).';
    } else {
        report.verdict = 'SAVE/NOTIFIER-DOMINATED: amortizing the transaction boundary only removed ~'
            + report.boundaryCostPerItemMs + 'ms; each save still costs ~' + amMed + 'ms INSIDE one '
            + 'transaction (' + Math.round((1 - boundaryShare) * 100) + '% of the original). '
            + 'Confound-free confirmation: ' + CONFIG.SAMPLE_SIZE + ' items in one txn still took '
            + report.amortizedSaveMs.wholeTxnMs + 'ms (~' + Math.round(perItemInBatchMs) + 'ms/item), '
            + 'so one transaction did NOT rescue the runtime. The cost is save-internal, most likely '
            + 'the notifier cascade firing per item even inside the txn. M1 alone will NOT fix this; '
            + 'M2 (notifier batching/suppression) is the real fix. The Notifier.begin/end batch API '
            + 'was absent in P1, so M2 needs a different suppression mechanism -- that is the next probe.';
    }

    Zotero.debug('=== p3_probe RESULT ===');
    Zotero.debug('saveTx    median=' + report.saveTxMs.median + '  p90=' + report.saveTxMs.p90
        + '  min=' + report.saveTxMs.min + '  max=' + report.saveTxMs.max);
    Zotero.debug('amortized median=' + report.amortizedSaveMs.median + '  p90=' + report.amortizedSaveMs.p90
        + '  min=' + report.amortizedSaveMs.min + '  max=' + report.amortizedSaveMs.max
        + '  wholeTxn=' + report.amortizedSaveMs.wholeTxnMs + 'ms for ' + CONFIG.SAMPLE_SIZE + ' items');
    Zotero.debug('boundary cost/item ~= ' + report.boundaryCostPerItemMs + 'ms');
    Zotero.debug('VERDICT: ' + report.verdict);

} catch (error) {
    Zotero.debug('p3_probe FAILED: ' + error.message + '\n' + error.stack);
    report.verdict = 'PROBE ERRORED: ' + error.message;
} finally {
    // Cleanup: remove PROBE_TAG_BASE-prefixed tags from touched items. Item API
    // only (this probe made no raw writes). Name-prefix scoped.
    var touchedList = Array.from(touchedItemIDs);
    for (var ci = 0; ci < touchedList.length; ci = ci + 1) {
        try {
            var cleanupItem = await Zotero.Items.getAsync(touchedList[ci]);
            var tags = cleanupItem.getTags();
            var removedAny = false;
            for (var ti = 0; ti < tags.length; ti = ti + 1) {
                if (tags[ti].tag.indexOf(PROBE_TAG_BASE) === 0) {
                    cleanupItem.removeTag(tags[ti].tag);
                    report.cleanup.tagRemoved = report.cleanup.tagRemoved + 1;
                    removedAny = true;
                }
            }
            if (removedAny) {
                await cleanupItem.saveTx();
                report.cleanup.itemsTouched = report.cleanup.itemsTouched + 1;
            }
        } catch (cleanupErr) {
            report.cleanup.failures.push({ itemID: touchedList[ci], error: cleanupErr.message });
        }
    }
    Zotero.debug('p3_probe cleanup: removed ' + report.cleanup.tagRemoved + ' tag(s) from '
        + report.cleanup.itemsTouched + ' item(s); ' + report.cleanup.failures.length + ' failure(s).');
    if (report.cleanup.failures.length > 0) {
        Zotero.debug('p3_probe cleanup failures (remove names starting "' + PROBE_TAG_BASE
            + '" manually): ' + JSON.stringify(report.cleanup.failures.slice(0, 20)));
    }
}

return report;
