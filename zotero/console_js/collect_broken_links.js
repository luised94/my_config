// =============================================================================
// COLLECT BROKEN LINKS
// =============================================================================
// Version: 1.0.0
// Date:    2026-07
// Purpose: Gather items whose linked attachment file cannot be found into a
//          dated collection, so they are clickable and repairable through
//          Zotero's own relink UI. Companion to
//          audit_orphan_attachments.js: the auditor REPORTS broken links,
//          this script SURFACES them for manual repair. It never repairs
//          anything itself.
//
// Usage:   Tools > Developer > Run JavaScript.
//          CHECK THE "Run as async function" CHECKBOX (A10.2).
//          Runs in DRY_RUN by default: it reports what it would create and
//          add, and writes nothing. Set CONFIG.DRY_RUN = false to create
//          the collection(s) and add items.
//
// Two populations, two collections (owner decision, 2026-07):
//   - MISSING: the reconstructed path is under the current base but the
//     file is not on disk. Fix = relink / locate the file per item.
//   - STALE:   the stored path is absolute and NOT under the current base
//     (cross-machine or historical base). Fix = re-relativize the path
//     (adjust_attachment_paths.js), NOT relinking. Different workflow, so
//     a separate collection; set CONFIG.INCLUDE_STALE = false to skip.
//
// Membership: Zotero collections hold TOP-LEVEL items only -- a child
//          attachment cannot be added directly, so the attachment's PARENT
//          item is added. Parents are de-duplicated (several broken
//          attachments can share one parent). Standalone linked-file
//          attachments (no parent) CANNOT be collected; they are counted
//          and listed in the report rather than silently dropped. The
//          2026-07 audit found 0 standalone linked-file attachments, so
//          any nonzero count here is new and worth a look.
//
// Reversibility: the only write is collection membership. Deleting the
//          collection removes it; no item data, no file, and no attachment
//          path is ever modified. Deleting a collection in Zotero does not
//          delete the items in it.
//
// Report detail: each broken attachment is classified as
//          "parent folder missing" (the author folder itself is gone --
//          a whole folder moved or was removed) vs "file missing in an
//          existing folder" (a single file went away). These want
//          different repairs, so the distinction is logged.
//
// Scope:   Detection and surfacing only. Automatic repair -- fuzzy-matching
//          a broken link to a similarly named file on disk (some broken
//          links may have twins in the orphan quarantine) -- is explicitly
//          OUT OF SCOPE. Auto-relinking writes item data and deserves its
//          own detect-then-fix split.
//
// Scale:   The broken population is small (72 missing + 5 stale in the
//          2026-07 audit), but the scan is over every linked-file row
//          (~71k), so A5 yielding applies to the scan. Writes are batched
//          into ONE transaction (A10.7: one saveTx per item would be one
//          transaction per item).
// =============================================================================

// 1. CONFIGURATION
var CONFIG = {
    DRY_RUN: true,                // A4: report-only default. false = create + add.

    INCLUDE_STALE: true,          // second collection for stale-base rows
    COLLECTION_PREFIX: 'Broken links',       // dated: "Broken links 2026-07-29"
    STALE_COLLECTION_SUFFIX: 'stale base',   // "Broken links 2026-07-29 - stale base"

    BASE_PATH: '',                // '' = derive from the baseAttachmentPath pref

    // Cross-machine / historical base classification, mirroring
    // audit_orphan_attachments.js so both tools bucket the same way.
    STALE_BASE_SUFFIXES: [
        '\\MIT Dropbox\\Luis Martinez\\zotero-storage'
    ],
    HISTORICAL_BASES: [],

    // Scale treatment (A5). The existence check is the slow part.
    YIELD_EVERY_ROWS: 2000,
    DELAY_MS: 15,
    CHECKPOINT_EVERY: 10000,

    REPORT_SAMPLE_MAX: 100,       // broken entries echoed into the return value

    // Version guards (A3)
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
    linkedFileRows: 0,
    existing: 0,
    missing: 0,
    stale: 0,
    standaloneBroken: 0,
    parentFolderMissing: 0,
    fileMissingInExistingFolder: 0
};

var missingEntries = [];      // { attachmentItemID, parentItemID, path, detail }
var staleEntries = [];        // { attachmentItemID, parentItemID, storedPath, reason }
var standaloneEntries = [];   // { attachmentItemID, path, bucket }
var missingParentIDs = new Set();
var staleParentIDs = new Set();
var folderExistsCache = new Map();   // folder path -> boolean (avoids restatting author folders)
var debugLines = [];

// 3. HELPERS

function report(line) {
    debugLines.push(line);
    Zotero.debug(`[collect_broken] ${line}`);
}

function assert(condition, message) {
    timing.assertions = timing.assertions + 1;
    if (!condition) {
        throw new Error(`collect_broken_links pre-flight failed: ${message}`);
    }
}

// Comparison key only (never used as a filesystem target): unify
// separators, NFC, lowercase -- same fold as the auditor.
function normalizeKey(path) {
    return path.replace(/\//g, '\\').normalize('NFC').toLowerCase();
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
assert(typeof IOUtils !== 'undefined' && typeof IOUtils.exists === 'function',
    'IOUtils.exists unavailable (requires Zotero 7+)');
assert(typeof ''.normalize === 'function', 'String.prototype.normalize unavailable');

var linkedFileMode = Zotero.Attachments.LINK_MODE_LINKED_FILE;
assert(typeof linkedFileMode === 'number', 'LINK_MODE_LINKED_FILE constant unavailable');
var userLibraryID = Zotero.Libraries.userLibraryID;
assert(typeof userLibraryID === 'number', 'Zotero.Libraries.userLibraryID unavailable');

var basePath = CONFIG.BASE_PATH;
if (basePath === '') {
    basePath = Zotero.Prefs.get('baseAttachmentPath');
}
assert(typeof basePath === 'string' && basePath.length > 0,
    'No base path: set CONFIG.BASE_PATH or the linked attachment base directory pref');
if (basePath.endsWith('\\') || basePath.endsWith('/')) {
    basePath = basePath.slice(0, basePath.length - 1);
}
var baseExists = await IOUtils.exists(basePath);
assert(baseExists, `Base path does not exist: ${basePath}`);
var baseKey = normalizeKey(basePath);
report(`base path: ${basePath}`);

var historicalBaseKeys = [];
for (var hb of CONFIG.HISTORICAL_BASES) {
    historicalBaseKeys.push(normalizeKey(hb));
}
var staleSuffixKeys = [];
for (var ss of CONFIG.STALE_BASE_SUFFIXES) {
    staleSuffixKeys.push(normalizeKey(ss));
}

// 5. MAIN

// --- 5a. Scan every live linked-file attachment ------------------------------
var scanStart = Date.now();
var linkRows = await Zotero.DB.queryAsync(
    'SELECT ia.itemID AS attachmentItemID, ia.path AS storedPath, ' +
    '       ia.parentItemID AS parentItemID ' +
    'FROM itemAttachments ia ' +
    'JOIN items i ON ia.itemID = i.itemID ' +
    'LEFT JOIN deletedItems di ON di.itemID = ia.itemID ' +
    'WHERE ia.linkMode = ? AND i.libraryID = ? AND di.itemID IS NULL ' +
    'ORDER BY ia.itemID',
    [linkedFileMode, userLibraryID]);
report(`scanning ${linkRows.length} live linked-file attachments`);

var rowsSinceYield = 0;
for (var linkRow of linkRows) {
    timing.linkedFileRows = timing.linkedFileRows + 1;
    var storedPath = linkRow.storedPath;
    var absolutePath = null;
    var isStale = false;
    var staleReason = '';

    if (storedPath === null || storedPath === '') {
        isStale = true;
        staleReason = 'empty stored path';
        storedPath = String(storedPath);
    } else if (storedPath.startsWith('attachments:')) {
        absolutePath = basePath + '\\' +
            storedPath.slice('attachments:'.length).replace(/\//g, '\\');
    } else {
        // Absolute stored path: under the current base it compares normally;
        // otherwise it is stale (cross-machine or historical base).
        var storedKey = normalizeKey(storedPath);
        if (storedKey.startsWith(baseKey + '\\')) {
            absolutePath = storedPath;
        } else {
            isStale = true;
            var matchedSuffix = false;
            for (var suffixKey of staleSuffixKeys) {
                if (storedKey.indexOf(suffixKey + '\\') !== -1) {
                    matchedSuffix = true;
                    break;
                }
            }
            var matchedHistorical = false;
            for (var hbKey of historicalBaseKeys) {
                if (storedKey.startsWith(hbKey + '\\')) {
                    matchedHistorical = true;
                    break;
                }
            }
            if (matchedSuffix) {
                staleReason = 'absolute path under the shared base with a foreign ' +
                    'machine user prefix (fix: re-relativize)';
            } else if (matchedHistorical) {
                staleReason = 'absolute path under a known historical base (fix: re-relativize)';
            } else {
                staleReason = 'absolute path under an unknown base';
            }
        }
    }

    if (isStale) {
        timing.stale = timing.stale + 1;
        if (linkRow.parentItemID === null) {
            timing.standaloneBroken = timing.standaloneBroken + 1;
            standaloneEntries.push({ attachmentItemID: linkRow.attachmentItemID,
                path: storedPath, bucket: 'stale' });
        } else {
            staleParentIDs.add(linkRow.parentItemID);
        }
        staleEntries.push({ attachmentItemID: linkRow.attachmentItemID,
            parentItemID: linkRow.parentItemID, storedPath: storedPath,
            reason: staleReason });
    } else {
        var fileExists = await IOUtils.exists(absolutePath);
        if (fileExists) {
            timing.existing = timing.existing + 1;
        } else {
            timing.missing = timing.missing + 1;

            // Classify the failure: is the containing folder gone, or just
            // the file? Folder results are cached because many broken files
            // share one author folder.
            var lastSeparator = absolutePath.lastIndexOf('\\');
            var containingFolder = absolutePath.slice(0, lastSeparator);
            var folderPresent = folderExistsCache.get(containingFolder);
            if (folderPresent === undefined) {
                folderPresent = await IOUtils.exists(containingFolder);
                folderExistsCache.set(containingFolder, folderPresent);
            }
            var detail = '';
            if (folderPresent) {
                detail = 'file missing in an existing folder';
                timing.fileMissingInExistingFolder = timing.fileMissingInExistingFolder + 1;
            } else {
                detail = 'parent folder missing';
                timing.parentFolderMissing = timing.parentFolderMissing + 1;
            }

            if (linkRow.parentItemID === null) {
                timing.standaloneBroken = timing.standaloneBroken + 1;
                standaloneEntries.push({ attachmentItemID: linkRow.attachmentItemID,
                    path: absolutePath, bucket: 'missing' });
            } else {
                missingParentIDs.add(linkRow.parentItemID);
            }
            missingEntries.push({ attachmentItemID: linkRow.attachmentItemID,
                parentItemID: linkRow.parentItemID, path: absolutePath,
                detail: detail });
        }
    }

    rowsSinceYield = rowsSinceYield + 1;
    if (timing.linkedFileRows % CONFIG.CHECKPOINT_EVERY === 0) {
        report(`scan checkpoint: ${timing.linkedFileRows}/${linkRows.length} rows, ` +
            `${timing.missing} missing, ${timing.stale} stale`);
    }
    if (rowsSinceYield >= CONFIG.YIELD_EVERY_ROWS) {
        rowsSinceYield = 0;
        await yieldToEventLoop();
    }
}
timing.scanMs = Date.now() - scanStart;
report(`scan done: ${timing.existing} present, ${timing.missing} missing ` +
    `(${timing.parentFolderMissing} parent folder missing, ` +
    `${timing.fileMissingInExistingFolder} file missing in existing folder), ` +
    `${timing.stale} stale, ${timing.standaloneBroken} standalone (uncollectable), ` +
    `${timing.scanMs} ms`);

// Standalone attachments cannot be added to a collection. The 2026-07 audit
// found zero, so a nonzero count here is new information, not routine.
if (timing.standaloneBroken > 0) {
    report(`WARNING: ${timing.standaloneBroken} broken attachment(s) have no parent ` +
        'item and CANNOT be collected. They are listed in standaloneEntries below; ' +
        'repair them directly from the attachment.');
}

var missingParentList = Array.from(missingParentIDs);
var staleParentList = Array.from(staleParentIDs);
report(`collectable parents: ${missingParentList.length} missing, ` +
    `${staleParentList.length} stale`);

// --- 5b. Plan (printed before any write, A4) ---------------------------------
var now = new Date();
var pad2 = function (n) { return String(n).padStart(2, '0'); };
var dateStamp = `${now.getFullYear()}-${pad2(now.getMonth() + 1)}-${pad2(now.getDate())}`;
var missingCollectionName = `${CONFIG.COLLECTION_PREFIX} ${dateStamp}`;
var staleCollectionName = `${CONFIG.COLLECTION_PREFIX} ${dateStamp} - ` +
    `${CONFIG.STALE_COLLECTION_SUFFIX}`;

report('PLAN:');
report(`  collection "${missingCollectionName}" <- ${missingParentList.length} parent item(s)`);
if (CONFIG.INCLUDE_STALE) {
    report(`  collection "${staleCollectionName}" <- ${staleParentList.length} parent item(s)`);
} else {
    report('  stale collection skipped (CONFIG.INCLUDE_STALE = false)');
}
report('  writes: collection membership only. No item data, path, or file is modified.');

var missingCollectionID = null;
var staleCollectionID = null;

if (CONFIG.DRY_RUN) {
    report('DRY_RUN: nothing created, nothing added. ' +
        'Set CONFIG.DRY_RUN = false to apply the plan above.');
} else {
    var writeStart = Date.now();

    // Create the collection(s) first: saveTx outside the membership
    // transaction, because the collectionID is needed to add items.
    if (missingParentList.length > 0) {
        var missingCollection = new Zotero.Collection();
        missingCollection.libraryID = userLibraryID;
        missingCollection.name = missingCollectionName;
        missingCollectionID = await missingCollection.saveTx();
        report(`created collection "${missingCollectionName}" (id ${missingCollectionID})`);
    } else {
        report('no missing-link parents; missing collection not created');
    }

    if (CONFIG.INCLUDE_STALE && staleParentList.length > 0) {
        var staleCollection = new Zotero.Collection();
        staleCollection.libraryID = userLibraryID;
        staleCollection.name = staleCollectionName;
        staleCollectionID = await staleCollection.saveTx();
        report(`created collection "${staleCollectionName}" (id ${staleCollectionID})`);
    } else if (CONFIG.INCLUDE_STALE) {
        report('no stale parents; stale collection not created');
    }

    // Membership writes batched into ONE transaction (A10.7).
    await Zotero.DB.executeTransaction(async function () {
        if (missingCollectionID !== null) {
            for (var missingParentID of missingParentList) {
                var missingParentItem = await Zotero.Items.getAsync(missingParentID);
                missingParentItem.addToCollection(missingCollectionID);
                await missingParentItem.save();
            }
        }
        if (staleCollectionID !== null) {
            for (var staleParentID of staleParentList) {
                var staleParentItem = await Zotero.Items.getAsync(staleParentID);
                staleParentItem.addToCollection(staleCollectionID);
                await staleParentItem.save();
            }
        }
    });
    timing.writeMs = Date.now() - writeStart;
    report(`writes done in ${timing.writeMs} ms`);
    report('To undo: delete the collection(s). Deleting a collection does not ' +
        'delete the items in it.');
}

} catch (e) {
    Zotero.debug(`[collect_broken] ERROR: ${e.message}\n${e.stack}`);
    throw e;
}

// 6. SUMMARY
timing.totalMs = Date.now() - timing.scriptStart;
report(`done in ${timing.totalMs} ms, assertions ${timing.assertions}, ` +
    `yields ${timing.yieldCount}`);
return {
    dryRun: CONFIG.DRY_RUN,
    scanned: timing.linkedFileRows,
    present: timing.existing,
    missing: timing.missing,
    missingParentFolderGone: timing.parentFolderMissing,
    missingFileOnlyGone: timing.fileMissingInExistingFolder,
    stale: timing.stale,
    standaloneUncollectable: timing.standaloneBroken,
    collectableMissingParents: missingParentList.length,
    collectableStaleParents: staleParentList.length,
    missingCollectionName: missingCollectionName,
    staleCollectionName: CONFIG.INCLUDE_STALE ? staleCollectionName : null,
    missingCollectionID: missingCollectionID,
    staleCollectionID: staleCollectionID,
    missingSample: missingEntries.slice(0, CONFIG.REPORT_SAMPLE_MAX),
    staleEntries: staleEntries,
    standaloneEntries: standaloneEntries,
    timing: timing
};
