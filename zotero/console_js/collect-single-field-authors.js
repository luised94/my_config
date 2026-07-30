// =============================================================================
// COLLECT SINGLE-FIELD (BLOCK) CREATOR NAMES
// =============================================================================
// Version: 1.0.0
// Date:    2026-07
// Purpose: Gather top-level items that have at least one creator stored in
//          SINGLE-FIELD mode (fieldMode = 1) -- the whole name in one block --
//          into a dated collection for manual review, versus the normal
//          two-field first/last name (fieldMode = 0).
//
// Usage:   Tools > Developer > Run JavaScript.
//          CHECK THE "Run as async function" CHECKBOX.
//          Runs in DRY_RUN by default: reports what it would create and add,
//          writes nothing. Set CONFIG.DRY_RUN = false to create + add.
//
// CAVEAT:  fieldMode = 1 is ALSO the correct way to store organizational
//          authors ("World Health Organization"). This script cannot tell a
//          mis-entered person from a legitimate institution; it surfaces
//          candidates for a human to judge. The report echoes the actual
//          names so you can scan them.
//
// Scope:   ONLY_AUTHOR_TYPE (default false) restricts to the "author" creator
//          type; false catches every creator type (editor, contributor, ...).
//
// Membership: collections hold top-level items. Items that carry creators are
//          regular items and are top-level, but a guard skips anything that
//          somehow isn't. De-duplicated (an item can have several block
//          creators).
//
// Reversibility: the only write is collection membership. Delete the
//          collection to undo; no item data is ever modified.
// =============================================================================

// 1. CONFIGURATION
var CONFIG = {
    DRY_RUN: true,                       // false = create collection + add items
    COLLECTION_PREFIX: 'Single-field creators',   // dated: "... 2026-07-29"
    ONLY_AUTHOR_TYPE: false,             // true = only creatorType "author"

    YIELD_EVERY_ITEMS: 2000,
    DELAY_MS: 15,
    REPORT_SAMPLE_MAX: 200,

    MIN_ZOTERO_VERSION: '7.0',
    MAX_ZOTERO_VERSION: '9.0.6',
    BYPASS_VERSION_CHECK: false
};

// 2. STATE
var timing = {
    scriptStart: Date.now(),
    assertions: 0,
    scanMs: 0,
    writeMs: 0,
    yieldCount: 0,
    creatorRows: 0,
    blockCreators: 0,
    skippedNonTopLevel: 0
};
var blockEntries = [];          // { itemID, name, creatorTypeID }
var blockItemIDs = new Set();
var debugLines = [];

// 3. HELPERS
function report(line) {
    debugLines.push(line);
    Zotero.debug(`[block_creators] ${line}`);
}
function assert(condition, message) {
    timing.assertions = timing.assertions + 1;
    if (!condition) {
        throw new Error(`collect_block_creators pre-flight failed: ${message}`);
    }
}
async function yieldToEventLoop() {
    timing.yieldCount = timing.yieldCount + 1;
    await new Promise(resolve => setTimeout(resolve, CONFIG.DELAY_MS));
}

try {

// 4. PRE-FLIGHT
report(`version 1.0.0 starting, Zotero ${Zotero.version}, DRY_RUN=${CONFIG.DRY_RUN}`);
var belowMin = Services.vc.compare(Zotero.version, CONFIG.MIN_ZOTERO_VERSION) < 0;
var aboveMax = Services.vc.compare(Zotero.version, CONFIG.MAX_ZOTERO_VERSION) > 0;
if ((belowMin || aboveMax) && !CONFIG.BYPASS_VERSION_CHECK) {
    throw new Error(`Zotero ${Zotero.version} outside tested range ` +
        `${CONFIG.MIN_ZOTERO_VERSION}..${CONFIG.MAX_ZOTERO_VERSION}. ` +
        `Set CONFIG.BYPASS_VERSION_CHECK = true to override.`);
}
assert(typeof Zotero.DB.queryAsync === 'function', 'Zotero.DB.queryAsync unavailable');
assert(typeof Zotero.DB.executeTransaction === 'function',
    'Zotero.DB.executeTransaction unavailable');
assert(typeof Zotero.Items.getAsync === 'function', 'Zotero.Items.getAsync unavailable');
assert(typeof Zotero.Collection === 'function', 'Zotero.Collection unavailable');

var userLibraryID = Zotero.Libraries.userLibraryID;
assert(typeof userLibraryID === 'number', 'Zotero.Libraries.userLibraryID unavailable');

var authorTypeID = null;
if (CONFIG.ONLY_AUTHOR_TYPE) {
    authorTypeID = Zotero.CreatorTypes.getID('author');
    assert(typeof authorTypeID === 'number', 'could not resolve "author" creatorTypeID');
    report(`restricting to author creatorTypeID ${authorTypeID}`);
}

// 5. MAIN
// --- 5a. Scan single-field creators ------------------------------------------
var scanStart = Date.now();
var sql =
    'SELECT ic.itemID AS itemID, c.lastName AS lastName, c.firstName AS firstName, ' +
    '       ic.creatorTypeID AS creatorTypeID ' +
    'FROM itemCreators ic ' +
    'JOIN creators c ON ic.creatorID = c.creatorID ' +
    'JOIN items i ON ic.itemID = i.itemID ' +
    'LEFT JOIN deletedItems di ON di.itemID = ic.itemID ' +
    'WHERE c.fieldMode = 1 AND i.libraryID = ? AND di.itemID IS NULL ' +
    (CONFIG.ONLY_AUTHOR_TYPE ? 'AND ic.creatorTypeID = ? ' : '') +
    'ORDER BY ic.itemID';
var params = CONFIG.ONLY_AUTHOR_TYPE ? [userLibraryID, authorTypeID] : [userLibraryID];
var rows = await Zotero.DB.queryAsync(sql, params);
report(`found ${rows.length} single-field creator row(s)`);

var since = 0;
for (var row of rows) {
    timing.creatorRows = timing.creatorRows + 1;
    timing.blockCreators = timing.blockCreators + 1;
    // In single-field mode the whole name lives in lastName.
    var name = row.lastName || row.firstName || '(empty)';
    blockItemIDs.add(row.itemID);
    if (blockEntries.length < CONFIG.REPORT_SAMPLE_MAX) {
        blockEntries.push({ itemID: row.itemID, name: name,
            creatorTypeID: row.creatorTypeID });
    }
    since = since + 1;
    if (since >= CONFIG.YIELD_EVERY_ITEMS) { since = 0; await yieldToEventLoop(); }
}
timing.scanMs = Date.now() - scanStart;

// Guard: keep only genuine top-level items (should be all of them).
var candidateIDs = Array.from(blockItemIDs);
var collectableIDs = [];
for (var cid of candidateIDs) {
    var it = await Zotero.Items.getAsync(cid);
    if (it && it.isTopLevelItem && it.isTopLevelItem()) {
        collectableIDs.push(cid);
    } else {
        timing.skippedNonTopLevel = timing.skippedNonTopLevel + 1;
    }
}
report(`scan done: ${timing.blockCreators} block creator(s) across ` +
    `${candidateIDs.length} item(s), ${collectableIDs.length} collectable, ` +
    `${timing.skippedNonTopLevel} skipped (not top-level), ${timing.scanMs} ms`);

// --- 5b. Plan ----------------------------------------------------------------
var now = new Date();
var pad2 = function (n) { return String(n).padStart(2, '0'); };
var dateStamp = `${now.getFullYear()}-${pad2(now.getMonth() + 1)}-${pad2(now.getDate())}`;
var collectionName = `${CONFIG.COLLECTION_PREFIX} ${dateStamp}`;

report('PLAN:');
report(`  collection "${collectionName}" <- ${collectableIDs.length} item(s)`);
report('  writes: collection membership only. No creator or item data is modified.');

var collectionID = null;
if (CONFIG.DRY_RUN) {
    report('DRY_RUN: nothing created, nothing added. ' +
        'Set CONFIG.DRY_RUN = false to apply the plan above.');
} else {
    var writeStart = Date.now();
    if (collectableIDs.length > 0) {
        var collection = new Zotero.Collection();
        collection.libraryID = userLibraryID;
        collection.name = collectionName;
        collectionID = await collection.saveTx();
        report(`created collection "${collectionName}" (id ${collectionID})`);

        await Zotero.DB.executeTransaction(async function () {
            for (var id of collectableIDs) {
                var item = await Zotero.Items.getAsync(id);
                item.addToCollection(collectionID);
                await item.save();
            }
        });
    } else {
        report('no collectable items; collection not created');
    }
    timing.writeMs = Date.now() - writeStart;
    report(`writes done in ${timing.writeMs} ms`);
    report('To undo: delete the collection. Deleting a collection does not ' +
        'delete the items in it.');
}

} catch (e) {
    Zotero.debug(`[block_creators] ERROR: ${e.message}\n${e.stack}`);
    throw e;
}

// 6. SUMMARY
timing.totalMs = Date.now() - timing.scriptStart;
report(`done in ${timing.totalMs} ms, assertions ${timing.assertions}, ` +
    `yields ${timing.yieldCount}`);
return {
    dryRun: CONFIG.DRY_RUN,
    onlyAuthorType: CONFIG.ONLY_AUTHOR_TYPE,
    blockCreatorRows: timing.blockCreators,
    itemsWithBlockCreator: Array.from(blockItemIDs).length,
    skippedNonTopLevel: timing.skippedNonTopLevel,
    collectionName: collectionName,
    collectionID: collectionID,
    sample: blockEntries,
    timing: timing
};
