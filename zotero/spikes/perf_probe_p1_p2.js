// =============================================================================
// PERF PROBE  P1 (bottleneck split) + P2 (executeTransaction/save semantics)
// =============================================================================
// Purpose: produce the two facts that decide the normalize_items perf fix
// ranking, and nothing else. It is a MEASUREMENT probe, not a fix.
//
//   P1  Is the ~504ms/item spent in the DB TRANSACTION or in the NOTIFIER
//       cascade? Times N real saves via saveTx (always available). If the
//       Zotero.Notifier.begin/end batch API exists, ALSO times N saves with
//       the cascade suppressed, so the delta isolates notifier cost.
//         - transaction-dominated  -> M1 (single executeTransaction) is the fix
//         - notifier-dominated     -> M2 (notifier batching) is the fix; M1 alone
//                                     barely moves the number
//
//   P2  Three correctness facts M1/M3/M4 depend on, each on its own item:
//       (a) item.save() inside Zotero.DB.executeTransaction JOINS the open txn
//           (does not throw or nest).
//       (b) after the txn commits, a FRESHLY RE-FETCHED item reports the tag via
//           hasTag -- i.e. the tag actually reached the DB, not just memory.
//           (This is the load-bearing invariant behind M4's free in-memory
//           verify. Checking hasTag on the pre-save object would be a false
//           positive, since addTag mutates memory before the save; so P2b
//           re-fetches.)
//       (c) a deliberate throw inside executeTransaction rolls back ALL saves in
//           that txn (the all-or-nothing failure model M4 assumes).
//
// SAFETY (adversarial-pass mitigations, do not weaken):
//   - Writes real tags, so it is gated behind I_UNDERSTAND_THIS_WRITES and is
//     intended for a SCRATCH / COPIED library. Run it on the real library and
//     it still self-heals (see cleanup), but do not.
//   - Uses a UNIQUE throwaway tag per run (__perf_probe_<timestamp>) that cannot
//     pre-exist, so every timed save is a genuine modify with a real notifier
//     cascade (an already-present tag would make saveTx a no-op and understate
//     the cost), and cleanup can delete exactly that tag and nothing else.
//   - Removes every tag it added at the end, in its own untimed phase. Timing
//     windows wrap ONLY the measured save.
//   - P1 results are printed BEFORE P2 runs, so a P2 throw never costs the P1
//     measurement.
//
// Reports median / p90 / min (not mean): median resists outliers, p90 shows the
// notifier tail, min reveals a warm-observer fast path if one exists.
//
// Usage: Tools > Developer > Run JavaScript. CHECK "Run as async function".
//        Set CONFIG.I_UNDERSTAND_THIS_WRITES = true on a scratch library.
// =============================================================================

var CONFIG = {
    // Hard consent gate. Must be flipped true or the probe refuses to write.
    // This probe writes and then deletes real tags; run it on a copied library.
    I_UNDERSTAND_THIS_WRITES: false,

    // Number of items to time in P1. 200 gives a stable median/p90 without a
    // long run. These items get the throwaway tag added then removed.
    P1_SAMPLE_SIZE: 200,

    // Log a running datapoint every this-many timed saves, so a stall is visible.
    P1_LOG_EVERY: 50,

    // Zotero band this probe was written against. Stable APIs, but fail loudly
    // rather than mid-measurement if a symbol is missing.
    MIN_ZOTERO_VERSION: '7.0',
    MAX_ZOTERO_VERSION: '9.0.6',
    BYPASS_VERSION_CHECK: false
};

// Unique per run: cannot collide with any real tag, makes every save a real
// modify, and makes cleanup unambiguous (delete exactly this token).
var PROBE_TAG = '__perf_probe_' + Date.now();

var report = {
    probeTag: PROBE_TAG,
    p1: {
        sampleRequested: CONFIG.P1_SAMPLE_SIZE,
        sampleTimed: 0,
        saveTxMs: { median: null, p90: null, min: null, max: null },
        notifierApiPresent: false,
        suppressedSaveMs: { median: null, p90: null, min: null, max: null },
        verdict: null                // filled in after timing
    },
    p2: {
        saveJoinsTransaction: null,  // (a)
        tagPersistsAfterCommit: null,// (b)
        throwRollsBackWholeTxn: null,// (c)
        notes: []
    },
    cleanup: { itemsTouched: 0, tagRemoved: 0, failures: [] }
};

function assert(condition, message) {
    if (!condition) { throw new Error('perf_probe pre-flight failed: ' + message); }
}

// Percentile over a numeric array. p in [0,1]. Nearest-rank on a sorted copy.
// Inlined stats rather than a helper library -- single file, single call site
// pattern, and the math must be obvious for a measurement tool to be trusted.
function percentile(sortedAscending, p) {
    if (sortedAscending.length === 0) { return null; }
    var rank = Math.ceil(p * sortedAscending.length) - 1;
    if (rank < 0) { rank = 0; }
    if (rank >= sortedAscending.length) { rank = sortedAscending.length - 1; }
    return sortedAscending[rank];
}

// ---- PRE-FLIGHT -------------------------------------------------------------
assert(typeof Zotero !== 'undefined', 'Zotero global unavailable');
assert(typeof Zotero.Search === 'function', 'Zotero.Search unavailable');
assert(typeof Zotero.Items !== 'undefined' && typeof Zotero.Items.getAsync === 'function',
    'Zotero.Items.getAsync unavailable');
assert(typeof Zotero.DB !== 'undefined' && typeof Zotero.DB.executeTransaction === 'function',
    'Zotero.DB.executeTransaction unavailable -- M1/M3 not testable on this build');
var userLibraryID = Zotero.Libraries.userLibraryID;
assert(typeof userLibraryID === 'number', 'userLibraryID unavailable');

if (!CONFIG.BYPASS_VERSION_CHECK) {
    var zoteroVersion = Zotero.version;
    assert(Services.vc.compare(zoteroVersion, CONFIG.MIN_ZOTERO_VERSION) >= 0,
        'Zotero ' + zoteroVersion + ' below tested floor ' + CONFIG.MIN_ZOTERO_VERSION);
    if (Services.vc.compare(zoteroVersion, CONFIG.MAX_ZOTERO_VERSION) > 0) {
        Zotero.debug('perf_probe: Zotero ' + zoteroVersion + ' above tested ceiling '
            + CONFIG.MAX_ZOTERO_VERSION + '; confirm APIs and bump.');
    }
}

assert(CONFIG.I_UNDERSTAND_THIS_WRITES === true,
    'this probe writes and then deletes real tags; set CONFIG.I_UNDERSTAND_THIS_WRITES = true '
    + 'and run it on a SCRATCH / COPIED library, not your real one');

// Track every item we touch so cleanup can remove PROBE_TAG from exactly those,
// regardless of which phase (P1 or P2) added it or whether a phase threw.
var touchedItemIDs = new Set();

try {
    // ---- Build the candidate set: top-level regular items, same view the ----
    // ---- normalizer uses (isNot attachment/note/annotation). ----
    var search = new Zotero.Search();
    search.libraryID = userLibraryID;
    search.addCondition('itemType', 'isNot', 'attachment');
    search.addCondition('itemType', 'isNot', 'note');
    search.addCondition('itemType', 'isNot', 'annotation');
    var candidateIDs = await search.search();
    assert(candidateIDs.length >= (CONFIG.P1_SAMPLE_SIZE + 3),
        'library has ' + candidateIDs.length + ' top-level items; need at least '
        + (CONFIG.P1_SAMPLE_SIZE + 3) + ' (P1 sample + 3 P2 items)');

    // First P1_SAMPLE_SIZE for timing; next 3 reserved for P2 (a),(b),(c).
    var p1IDs = candidateIDs.slice(0, CONFIG.P1_SAMPLE_SIZE);
    var p2IDs = candidateIDs.slice(CONFIG.P1_SAMPLE_SIZE, CONFIG.P1_SAMPLE_SIZE + 3);

    var p1Items = await Zotero.Items.getAsync(p1IDs);

    // =========================================================================
    // P1: time saveTx over N items. Window wraps ONLY the save.
    // =========================================================================
    var saveTxTimings = [];
    for (var i = 0; i < p1Items.length; i = i + 1) {
        var item = p1Items[i];
        // Guarantee a real modify: PROBE_TAG is unique, so it is never already
        // present. If somehow present (impossible), skip so we never time a no-op.
        if (item.hasTag(PROBE_TAG)) { continue; }
        item.addTag(PROBE_TAG);
        touchedItemIDs.add(item.id);

        var t0 = Date.now();
        await item.saveTx();
        var elapsed = Date.now() - t0;

        saveTxTimings.push(elapsed);
        if ((i + 1) % CONFIG.P1_LOG_EVERY === 0) {
            Zotero.debug('perf_probe P1: ' + (i + 1) + ' saves timed, last=' + elapsed + 'ms');
        }
    }
    saveTxTimings.sort(function (a, b) { return a - b; });
    report.p1.sampleTimed = saveTxTimings.length;
    report.p1.saveTxMs.median = percentile(saveTxTimings, 0.50);
    report.p1.saveTxMs.p90 = percentile(saveTxTimings, 0.90);
    report.p1.saveTxMs.min = saveTxTimings.length ? saveTxTimings[0] : null;
    report.p1.saveTxMs.max = saveTxTimings.length ? saveTxTimings[saveTxTimings.length - 1] : null;

    // ---- Optional: suppressed-notifier timing, ONLY if the batch API exists. -
    // Independent of P1's primary datum so P1 always yields a number.
    var hasNotifierBatch = (typeof Zotero.Notifier !== 'undefined'
        && typeof Zotero.Notifier.begin === 'function'
        && typeof Zotero.Notifier.end === 'function');
    report.p1.notifierApiPresent = hasNotifierBatch;

    if (hasNotifierBatch) {
        // Re-save the same items inside a begin/end window with a SECOND unique
        // tag so each is again a real modify. Suppressed cascade -> the delta
        // vs saveTxMs isolates notifier cost.
        var suppressedTag = PROBE_TAG + '_s';
        var suppressedTimings = [];
        Zotero.Notifier.begin();
        try {
            for (var si = 0; si < p1Items.length; si = si + 1) {
                var sItem = p1Items[si];
                if (sItem.hasTag(suppressedTag)) { continue; }
                sItem.addTag(suppressedTag);
                touchedItemIDs.add(sItem.id);   // cleanup handles both tags per item
                var st0 = Date.now();
                await sItem.saveTx();
                suppressedTimings.push(Date.now() - st0);
            }
        } finally {
            Zotero.Notifier.end();   // single batched flush; also un-suppresses
        }
        suppressedTimings.sort(function (a, b) { return a - b; });
        report.p1.suppressedSaveMs.median = percentile(suppressedTimings, 0.50);
        report.p1.suppressedSaveMs.p90 = percentile(suppressedTimings, 0.90);
        report.p1.suppressedSaveMs.min = suppressedTimings.length ? suppressedTimings[0] : null;
        report.p1.suppressedSaveMs.max = suppressedTimings.length
            ? suppressedTimings[suppressedTimings.length - 1] : null;
        // Remember the suppressed tag for cleanup.
        report.p1._suppressedTag = suppressedTag;
    }

    // ---- P1 verdict (printed before P2 runs). -------------------------------
    var med = report.p1.saveTxMs.median;
    if (hasNotifierBatch && report.p1.suppressedSaveMs.median !== null) {
        var supMed = report.p1.suppressedSaveMs.median;
        var drop = med > 0 ? (1 - supMed / med) : 0;
        if (drop >= 0.5) {
            report.p1.verdict = 'NOTIFIER-DOMINATED: suppressing the cascade cut median from '
                + med + 'ms to ' + supMed + 'ms (' + Math.round(drop * 100) + '% drop). '
                + 'M2 (notifier batching) is the real fix; M1 alone will barely move the number.';
        } else {
            report.p1.verdict = 'TRANSACTION-DOMINATED: suppressing the notifier only moved median '
                + med + 'ms -> ' + supMed + 'ms. The cost is the transaction boundary; '
                + 'M1 (single executeTransaction) is the fix.';
        }
    } else {
        report.p1.verdict = 'saveTx median=' + med + 'ms, p90=' + report.p1.saveTxMs.p90
            + 'ms. Notifier batch API absent, so notifier cost was not isolated here. '
            + 'If median is ~500ms the cost is transaction+notifier combined; run P3 '
            + '(observer-level timing) to split them. If median is a few ms, the 504ms/item '
            + 'attribution is wrong and lives elsewhere.';
    }

    Zotero.debug('=== perf_probe P1 RESULT ===');
    Zotero.debug('saveTx ms  median=' + report.p1.saveTxMs.median
        + '  p90=' + report.p1.saveTxMs.p90
        + '  min=' + report.p1.saveTxMs.min
        + '  max=' + report.p1.saveTxMs.max
        + '  (n=' + report.p1.sampleTimed + ')');
    if (hasNotifierBatch) {
        Zotero.debug('suppressed ms  median=' + report.p1.suppressedSaveMs.median
            + '  p90=' + report.p1.suppressedSaveMs.p90);
    }
    Zotero.debug('VERDICT: ' + report.p1.verdict);

    // =========================================================================
    // P2: three isolated semantic checks, each on its own item. Runs AFTER P1
    // is printed, so a throw here never costs the P1 numbers.
    // =========================================================================
    var tagA = PROBE_TAG + '_a';
    var tagB = PROBE_TAG + '_b';
    var tagC = PROBE_TAG + '_c';

    // (a) does item.save() inside executeTransaction join the open txn?
    try {
        var itemA = await Zotero.Items.getAsync(p2IDs[0]);
        touchedItemIDs.add(itemA.id);
        await Zotero.DB.executeTransaction(async function () {
            itemA.addTag(tagA);
            await itemA.save();      // joins outer txn; must not throw/nest
        });
        report.p2.saveJoinsTransaction = true;
        report.p2.notes.push('(a) item.save() inside executeTransaction did not throw.');
    } catch (errA) {
        report.p2.saveJoinsTransaction = false;
        report.p2.notes.push('(a) FAILED: ' + errA.message + ' -- M1/M3 not viable as written.');
    }

    // (b) after commit, does a FRESHLY re-fetched item report the tag?
    // Re-fetch is the point: it proves the tag reached the DB, not just memory.
    try {
        var itemB = await Zotero.Items.getAsync(p2IDs[1]);
        touchedItemIDs.add(itemB.id);
        await Zotero.DB.executeTransaction(async function () {
            itemB.addTag(tagB);
            await itemB.save();
        });
        var refetchedB = await Zotero.Items.getAsync(p2IDs[1]);
        report.p2.tagPersistsAfterCommit = refetchedB.hasTag(tagB);
        report.p2.notes.push('(b) re-fetched item hasTag(committed) = '
            + report.p2.tagPersistsAfterCommit
            + (report.p2.tagPersistsAfterCommit
                ? ' -- M4 free in-memory verify is sound.'
                : ' -- M4 CANNOT rely on in-memory verify; a re-fetch would be required.'));
    } catch (errB) {
        report.p2.tagPersistsAfterCommit = false;
        report.p2.notes.push('(b) FAILED: ' + errB.message);
    }

    // (c) does a throw inside executeTransaction roll back the whole txn?
    // Add the tag then throw; afterward a re-fetch must NOT have the tag.
    try {
        var itemC = await Zotero.Items.getAsync(p2IDs[2]);
        touchedItemIDs.add(itemC.id);   // in case rollback fails and it persists
        var sentinel = 'perf_probe_intentional_rollback';
        try {
            await Zotero.DB.executeTransaction(async function () {
                itemC.addTag(tagC);
                await itemC.save();
                throw new Error(sentinel);   // force rollback
            });
        } catch (inner) {
            if (inner.message !== sentinel) { throw inner; }  // real error, re-raise
        }
        var refetchedC = await Zotero.Items.getAsync(p2IDs[2]);
        var rolledBack = !refetchedC.hasTag(tagC);
        report.p2.throwRollsBackWholeTxn = rolledBack;
        report.p2.notes.push('(c) after intentional throw, re-fetched item hasTag = '
            + refetchedC.hasTag(tagC) + ' -> rollback '
            + (rolledBack ? 'CONFIRMED -- M4 all-or-nothing failure model holds.'
                          : 'DID NOT occur -- batch failure model is wrong; M3/M4 need rework.'));
        if (rolledBack) { touchedItemIDs.delete(itemC.id); }  // nothing persisted to clean
    } catch (errC) {
        report.p2.throwRollsBackWholeTxn = null;
        report.p2.notes.push('(c) INCONCLUSIVE: ' + errC.message);
    }

    Zotero.debug('=== perf_probe P2 RESULT ===');
    for (var ni = 0; ni < report.p2.notes.length; ni = ni + 1) {
        Zotero.debug(report.p2.notes[ni]);
    }

} finally {
    // =========================================================================
    // CLEANUP (untimed): remove every probe tag from every item we touched.
    // Runs even if a phase threw. Deletes ONLY tags that start with PROBE_TAG,
    // so nothing real is ever removed.
    // =========================================================================
    var touchedList = Array.from(touchedItemIDs);
    for (var ci = 0; ci < touchedList.length; ci = ci + 1) {
        try {
            var cleanupItem = await Zotero.Items.getAsync(touchedList[ci]);
            var tags = cleanupItem.getTags();   // [{tag, type}]
            var removedAny = false;
            for (var ti = 0; ti < tags.length; ti = ti + 1) {
                if (tags[ti].tag.indexOf(PROBE_TAG) === 0) {   // PROBE_TAG-prefixed only
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
    Zotero.debug('perf_probe cleanup: removed ' + report.cleanup.tagRemoved
        + ' probe tag(s) from ' + report.cleanup.itemsTouched + ' item(s); '
        + report.cleanup.failures.length + ' cleanup failure(s).');
    if (report.cleanup.failures.length > 0) {
        Zotero.debug('perf_probe cleanup failures (remove tags starting "' + PROBE_TAG
            + '" manually): ' + JSON.stringify(report.cleanup.failures.slice(0, 20)));
    }
}

return report;
