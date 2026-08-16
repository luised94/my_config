// =============================================================================
// MIGRATE /unread -> __unopened  (ONE-TIME)
// =============================================================================
// Version: 1.0.0
// Date:    2026-08-12
// Thread:  3 (incoming-item automation). ONE-TIME migration, not recurring.
// Status:  owner action. Run AFTER diagnose_thread3_tag_state.js (which sizes
//          it) and BEFORE the first normalize_items.js pass. Sequencing is not
//          load-bearing against the normalizer here (the normalizer would also
//          add __unopened to the clean /unread items), but running migrations
//          before the normalizer keeps the "tags-first, normalizer-last" order
//          the thread-3 plan fixes.
//
// Purpose: Replace the legacy "/unread" tag (leading slash, predates the "__"
//          convention) with __unopened. Diagnosed 2026-08-12: 86 top-level
//          items carry /unread; 84 are "clean" (no current reading-state tag)
//          and 2 are contradictions (also carry __read or __in_progress).
//
// What it does, per item carrying /unread:
//   - CLEAN (no __read and no __in_progress): remove /unread, and add
//     __unopened if the item does not already have it (13 of the 84 already
//     do -- benign, the add is skipped for those). This is the migration.
//   - CONTRADICTION (also __read or __in_progress): remove /unread, add
//     NOTHING. The current reading-state tag is authoritative (CONVENTIONS
//     B1: tags win), so the item keeps its real state; only the dead legacy
//     tag goes. There are 2 such items (99870 __in_progress, 100614 __read).
//   Every touched item is also added to a dated review collection so the run
//   is inspectable and reversible at the collection level.
//
// Why removing is safe here even though the thread-3 normalizer is strictly
// additive: this is a one-time migration, not the recurring normalizer. The
// normalizer's "never remove" guarantee is what lets it run blind on a
// cadence; a migration runs once, under DRY_RUN review, with a backup
// collection, so a scoped removal is appropriate. (An earlier abandoned
// script, convert_readstatus_to_tags.js, drafted the same "replace __unopened"
// idea but left every write commented out and never ran; this completes that
// intent with detect-then-write discipline -- CONVENTIONS D2.)
//
// Usage:   Tools > Developer > Run JavaScript. CHECK "Run as async function".
//          DRY_RUN is true by default: it prints the full plan and writes
//          nothing. Read the plan, then set CONFIG.DRY_RUN = false to apply.
//          Idempotent: re-running after a successful apply finds no /unread
//          tags and no-ops (CONVENTIONS A7).
//
// Reversibility: deleting the dated review collection undoes the audit trail
//          but NOT the tag changes (deleting a collection does not touch item
//          tags). To fully reverse, the collection lists exactly which items
//          were touched; /unread can be re-added and __unopened removed from
//          that set by hand. The tag changes are small (86 items) and printed
//          in full in the plan, so a manual reversal is tractable. This is the
//          one place a stronger backup would matter; given the tiny scope and
//          the printed plan, the collection is the accepted backup.
//
// Write strategy (S4 defence-in-depth): each item's tag change is saved with
//          saveTx, then re-fetched and verified; on a verification miss the
//          save is retried once. On settled items (not mid-import) loss is not
//          expected, so this is a safety net, not a load-bearing gate -- but
//          it is cheap and the S4 findings say awaited saves CAN be lost, so
//          it stays. Collection membership is written separately, batched.
// =============================================================================

// 1. CONFIGURATION
var CONFIG = {
    DRY_RUN: true,                        // false = apply. Read the plan first.

    LEGACY_UNREAD_TAG: '/unread',
    UNOPENED_TAG: '__unopened',

    // Tags whose presence makes an item a CONTRADICTION: remove /unread but add
    // nothing, because the item has a real reading state that wins. Matches the
    // diagnostic's contradiction set.
    CONTRADICTION_TAGS: ['__read', '__in_progress'],

    COLLECTION_PREFIX: 'unread migration',  // dated: "unread migration 2026-08-12"

    // Write-verify-retry (S4). RETRY_BACKOFF_MS then RETRY_SETTLE_MS mirror the
    // ~1.2s recovery S4 measured; kept though loss is not expected on settled
    // items.
    RETRY_BACKOFF_MS: 800,
    RETRY_SETTLE_MS: 400,

    // Scale: the population is tiny (86), so batching is a formality, but the
    // load path is the same getAsync-in-batches used elsewhere (never getAll).
    LOAD_BATCH_SIZE: 100,

    MIN_ZOTERO_VERSION: '7.0',
    MAX_ZOTERO_VERSION: '9.0.6',
    BYPASS_VERSION_CHECK: false
};

// 2. STATE
var timing = { scriptStart: Date.now(), assertions: 0, writeMs: 0 };
var result = {
    dryRun: CONFIG.DRY_RUN,
    totalUnread: 0,
    planCleanAddUnopened: [],    // itemIDs: remove /unread, add __unopened
    planCleanAlreadyUnopened: [],// itemIDs: remove /unread, __unopened already present
    planContradiction: [],       // { itemID, keepsTag }: remove /unread, add nothing
    applied: {
        unreadRemoved: 0,
        unopenedAdded: 0,
        verifyRetries: 0,
        verifyFailuresAfterRetry: [],   // itemIDs that failed verification even after retry
        addedToCollection: 0,
        collectionName: null,
        collectionID: null
    }
};

// 3. HELPERS
function assert(condition, message) {
    timing.assertions = timing.assertions + 1;
    if (!condition) {
        throw new Error(`migrate_slash_unread pre-flight failed: ${message}`);
    }
}

// Save an item's pending tag changes, then verify the end state. saveTx()
// updates the in-memory item synchronously (repo idiom: mark-as-read /
// tag-google-books read fields off the same object right after saveTx), so the
// common-path verify is against `item` itself -- free. Do NOT re-fetch per
// item: getAsync triggers a full itemData load, and doing that on every item
// is what made the reconcile run take hours (2026-08-12). The rare failure
// path re-fetches with getAsync and re-applies (S4: re-applying, not just
// re-saving, is what recovers a lost write). expectedPresent / expectedAbsent
// are tag-name arrays. Returns true if verified.
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

    if (verifyInMemory(item)) { return true; }

    // Rare miss (expected: zero). Re-fetch, re-apply, save, settle, verify.
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
        Zotero.debug(`migrate_slash_unread: Zotero ${zoteroVersion} above tested ceiling ${CONFIG.MAX_ZOTERO_VERSION}; confirm and bump.`);
    }
}

// 5. MAIN
try {
    // Resolve the /unread population (top-level, name-match).
    var search = new Zotero.Search();
    search.libraryID = userLibraryID;
    search.addCondition('noChildren', 'true');
    search.addCondition('tag', 'is', CONFIG.LEGACY_UNREAD_TAG);
    var unreadIDs = await search.search();
    result.totalUnread = unreadIDs.length;

    // Load in batches (never getAll) and classify each item.
    var unreadItems = [];
    for (var start = 0; start < unreadIDs.length; start = start + CONFIG.LOAD_BATCH_SIZE) {
        var batch = await Zotero.Items.getAsync(unreadIDs.slice(start, start + CONFIG.LOAD_BATCH_SIZE));
        for (var bi = 0; bi < batch.length; bi = bi + 1) { unreadItems.push(batch[bi]); }
    }

    for (var ui = 0; ui < unreadItems.length; ui = ui + 1) {
        var item = unreadItems[ui];
        var contradictionTagPresent = null;
        for (var ci = 0; ci < CONFIG.CONTRADICTION_TAGS.length; ci = ci + 1) {
            if (item.hasTag(CONFIG.CONTRADICTION_TAGS[ci])) {
                contradictionTagPresent = CONFIG.CONTRADICTION_TAGS[ci];
                break;
            }
        }
        if (contradictionTagPresent !== null) {
            result.planContradiction.push({ itemID: item.id, keepsTag: contradictionTagPresent });
        } else if (item.hasTag(CONFIG.UNOPENED_TAG)) {
            result.planCleanAlreadyUnopened.push(item.id);
        } else {
            result.planCleanAddUnopened.push(item.id);
        }
    }

    // --- Plan (printed before any write, A4) ---
    var now = new Date();
    var pad2 = function (n) { return String(n).padStart(2, '0'); };
    var dateStamp = `${now.getFullYear()}-${pad2(now.getMonth() + 1)}-${pad2(now.getDate())}`;
    var collectionName = `${CONFIG.COLLECTION_PREFIX} ${dateStamp}`;
    result.applied.collectionName = collectionName;

    var plan = [];
    plan.push('=== migrate_slash_unread PLAN ===');
    plan.push(`/unread items found: ${result.totalUnread}`);
    plan.push(`  clean, will remove /unread and ADD __unopened: ${result.planCleanAddUnopened.length}`);
    plan.push(`  clean, will remove /unread (__unopened already present): ${result.planCleanAlreadyUnopened.length}`);
    plan.push(`  contradiction, will remove /unread and add NOTHING: ${result.planContradiction.length}`);
    for (var pc = 0; pc < result.planContradiction.length; pc = pc + 1) {
        plan.push(`    [${result.planContradiction[pc].itemID}] keeps ${result.planContradiction[pc].keepsTag}`);
    }
    plan.push(`  all ${result.totalUnread} touched items -> collection "${collectionName}"`);
    plan.push('  writes: tag changes (remove /unread; add __unopened where noted) + collection membership.');
    for (var pl = 0; pl < plan.length; pl = pl + 1) { Zotero.debug(plan[pl]); }

    if (CONFIG.DRY_RUN) {
        Zotero.debug('DRY_RUN: nothing written. Set CONFIG.DRY_RUN = false to apply the plan above.');
    } else {
        var writeStart = Date.now();

        // Tag changes first, per item, with verify-retry. Not batched into one
        // transaction because verify-retry needs a settled, re-fetchable state
        // between save and check.
        var touchedIDs = [];

        for (var ai2 = 0; ai2 < result.planCleanAddUnopened.length; ai2 = ai2 + 1) {
            var addItem = await Zotero.Items.getAsync(result.planCleanAddUnopened[ai2]);
            addItem.removeTag(CONFIG.LEGACY_UNREAD_TAG);
            addItem.addTag(CONFIG.UNOPENED_TAG);
            var okAdd = await saveVerifyRetry(addItem, [CONFIG.UNOPENED_TAG], [CONFIG.LEGACY_UNREAD_TAG]);
            if (okAdd) {
                result.applied.unreadRemoved = result.applied.unreadRemoved + 1;
                result.applied.unopenedAdded = result.applied.unopenedAdded + 1;
            } else {
                result.applied.verifyFailuresAfterRetry.push(addItem.id);
            }
            touchedIDs.push(addItem.id);
        }

        for (var al = 0; al < result.planCleanAlreadyUnopened.length; al = al + 1) {
            var alreadyItem = await Zotero.Items.getAsync(result.planCleanAlreadyUnopened[al]);
            alreadyItem.removeTag(CONFIG.LEGACY_UNREAD_TAG);
            var okAlready = await saveVerifyRetry(alreadyItem, [CONFIG.UNOPENED_TAG], [CONFIG.LEGACY_UNREAD_TAG]);
            if (okAlready) {
                result.applied.unreadRemoved = result.applied.unreadRemoved + 1;
            } else {
                result.applied.verifyFailuresAfterRetry.push(alreadyItem.id);
            }
            touchedIDs.push(alreadyItem.id);
        }

        for (var co = 0; co < result.planContradiction.length; co = co + 1) {
            var contraItem = await Zotero.Items.getAsync(result.planContradiction[co].itemID);
            contraItem.removeTag(CONFIG.LEGACY_UNREAD_TAG);
            var okContra = await saveVerifyRetry(contraItem, [result.planContradiction[co].keepsTag], [CONFIG.LEGACY_UNREAD_TAG]);
            if (okContra) {
                result.applied.unreadRemoved = result.applied.unreadRemoved + 1;
            } else {
                result.applied.verifyFailuresAfterRetry.push(contraItem.id);
            }
            touchedIDs.push(contraItem.id);
        }

        // Review collection: create, then batch membership into one transaction
        // (membership has no lost-write concern, so the collect_broken_links
        // batching pattern applies here).
        if (touchedIDs.length > 0) {
            var collection = new Zotero.Collection();
            collection.libraryID = userLibraryID;
            collection.name = collectionName;
            result.applied.collectionID = await collection.saveTx();
            await Zotero.DB.executeTransaction(async function () {
                for (var ti = 0; ti < touchedIDs.length; ti = ti + 1) {
                    var collItem = await Zotero.Items.getAsync(touchedIDs[ti]);
                    collItem.addToCollection(result.applied.collectionID);
                    await collItem.save();
                }
            });
            result.applied.addedToCollection = touchedIDs.length;
        }

        timing.writeMs = Date.now() - writeStart;
        Zotero.debug(`migrate_slash_unread: writes done in ${timing.writeMs} ms`);
        Zotero.debug(`To review: open collection "${collectionName}". To reverse: re-add /unread and remove __unopened on those items (tag changes are not undone by deleting the collection).`);
        if (result.applied.verifyFailuresAfterRetry.length > 0) {
            Zotero.debug(`WARNING: ${result.applied.verifyFailuresAfterRetry.length} item(s) failed verification even after retry: ${result.applied.verifyFailuresAfterRetry.join(', ')}. Re-run to reconcile.`);
        }
    }
} catch (error) {
    Zotero.debug(`migrate_slash_unread FAILED: ${error.message}\n${error.stack}`);
    throw error;
}

// 6. SUMMARY
timing.totalMs = Date.now() - timing.scriptStart;
result.timing = timing;
Zotero.debug(`migrate_slash_unread done in ${timing.totalMs} ms (dryRun=${CONFIG.DRY_RUN}, assertions=${timing.assertions})`);
return result;
