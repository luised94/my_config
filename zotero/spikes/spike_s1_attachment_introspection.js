// STATUS: COMPLETED SPIKE (thread 2). Run once on Zotero 9.0.6, 2026-07.
// Not maintained. Kept for reference and re-runnability. Findings are
// recorded in handoff/02_orphan_pipeline.md "Verified facts". Re-run only
// to re-confirm on a newer Zotero; bump MAX_ZOTERO_VERSION if you do.
// =============================================================================
// SPIKE S1: ATTACHMENT INTROSPECTION
// =============================================================================
// Version: 1.2
// Purpose: Verify attachment facts needed by the orphan auditor design
//          (handoff/02): linkMode values present and counts, getFilePath /
//          getFilePathAsync / fileExists behavior per linkMode, relative-path
//          (base directory) usage, trash and library breakdown.
// Usage:   Tools > Developer > Run JavaScript (Zotero 7+).
//          CHECK THE "Run as async function" CHECKBOX. Paste, run, and paste
//          the returned summary back into handoff/02 Verified facts.
// Safety:  Report-only. Zero writes to the library. Reads metadata and
//          checks file existence (stat-level; does not read file contents,
//          so Dropbox online-only placeholders are not hydrated).
// Output:  Returns summary object; mirrors every line to Zotero.debug.
// Changes in 1.2: LIKE query uses a bound parameter (Zotero.DB.queryAsync
//          rejects inline LIKE literals).
// Changes in 1.1: no async IIFE (the console does not await it, so the
//          return value was lost and errors were silent unhandled
//          rejections); top-level await with loud try/catch; single-use
//          helpers inlined per convention; MAX_ZOTERO_VERSION 9.0.6.
// =============================================================================

// 1. CONFIGURATION
var CONFIG = {
    SAMPLE_PER_LINKMODE: 8,      // items sampled per linkMode for API probing
    MISSING_SCAN_LIMIT: 2000,    // max linked-file attachments scanned to find missing-file examples
    MISSING_EXAMPLES_MAX: 5,     // stop after this many missing-file examples
    SCAN_BATCH_SIZE: 200,        // batch size for the missing-file scan
    DELAY_MS: 30,                // event-loop yield between batches
    MIN_ZOTERO_VERSION: '7.0',
    MAX_ZOTERO_VERSION: '9.0.6', // confirmed on 9.0.6 (spike run 2026-07)
    BYPASS_VERSION_CHECK: false  // single override for version checks
};

// 2. STATE
var timing = {
    scriptStart: Date.now(),
    assertions: 0,
    scannedForMissing: 0,
    missingFound: 0
};
var lines = [];
var summary = {
    zoteroVersion: null,
    error: null,
    prefs: {},
    linkModeConstants: {},
    linkModeCounts: [],
    contentTypeCounts: [],
    relativePathCount: 0,
    trashedAttachmentCount: 0,
    samples: [],
    missingExamples: [],
    timing: timing
};

// 3. HELPERS
function report(line) {
    lines.push(line);
    Zotero.debug(`[S1] ${line}`);
}

function assert(condition, message) {
    timing.assertions = timing.assertions + 1;
    if (!condition) {
        throw new Error(`S1 pre-flight failed: ${message}`);
    }
}

function safeCall(label, fn) {
    // Probes a host API that may throw for some linkModes; the throw itself
    // is a spike finding, so it is captured, not swallowed silently.
    try {
        var value = fn();
        return { ok: true, value: value };
    } catch (e) {
        return { ok: false, error: `${label}: ${e.message}` };
    }
}

async function safeCallAsync(label, fn) {
    try {
        var value = await fn();
        return { ok: true, value: value };
    } catch (e) {
        return { ok: false, error: `${label}: ${e.message}` };
    }
}

try {

// 4. PRE-FLIGHT
summary.zoteroVersion = Zotero.version;
var belowMin = Services.vc.compare(Zotero.version, CONFIG.MIN_ZOTERO_VERSION) < 0;
var aboveMax = Services.vc.compare(Zotero.version, CONFIG.MAX_ZOTERO_VERSION) > 0;
if ((belowMin || aboveMax) && !CONFIG.BYPASS_VERSION_CHECK) {
    throw new Error(`Zotero ${Zotero.version} outside tested range ` +
        `${CONFIG.MIN_ZOTERO_VERSION}..${CONFIG.MAX_ZOTERO_VERSION}. ` +
        `Set CONFIG.BYPASS_VERSION_CHECK = true to override.`);
}
assert(typeof Zotero.DB.queryAsync === 'function', 'Zotero.DB.queryAsync unavailable');
assert(typeof Zotero.Items.getAsync === 'function', 'Zotero.Items.getAsync unavailable');
report(`Zotero version: ${Zotero.version}`);

// 5. MAIN

// 5a. Base-directory prefs
summary.prefs.baseAttachmentPath = Zotero.Prefs.get('baseAttachmentPath');
summary.prefs.saveRelativeAttachmentPath = Zotero.Prefs.get('saveRelativeAttachmentPath');
report(`pref baseAttachmentPath: ${summary.prefs.baseAttachmentPath}`);
report(`pref saveRelativeAttachmentPath: ${summary.prefs.saveRelativeAttachmentPath}`);

// 5b. linkMode constants exposed by this Zotero version
var constantNames = [
    'LINK_MODE_IMPORTED_FILE',
    'LINK_MODE_IMPORTED_URL',
    'LINK_MODE_LINKED_FILE',
    'LINK_MODE_LINKED_URL',
    'LINK_MODE_EMBEDDED_IMAGE'
];
var linkModeName = {};
for (var name of constantNames) {
    var value = Zotero.Attachments[name];
    if (typeof value === 'number') {
        summary.linkModeConstants[name] = value;
        linkModeName[value] = name;
        report(`constant ${name} = ${value}`);
    } else {
        report(`constant ${name}: NOT DEFINED on this version`);
    }
}

// 5c. Counts by library and linkMode (includes trashed; noted separately)
var countRows = await Zotero.DB.queryAsync(
    'SELECT i.libraryID AS libraryID, ia.linkMode AS linkMode, COUNT(*) AS n ' +
    'FROM itemAttachments ia JOIN items i ON ia.itemID = i.itemID ' +
    'GROUP BY i.libraryID, ia.linkMode ORDER BY i.libraryID, ia.linkMode');
for (var row of countRows) {
    var lmLabel = linkModeName[row.linkMode];
    if (lmLabel === undefined) {
        lmLabel = 'UNKNOWN';
    }
    summary.linkModeCounts.push({
        libraryID: row.libraryID,
        linkMode: row.linkMode,
        linkModeName: lmLabel,
        count: row.n
    });
    report(`library ${row.libraryID} linkMode ${row.linkMode} (${lmLabel}): ${row.n}`);
}

var trashRows = await Zotero.DB.queryAsync(
    'SELECT COUNT(*) AS n FROM itemAttachments ia ' +
    'JOIN deletedItems di ON ia.itemID = di.itemID');
summary.trashedAttachmentCount = trashRows[0].n;
report(`attachments in trash (included in counts above): ${summary.trashedAttachmentCount}`);

// Zotero.DB.queryAsync REJECTS inline LIKE literals ("Please enter a LIKE
// clause with bindings") -- the pattern must be a bound parameter.
var relRows = await Zotero.DB.queryAsync(
    'SELECT COUNT(*) AS n FROM itemAttachments WHERE path LIKE ?',
    ['attachments:%']);
summary.relativePathCount = relRows[0].n;
report(`attachments with relative (attachments:) paths: ${summary.relativePathCount}`);

var ctRows = await Zotero.DB.queryAsync(
    'SELECT contentType, COUNT(*) AS n FROM itemAttachments ' +
    'GROUP BY contentType ORDER BY n DESC LIMIT 15');
for (var ctRow of ctRows) {
    summary.contentTypeCounts.push({ contentType: ctRow.contentType, count: ctRow.n });
    report(`contentType ${ctRow.contentType}: ${ctRow.n}`);
}

// 5d. Per-linkMode API probing on a small sample
var presentLinkModes = [];
for (var lmRow of countRows) {
    if (presentLinkModes.indexOf(lmRow.linkMode) === -1) {
        presentLinkModes.push(lmRow.linkMode);
    }
}
for (var lm of presentLinkModes) {
    var idRows = await Zotero.DB.queryAsync(
        'SELECT itemID FROM itemAttachments WHERE linkMode = ? LIMIT ?',
        [lm, CONFIG.SAMPLE_PER_LINKMODE]);
    var ids = [];
    for (var idRow of idRows) {
        ids.push(idRow.itemID);
    }
    var items = await Zotero.Items.getAsync(ids);
    for (var item of items) {
        var probe = {
            itemID: item.id,
            key: item.key,
            linkMode: lm,
            linkModeName: linkModeName[lm],
            contentType: item.attachmentContentType,
            rawPath: item.attachmentPath,
            getFilePath: safeCall('getFilePath', () => item.getFilePath()),
            getFilePathAsync: await safeCallAsync('getFilePathAsync', () => item.getFilePathAsync()),
            fileExists: await safeCallAsync('fileExists', () => item.fileExists())
        };
        summary.samples.push(probe);
        report(`sample ${probe.key} lm=${probe.linkModeName} raw=${probe.rawPath} ` +
            `getFilePath=${JSON.stringify(probe.getFilePath)} ` +
            `getFilePathAsync=${JSON.stringify(probe.getFilePathAsync)} ` +
            `fileExists=${JSON.stringify(probe.fileExists)}`);
    }
}

// 5e. Hunt for missing-file examples among linked-file attachments
var linkedFileMode = Zotero.Attachments.LINK_MODE_LINKED_FILE;
if (typeof linkedFileMode === 'number') {
    var scanRows = await Zotero.DB.queryAsync(
        'SELECT itemID FROM itemAttachments WHERE linkMode = ? ORDER BY itemID LIMIT ?',
        [linkedFileMode, CONFIG.MISSING_SCAN_LIMIT]);
    var scanIds = [];
    for (var scanRow of scanRows) {
        scanIds.push(scanRow.itemID);
    }
    for (var start = 0; start < scanIds.length; start = start + CONFIG.SCAN_BATCH_SIZE) {
        if (timing.missingFound >= CONFIG.MISSING_EXAMPLES_MAX) {
            break;
        }
        var batchIds = scanIds.slice(start, start + CONFIG.SCAN_BATCH_SIZE);
        var batchItems = await Zotero.Items.getAsync(batchIds);
        for (var scanItem of batchItems) {
            timing.scannedForMissing = timing.scannedForMissing + 1;
            var exists = await safeCallAsync('fileExists', () => scanItem.fileExists());
            var isMissing = exists.ok === true && exists.value === false;
            if (isMissing && timing.missingFound < CONFIG.MISSING_EXAMPLES_MAX) {
                timing.missingFound = timing.missingFound + 1;
                var missingProbe = {
                    itemID: scanItem.id,
                    key: scanItem.key,
                    rawPath: scanItem.attachmentPath,
                    getFilePath: safeCall('getFilePath', () => scanItem.getFilePath()),
                    getFilePathAsync: await safeCallAsync('getFilePathAsync', () => scanItem.getFilePathAsync())
                };
                summary.missingExamples.push(missingProbe);
                report(`MISSING example ${missingProbe.key} raw=${missingProbe.rawPath} ` +
                    `getFilePath=${JSON.stringify(missingProbe.getFilePath)} ` +
                    `getFilePathAsync=${JSON.stringify(missingProbe.getFilePathAsync)}`);
            }
        }
        // Inline event-loop yield (single call site).
        await new Promise(resolve => setTimeout(resolve, CONFIG.DELAY_MS));
    }
    report(`missing-file scan: scanned ${timing.scannedForMissing}, found ${timing.missingFound}`);
} else {
    report('LINK_MODE_LINKED_FILE constant missing; skipped missing-file scan');
}

} catch (e) {
    // Loud failure: record in the summary AND rethrow so the console shows it.
    summary.error = `${e.message}\n${e.stack}`;
    Zotero.debug(`[S1] ERROR: ${summary.error}`);
    throw e;
}

// 6. SUMMARY
timing.totalMs = Date.now() - timing.scriptStart;
report(`done in ${timing.totalMs} ms, assertions: ${timing.assertions}`);
return summary;
