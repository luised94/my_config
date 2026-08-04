// =============================================================================
// ATTANGER MOVE/RENAME STATS + COLLECT CANDIDATES
// =============================================================================
// Version: 1.1.0
// Date:    2026-08
// Purpose: For every live linked-file attachment, compute what Attanger WOULD
//          do (target folder = destDir + first-author-family subfolder; target
//          filename = Zotero's native rename template), compare to the current
//          path, and collect the PARENT items that need a move and/or a rename
//          into dated collection(s) for manual processing via Attanger's GUI
//          (right-click > Attanger > Rename and Move Attachment).
//
// Usage:   Tools > Developer > Run JavaScript.  CHECK "Run as async function".
//          DRY_RUN default: reports the plan, writes nothing.
//          DRY_RUN=false: creates collection(s) + adds parents.
//
// Changes in 1.1.0:
//   - All membership saves now share ONE Zotero.Notifier.Queue, committed once
//     after all chunks. 1.0.0 fired a notifier batch per chunk (~20 batches at
//     10k items / 500 chunk), and EACH batch triggered a full tag-selector
//     reload (~50 s in a large library) plus items-pane refresh. The UI churned
//     for many minutes after the writes were already committed. One queue ->
//     one notification batch -> one UI refresh.
//   - addItems() replaced with a direct per-item addToCollection + save loop,
//     because addItems in shipped Zotero versions does not reliably forward
//     save options, and the notifierQueue option must reach item.save() to
//     work. The loop passes skipDateModifiedUpdate (same lightening addItems
//     used) plus notifierQueue explicitly, so no forwarding is assumed.
//   - Queue commit is in a finally block: a mid-run failure still flushes the
//     notifications for whatever was committed, so the UI does not silently
//     desynchronize from the database.
//   - Re-run on the same day now REUSES an existing collection with the same
//     name instead of creating a duplicate, and skips parents already in it.
//     This makes the advertised "idempotent and re-runnable" claim true at the
//     collection level, not just the membership level.
//   - Removed duplicated CONFIG keys (YIELD_HOLD_MS, HEARTBEAT_EVERY_ITEMS,
//     REPORT_SAMPLE_MAX appeared twice; values were identical, last-one-wins,
//     so this is a no-op cleanup).
//
// Confidence, honestly stated:
//   - RENAME target uses Zotero.Attachments.getFileBaseNameFromItem() -- the
//     SAME native call Attanger uses -- so it is accurate (modulo the
//     attachmentTitle edge case). CAVEAT: this script then applies its own
//     sanitizePathComponent() to that base, which may not match Zotero's
//     internal filename cleaning exactly; disagreement inflates RENAME false
//     positives only. Safe direction, given the superset design below.
//   - MOVE target reimplements Attanger's subfolderFormat
//     ({{ authors name="family" max="1" }} = first author's family name).
//     This is BEST-EFFORT: diacritic/sanitization rules may differ slightly.
//   Because running Attanger's move on an already-correct item is a NO-OP,
//   the collections are a safe SUPERSET: false positives cost a harmless
//   no-op, so membership is biased toward inclusion.
//
// Reversibility: only write is collection membership. No file, path, or item
//          data is touched. This script NEVER moves or renames anything --
//          that is the GUI's job, under your eye, per item.
//
// Source-missing items are classified separately and NOT collected: Attanger
//          cannot move a file that is not on disk. Those belong to the
//          broken-links repair workflow, not here.
// =============================================================================

// 1. CONFIGURATION
var CONFIG = {
    DRY_RUN: true,

    RESTRICT_TO_SELECTED_ITEMS: false,   // validate on a small selection first
    CHECK_SOURCE_EXISTS: true,           // skip/flag attachments whose file is gone

    MOVE_COLLECTION_PREFIX: 'Attanger move candidates',
    INCLUDE_RENAME_COLLECTION: true,
    RENAME_COLLECTION_PREFIX: 'Attanger rename candidates',

    DEST_DIR: '',        // '' = read extensions.zotero.zoteroattanger.destDir
    BASE_PATH: '',       // '' = read baseAttachmentPath (for reconstructing current paths)

    YIELD_HOLD_MS: 40,           // time-budget yielding (matches BBT lesson)
    HEARTBEAT_EVERY_ITEMS: 5000,
    REPORT_SAMPLE_MAX: 100,
    WRITE_CHUNK_SIZE: 500,       // membership writes per transaction; bounds txn duration

    MIN_ZOTERO_VERSION: '7.0',
    MAX_ZOTERO_VERSION: '9.0.6',
    BYPASS_VERSION_CHECK: false
};

// 2. STATE
var timing = {
    scriptStart: Date.now(), assertions: 0, scanMs: 0, writeMs: 0,
    yieldCount: 0, linkedFileRows: 0, standalone: 0, sourceMissing: 0,
    alreadyCorrect: 0, wouldMoveOnly: 0, wouldRenameOnly: 0,
    wouldMoveAndRename: 0, classifyErrors: 0, noCreatorFallbackUnknown: 0,
    alreadyMembersSkipped: 0
};
var moveParentIDs = new Set();
var renameParentIDs = new Set();
var sampleEntries = [];        // { attachmentItemID, parentItemID, current, expected, detail }
var classifyErrorSample = [];  // { attachmentItemID, message }
var sourceMissingSample = [];
var debugLines = [];
var lastYieldAt = Date.now();

// 3. HELPERS
function report(l) { debugLines.push(l); Zotero.debug(`[attanger_stats] ${l}`); }
function assert(c, m) { timing.assertions++; if (!c) throw new Error(`attanger_stats pre-flight failed: ${m}`); }
async function maybeYield() {
    if (Date.now() - lastYieldAt >= CONFIG.YIELD_HOLD_MS) {
        timing.yieldCount++;
        await new Promise(r => setTimeout(r, 0));
        lastYieldAt = Date.now();
    }
}
function normalizeKey(path) { return path.replace(/\//g, '\\').normalize('NFC').toLowerCase(); }
function sanitizePathComponent(s) {
    return s.replace(/[\\/:*?"<>|]/g, '_').replace(/[.\s]+$/, '').trim();
}

try {

// 4. PRE-FLIGHT
report(`version 1.1.0 starting, Zotero ${Zotero.version}, DRY_RUN=${CONFIG.DRY_RUN}`);
var belowMin = Services.vc.compare(Zotero.version, CONFIG.MIN_ZOTERO_VERSION) < 0;
var aboveMax = Services.vc.compare(Zotero.version, CONFIG.MAX_ZOTERO_VERSION) > 0;
if ((belowMin || aboveMax) && !CONFIG.BYPASS_VERSION_CHECK) {
    throw new Error(`Zotero ${Zotero.version} outside tested range; set BYPASS_VERSION_CHECK.`);
}
assert(typeof Zotero.DB.queryAsync === 'function', 'queryAsync unavailable');
assert(typeof Zotero.DB.executeTransaction === 'function', 'executeTransaction unavailable');
assert(typeof Zotero.Items.getAsync === 'function', 'getAsync unavailable');
assert(typeof Zotero.Collection === 'function', 'Zotero.Collection unavailable');
assert(typeof Zotero.Attachments.getFileBaseNameFromItem === 'function',
    'Zotero.Attachments.getFileBaseNameFromItem unavailable (needed for accurate rename target)');
assert(typeof IOUtils !== 'undefined' && typeof IOUtils.exists === 'function', 'IOUtils.exists unavailable');
// New in 1.1.0: the notifier queue is the mechanism that prevents the per-chunk
// UI refresh storm, so its absence is a hard stop, not a degraded mode.
assert(typeof Zotero.Notifier === 'object' && typeof Zotero.Notifier.Queue === 'function',
    'Zotero.Notifier.Queue unavailable (needed to batch UI notifications)');
assert(typeof Zotero.Notifier.commit === 'function', 'Zotero.Notifier.commit unavailable');

var linkedFileMode = Zotero.Attachments.LINK_MODE_LINKED_FILE;
var userLibraryID = Zotero.Libraries.userLibraryID;
var authorTypeID = Zotero.CreatorTypes.getID('author');

var destDir = CONFIG.DEST_DIR || Zotero.Prefs.get('extensions.zotero.zoteroattanger.destDir', true);
assert(typeof destDir === 'string' && destDir.length > 0, 'No Attanger destDir');
if (destDir.endsWith('\\') || destDir.endsWith('/')) destDir = destDir.slice(0, -1);

var basePath = CONFIG.BASE_PATH || Zotero.Prefs.get('baseAttachmentPath');
assert(typeof basePath === 'string' && basePath.length > 0, 'No baseAttachmentPath');
if (basePath.endsWith('\\') || basePath.endsWith('/')) basePath = basePath.slice(0, -1);

var attachType = Zotero.Prefs.get('extensions.zotero.zoteroattanger.attachType', true);
report(`destDir=${destDir}`);
report(`basePath=${basePath}`);
report(`attachType=${attachType} (Attanger moves only when this is "linking")`);
if (attachType !== 'linking') {
    report('WARNING: attachType is not "linking"; Attanger move may not act on these.');
}

// Optional selection restriction
var restrictSet = null;
if (CONFIG.RESTRICT_TO_SELECTED_ITEMS) {
    restrictSet = new Set();
    var sel = (typeof ZoteroPane !== 'undefined') ? ZoteroPane.getSelectedItems() : [];
    for (var s of sel) {
        if (s.isAttachment && s.isAttachment()) restrictSet.add(s.id);
        else {
            var kids = s.getAttachments ? s.getAttachments() : [];
            for (var kid of kids) restrictSet.add(kid);
        }
    }
    report(`RESTRICT_TO_SELECTED_ITEMS: ${restrictSet.size} attachment id(s) in scope`);
    if (restrictSet.size === 0) report('WARNING: nothing selected; scan will process nothing.');
}

// 5. MAIN
var scanStart = Date.now();
var rows = await Zotero.DB.queryAsync(
    'SELECT ia.itemID AS attachmentItemID, ia.path AS storedPath, ' +
    '       ia.parentItemID AS parentItemID ' +
    'FROM itemAttachments ia ' +
    'JOIN items i ON ia.itemID = i.itemID ' +
    'LEFT JOIN deletedItems di ON di.itemID = ia.itemID ' +
    'WHERE ia.linkMode = ? AND i.libraryID = ? AND di.itemID IS NULL ' +
    'ORDER BY ia.itemID',
    [linkedFileMode, userLibraryID]);
report(`scanning ${rows.length} live linked-file attachment(s)`);

for (var row of rows) {
    timing.linkedFileRows++;
    if (timing.linkedFileRows % CONFIG.HEARTBEAT_EVERY_ITEMS === 0) {
        report(`heartbeat: ${timing.linkedFileRows}/${rows.length} scanned, ` +
            `${timing.wouldMoveOnly + timing.wouldMoveAndRename} move, ` +
            `${timing.wouldRenameOnly + timing.wouldMoveAndRename} rename`);
    }
    await maybeYield();

    if (restrictSet && !restrictSet.has(row.attachmentItemID)) continue;

    if (row.parentItemID === null) {
        timing.standalone++;
        continue;   // no parent -> no author subfolder, and cannot be collected
    }

    // Reconstruct current absolute path
    var storedPath = row.storedPath || '';
    var currentAbsolute;
    if (storedPath.startsWith('attachments:')) {
        currentAbsolute = basePath + '\\' +
            storedPath.slice('attachments:'.length).replace(/\//g, '\\');
    } else {
        currentAbsolute = storedPath.replace(/\//g, '\\');
    }
    if (!currentAbsolute) { continue; }

    var lastSep = currentAbsolute.lastIndexOf('\\');
    var currentFolder = currentAbsolute.slice(0, lastSep);
    var currentFilename = currentAbsolute.slice(lastSep + 1);
    var dotIdx = currentFilename.lastIndexOf('.');
    var ext = dotIdx >= 0 ? currentFilename.slice(dotIdx) : '';

    // Optional source-existence gate (move needs the file present)
    if (CONFIG.CHECK_SOURCE_EXISTS) {
        var exists = await IOUtils.exists(currentAbsolute);
        if (!exists) {
            timing.sourceMissing++;
            if (sourceMissingSample.length < CONFIG.REPORT_SAMPLE_MAX) {
                sourceMissingSample.push({ attachmentItemID: row.attachmentItemID,
                    parentItemID: row.parentItemID, path: currentAbsolute });
            }
            continue;   // defer to broken-links workflow, do not collect here
        }
    }

    try {
        var parentItem = await Zotero.Items.getAsync(row.parentItemID);

        // --- expected subfolder: first author's family name (best-effort) ---
        var creators = parentItem.getCreators();
        var firstAuthor = null;
        for (var cr of creators) { if (cr.creatorTypeID === authorTypeID) { firstAuthor = cr; break; } }
        if (!firstAuthor && creators.length > 0) firstAuthor = creators[0];
        var subfolder = null;
        if (firstAuthor) {
            subfolder = sanitizePathComponent(firstAuthor.lastName || firstAuthor.firstName || '');
        }
        if (!subfolder) {
            timing.noCreatorFallbackUnknown++;
            // Attanger's no-author fallback is unknown; be conservative -> flag as move candidate.
            moveParentIDs.add(row.parentItemID);
            if (sampleEntries.length < CONFIG.REPORT_SAMPLE_MAX) {
                sampleEntries.push({ attachmentItemID: row.attachmentItemID,
                    parentItemID: row.parentItemID, current: currentAbsolute,
                    expected: '(unknown: no author; Attanger fallback undetermined)',
                    detail: 'no-author fallback unknown' });
            }
            continue;
        }
        var expectedFolder = destDir + '\\' + subfolder;

        // --- expected filename: native rename template (accurate) ---
        var expectedBase = await Zotero.Attachments.getFileBaseNameFromItem(parentItem);
        var expectedFilename = (expectedBase ? sanitizePathComponent(expectedBase) : currentFilename.slice(0, dotIdx >= 0 ? dotIdx : undefined)) + ext;

        var folderDiffers = normalizeKey(currentFolder) !== normalizeKey(expectedFolder);
        var nameDiffers = normalizeKey(currentFilename) !== normalizeKey(expectedFilename);

        var detail;
        if (folderDiffers && nameDiffers) {
            timing.wouldMoveAndRename++; detail = 'move + rename';
            moveParentIDs.add(row.parentItemID); renameParentIDs.add(row.parentItemID);
        } else if (folderDiffers) {
            timing.wouldMoveOnly++; detail = 'move only';
            moveParentIDs.add(row.parentItemID);
        } else if (nameDiffers) {
            timing.wouldRenameOnly++; detail = 'rename only';
            renameParentIDs.add(row.parentItemID);
        } else {
            timing.alreadyCorrect++; detail = 'already correct';
        }

        if (detail !== 'already correct' && sampleEntries.length < CONFIG.REPORT_SAMPLE_MAX) {
            sampleEntries.push({ attachmentItemID: row.attachmentItemID,
                parentItemID: row.parentItemID, current: currentAbsolute,
                expected: expectedFolder + '\\' + expectedFilename, detail: detail });
        }
    } catch (e) {
        timing.classifyErrors++;
        if (classifyErrorSample.length < CONFIG.REPORT_SAMPLE_MAX) {
            classifyErrorSample.push({ attachmentItemID: row.attachmentItemID, message: e.message });
        }
    }
}
timing.scanMs = Date.now() - scanStart;
report(`scan done: correct ${timing.alreadyCorrect}, moveOnly ${timing.wouldMoveOnly}, ` +
    `renameOnly ${timing.wouldRenameOnly}, move+rename ${timing.wouldMoveAndRename}, ` +
    `sourceMissing ${timing.sourceMissing}, standalone ${timing.standalone}, ` +
    `noAuthor ${timing.noCreatorFallbackUnknown}, errors ${timing.classifyErrors}; ${timing.scanMs} ms`);

var moveList = Array.from(moveParentIDs);
var renameList = Array.from(renameParentIDs);
report(`collectable parents: ${moveList.length} move, ${renameList.length} rename`);

// --- Plan / write ------------------------------------------------------------
var now = new Date();
var pad2 = n => String(n).padStart(2, '0');
var dateStamp = `${now.getFullYear()}-${pad2(now.getMonth() + 1)}-${pad2(now.getDate())}`;
var moveCollectionName = `${CONFIG.MOVE_COLLECTION_PREFIX} ${dateStamp}`;
var renameCollectionName = `${CONFIG.RENAME_COLLECTION_PREFIX} ${dateStamp}`;

report('PLAN:');
report(`  "${moveCollectionName}" <- ${moveList.length} parent(s)`);
if (CONFIG.INCLUDE_RENAME_COLLECTION) report(`  "${renameCollectionName}" <- ${renameList.length} parent(s)`);
report('  writes: collection membership only. This script never moves or renames files.');


var moveCollection = null, renameCollection = null;
var moveCollectionID = null, renameCollectionID = null;
if (CONFIG.DRY_RUN) {
    report('DRY_RUN: nothing created. Review sampleEntries. Set DRY_RUN=false to apply.');
} else {
    var writeStart = Date.now();

    // Reuse a same-named collection if one exists (same-day re-run), so re-running
    // does not create "Attanger move candidates 2026-08-04" twice. getByLibrary
    // returns loaded collection objects; name match is exact.
    var existingCollections = Zotero.Collections.getByLibrary(userLibraryID);
    for (var existing of existingCollections) {
        if (existing.name === moveCollectionName) { moveCollection = existing; moveCollectionID = existing.id; }
        if (existing.name === renameCollectionName) { renameCollection = existing; renameCollectionID = existing.id; }
    }
    if (moveCollection !== null) report(`reusing existing "${moveCollectionName}" (id ${moveCollectionID})`);
    if (renameCollection !== null && CONFIG.INCLUDE_RENAME_COLLECTION) {
        report(`reusing existing "${renameCollectionName}" (id ${renameCollectionID})`);
    }

    // Collections created first (separate saveTx) so we hold live objects + IDs.
    if (moveCollection === null && moveList.length > 0) {
        moveCollection = new Zotero.Collection();
        moveCollection.libraryID = userLibraryID; moveCollection.name = moveCollectionName;
        moveCollectionID = await moveCollection.saveTx();
        report(`created "${moveCollectionName}" (id ${moveCollectionID})`);
    }
    if (CONFIG.INCLUDE_RENAME_COLLECTION && renameCollection === null && renameList.length > 0) {
        renameCollection = new Zotero.Collection();
        renameCollection.libraryID = userLibraryID; renameCollection.name = renameCollectionName;
        renameCollectionID = await renameCollection.saveTx();
        report(`created "${renameCollectionName}" (id ${renameCollectionID})`);
    }
    if (!CONFIG.INCLUDE_RENAME_COLLECTION) renameCollection = null;

    // Membership in CHUNKED transactions, NOT one big transaction. A single
    // transaction over ~16k per-item saves tripped Zotero's "Transaction
    // timeout, most likely caused by unresolved pending work"; bounding each
    // transaction to WRITE_CHUNK_SIZE items fixes that.
    //
    // 1.1.0: every save shares ONE notifier queue, committed ONCE after all
    // chunks. Without it, each chunk commit fired its own notification batch,
    // and each batch triggered a full tag-selector reload (~50 s in a large
    // library) plus items-pane refresh -- the UI churned for many minutes
    // after the database writes were long done. One queue -> one batch -> one
    // refresh. addItems() is NOT used because shipped versions do not reliably
    // forward save options; the direct addToCollection + save loop guarantees
    // notifierQueue and skipDateModifiedUpdate actually reach item.save().
    //
    // Trade-off accepted: this is no longer ONE transaction, so a mid-run
    // failure leaves a partially populated collection. That is safe here --
    // membership is idempotent and re-runnable (already-members are skipped),
    // and no file/path/item data is touched.
    //
    // Yield to the event loop ONLY BETWEEN chunks, never inside a transaction:
    // awaiting any non-DB promise (setTimeout, maybeYield, etc.) while a
    // transaction is open re-triggers the same timeout and rolls it back.
    var notifierQueue = new Zotero.Notifier.Queue();
    try {
        if (moveCollection !== null) {
            // Skip parents already in the collection (re-run case): a save on an
            // already-member item is not free, and 10k pointless saves is exactly
            // the cost this script exists to avoid.
            var movePending = moveList.filter(function (parentID) { return !moveCollection.hasItem(parentID); });
            timing.alreadyMembersSkipped += moveList.length - movePending.length;
            for (var moveChunkStart = 0; moveChunkStart < movePending.length; moveChunkStart += CONFIG.WRITE_CHUNK_SIZE) {
                var moveChunk = movePending.slice(moveChunkStart, moveChunkStart + CONFIG.WRITE_CHUNK_SIZE);
                var moveChunkItems = await Zotero.Items.getAsync(moveChunk);
                await Zotero.DB.executeTransaction(async function () {
                    for (var moveItem of moveChunkItems) {
                        moveItem.addToCollection(moveCollectionID);
                        await moveItem.save({ skipDateModifiedUpdate: true, notifierQueue: notifierQueue });
                    }
                });
                await new Promise(function (resolve) { setTimeout(resolve, 0); });
                timing.yieldCount++;
            }
            report(`added ${movePending.length} parent(s) to "${moveCollectionName}" ` +
                `(${moveList.length - movePending.length} already present, skipped)`);
        }
        if (renameCollection !== null) {
            var renamePending = renameList.filter(function (parentID) { return !renameCollection.hasItem(parentID); });
            timing.alreadyMembersSkipped += renameList.length - renamePending.length;
            for (var renameChunkStart = 0; renameChunkStart < renamePending.length; renameChunkStart += CONFIG.WRITE_CHUNK_SIZE) {
                var renameChunk = renamePending.slice(renameChunkStart, renameChunkStart + CONFIG.WRITE_CHUNK_SIZE);
                var renameChunkItems = await Zotero.Items.getAsync(renameChunk);
                await Zotero.DB.executeTransaction(async function () {
                    for (var renameItem of renameChunkItems) {
                        renameItem.addToCollection(renameCollectionID);
                        await renameItem.save({ skipDateModifiedUpdate: true, notifierQueue: notifierQueue });
                    }
                });
                await new Promise(function (resolve) { setTimeout(resolve, 0); });
                timing.yieldCount++;
            }
            report(`added ${renamePending.length} parent(s) to "${renameCollectionName}" ` +
                `(${renameList.length - renamePending.length} already present, skipped)`);
        }
    } finally {
        // Commit in finally: whatever chunks committed to the database before a
        // failure must still be announced, or the UI silently desynchronizes
        // from the database until restart. This is the ONE notification batch;
        // expect ONE tag reload + ONE items-pane refresh here, and only here.
        await Zotero.Notifier.commit(notifierQueue);
        report('notifier queue committed: expect a single UI refresh now');
    }

    timing.writeMs = Date.now() - writeStart;
    report(`writes done in ${timing.writeMs} ms`);
    report('Next: select the collection contents, right-click > Attanger > Rename and Move. ' +
        'Undo = delete the collection (does not delete items).');
}

} catch (e) {
    Zotero.debug(`[attanger_stats] ERROR: ${e.message}\n${e.stack}`);
    throw e;
}

// 6. SUMMARY
timing.totalMs = Date.now() - timing.scriptStart;
report(`done in ${timing.totalMs} ms, assertions ${timing.assertions}, yields ${timing.yieldCount}`);
return {
    dryRun: CONFIG.DRY_RUN,
    scanned: timing.linkedFileRows,
    alreadyCorrect: timing.alreadyCorrect,
    wouldMoveOnly: timing.wouldMoveOnly,
    wouldRenameOnly: timing.wouldRenameOnly,
    wouldMoveAndRename: timing.wouldMoveAndRename,
    sourceMissing: timing.sourceMissing,
    standaloneUncollectable: timing.standalone,
    noAuthorFallbackUnknown: timing.noCreatorFallbackUnknown,
    classifyErrors: timing.classifyErrors,
    alreadyMembersSkipped: timing.alreadyMembersSkipped,
    collectableMoveParents: moveList.length,
    collectableRenameParents: renameList.length,
    moveCollectionName, renameCollectionName: CONFIG.INCLUDE_RENAME_COLLECTION ? renameCollectionName : null,
    moveCollectionID, renameCollectionID,
    sample: sampleEntries,
    classifyErrorSample,
    sourceMissingSample,
    timing: timing
};
