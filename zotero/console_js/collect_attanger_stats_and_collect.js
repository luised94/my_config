// =============================================================================
// ATTANGER MOVE/RENAME STATS + COLLECT CANDIDATES
// =============================================================================
// Version: 1.0.0
// Date:    2026-07
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
// Confidence, honestly stated:
//   - RENAME target uses Zotero.Attachments.getFileBaseNameFromItem() -- the
//     SAME native call Attanger uses -- so it is accurate (modulo the
//     attachmentTitle edge case).
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

    MIN_ZOTERO_VERSION: '7.0',
    MAX_ZOTERO_VERSION: '9.0.6',
    BYPASS_VERSION_CHECK: false
};

// 2. STATE
var timing = {
    scriptStart: Date.now(), assertions: 0, scanMs: 0, writeMs: 0,
    yieldCount: 0, linkedFileRows: 0, standalone: 0, sourceMissing: 0,
    alreadyCorrect: 0, wouldMoveOnly: 0, wouldRenameOnly: 0,
    wouldMoveAndRename: 0, classifyErrors: 0, noCreatorFallbackUnknown: 0
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
report(`version 1.0.0 starting, Zotero ${Zotero.version}, DRY_RUN=${CONFIG.DRY_RUN}`);
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

var moveCollectionID = null, renameCollectionID = null;
if (CONFIG.DRY_RUN) {
    report('DRY_RUN: nothing created. Review sampleEntries. Set DRY_RUN=false to apply.');
} else {
    var writeStart = Date.now();
    if (moveList.length > 0) {
        var mc = new Zotero.Collection(); mc.libraryID = userLibraryID; mc.name = moveCollectionName;
        moveCollectionID = await mc.saveTx();
        report(`created "${moveCollectionName}" (id ${moveCollectionID})`);
    }
    if (CONFIG.INCLUDE_RENAME_COLLECTION && renameList.length > 0) {
        var rc = new Zotero.Collection(); rc.libraryID = userLibraryID; rc.name = renameCollectionName;
        renameCollectionID = await rc.saveTx();
        report(`created "${renameCollectionName}" (id ${renameCollectionID})`);
    }
    await Zotero.DB.executeTransaction(async function () {
        if (moveCollectionID !== null) for (var pid of moveList) {
            var it = await Zotero.Items.getAsync(pid); it.addToCollection(moveCollectionID); await it.save();
        }
        if (renameCollectionID !== null) for (var pid2 of renameList) {
            var it2 = await Zotero.Items.getAsync(pid2); it2.addToCollection(renameCollectionID); await it2.save();
        }
    });
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
    collectableMoveParents: moveList.length,
    collectableRenameParents: renameList.length,
    moveCollectionName, renameCollectionName: CONFIG.INCLUDE_RENAME_COLLECTION ? renameCollectionName : null,
    moveCollectionID, renameCollectionID,
    sample: sampleEntries,
    classifyErrorSample,
    sourceMissingSample,
    timing: timing
};
