// =============================================================================
// REPAIR ATTACHMENT PATHS
// =============================================================================
// Version: 1.0.0
// Date:    2026-07
// Purpose: Repair broken linked-file attachment paths where the correct file
//          can be PROVEN to exist on disk. Closes the loop opened by
//          audit_orphan_attachments.js: the auditor detects broken links,
//          collect_broken_links.js surfaces them, this script fixes the two
//          mechanically-repairable classes and reports the rest.
//
// Usage:   Tools > Developer > Run JavaScript.
//          CHECK THE "Run as async function" CHECKBOX (A10.2).
//          DRY_RUN is true by default: it prints the full plan and writes
//          nothing. Set CONFIG.DRY_RUN = false to apply.
//
// Why not adjust_attachment_paths.js: that script does BLIND prefix
//          substitution with no existence check, hardcodes a single old base
//          (missing the second machine's user prefix), materializes the whole
//          library via Zotero.Items.getAll (A10.7 violation at ~71k rows),
//          and writes absolute paths back. This script verifies every
//          proposed path on disk before proposing it, handles multiple
//          historical bases, queries the DB directly, and writes RELATIVE
//          "attachments:" paths so the result survives the next machine
//          change. adjust_attachment_paths.js is left in place for history.
//
// Repair strategies (each candidate is verified with IOUtils.exists BEFORE
// it is proposed; an unverifiable candidate is never written):
//
//   S1 STALE_BASE -- the stored path is absolute under a historical base
//      (e.g. "\Dropbox (MIT)\zotero-storage\"), from an older layout or the
//      other machine. Take the tail after the marker, test it under the
//      CURRENT base, and if the file is there, rewrite to a relative path.
//      Fixes the 5 stale rows found by the 2026-07 audit.
//
//   S2 TRAILING_DOT -- the intended path contains a component ending in a
//      period or space (e.g. "Hughes Jr.", "Huawei Technologies Co., Ltd.",
//      "Boehmke, Ph.D."). Windows SILENTLY STRIPS trailing dots and spaces
//      from path components, so the folder on disk is "Hughes Jr" while the
//      database says "Hughes Jr." -- a link that can never resolve. Strip
//      trailing dots/spaces from every component, test, and rewrite if the
//      file is there. This is the largest broken-link class in the 2026-07
//      audit (42 of 73) and is SELF-INFLICTING: it recurs for every author
//      with a suffix (Jr., Inc., Ltd., Ph.D.) or a terminal initial. This
//      script REPAIRS the symptom; the naming pipeline must be fixed
//      separately to stop producing these paths (see handoff notes).
//
// Explicitly OUT OF SCOPE: conflict-copy repair. A link pointing at
//          "Title 2.pdf" whose file is gone may or may not be satisfied by
//          "Title.pdf" sitting beside it -- those are different files that
//          happen to share a stem, and silently repointing an item at a
//          file it never referenced is a data-integrity guess, not a
//          repair. Such rows are COUNTED and REPORTED as candidates for
//          manual review, never rewritten.
//
// Safety:  Every write is a path string change on an attachment row. No file
//          is moved, renamed, copied, or deleted. Nothing is written unless
//          the target file is confirmed present. Writes are batched into ONE
//          transaction (A10.7). The pre-change path of every modified row is
//          recorded in the return value, so a mistaken run is reversible by
//          writing the old strings back.
// =============================================================================

// 1. CONFIGURATION
var CONFIG = {
    DRY_RUN: true,                // A4: report-only default. false = apply.

    BASE_PATH: '',                // '' = derive from the baseAttachmentPath pref

    // S1: markers identifying a historical/foreign base inside a stored
    // absolute path. Matched case-insensitively as a SUBSTRING, because the
    // Windows user prefix differs per machine (Luis, Luised94, liusm) while
    // the tail is stable. The text AFTER the marker is the candidate tail.
    // Confirmed present in the 2026-07 audit's 5 stale rows.
    HISTORICAL_BASE_MARKERS: [
        '\\Dropbox (MIT)\\zotero-storage\\',
        '\\MIT Dropbox\\Luis Martinez\\zotero-storage\\'
    ],

    ENABLE_STALE_BASE_REPAIR: true,     // S1
    ENABLE_TRAILING_DOT_REPAIR: true,   // S2

    // Scale treatment (A5). The existence checks dominate.
    YIELD_EVERY_ROWS: 2000,
    DELAY_MS: 15,
    CHECKPOINT_EVERY: 10000,

    MAX_REPAIRS: 0,               // 0 = no cap. Set small to rehearse.
    REPORT_SAMPLE_MAX: 200,

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
    present: 0,
    broken: 0,
    repairableStaleBase: 0,
    repairableTrailingDot: 0,
    unrepairableConflictCopy: 0,
    unrepairableOther: 0,
    written: 0,
    writeErrors: 0
};

var repairs = [];          // { attachmentItemID, strategy, oldStored, newStored, verifiedPath }
var unrepairable = [];     // { attachmentItemID, intendedPath, classification }
var writeErrorSample = [];
var debugLines = [];

// 3. HELPERS

function report(line) {
    debugLines.push(line);
    Zotero.debug(`[repair_paths] ${line}`);
}

function assert(condition, message) {
    timing.assertions = timing.assertions + 1;
    if (!condition) {
        throw new Error(`repair_attachment_paths pre-flight failed: ${message}`);
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
assert(typeof IOUtils !== 'undefined' && typeof IOUtils.exists === 'function',
    'IOUtils.exists unavailable (requires Zotero 7+)');

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
var baseLower = basePath.toLowerCase();
report(`base path: ${basePath}`);

var markerLowers = [];
for (var marker of CONFIG.HISTORICAL_BASE_MARKERS) {
    markerLowers.push(marker.toLowerCase());
}

// 5. MAIN

// --- 5a. Scan and build verified repair candidates ---------------------------
var scanStart = Date.now();
var linkRows = await Zotero.DB.queryAsync(
    'SELECT ia.itemID AS attachmentItemID, ia.path AS storedPath ' +
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
    if (storedPath === null || storedPath === '') {
        timing.broken = timing.broken + 1;
        timing.unrepairableOther = timing.unrepairableOther + 1;
        unrepairable.push({ attachmentItemID: linkRow.attachmentItemID,
            intendedPath: String(storedPath), classification: 'empty stored path' });
        continue;
    }

    // Reconstruct the path the library currently intends.
    var isRelative = storedPath.startsWith('attachments:');
    var intendedPath = null;
    if (isRelative) {
        intendedPath = basePath + '\\' +
            storedPath.slice('attachments:'.length).replace(/\//g, '\\');
    } else {
        intendedPath = storedPath;
    }

    // A path that already resolves needs nothing.
    var intendedExists = await IOUtils.exists(intendedPath);
    if (intendedExists) {
        timing.present = timing.present + 1;
        rowsSinceYield = rowsSinceYield + 1;
        if (rowsSinceYield >= CONFIG.YIELD_EVERY_ROWS) {
            rowsSinceYield = 0;
            await yieldToEventLoop();
        }
        continue;
    }
    timing.broken = timing.broken + 1;

    // --- Candidate generation. Each candidate is a TAIL relative to the
    // current base; it becomes a repair only if the file is really there.
    var candidateTail = null;
    var strategy = null;

    // S1 STALE_BASE: absolute path under a historical/foreign base.
    if (CONFIG.ENABLE_STALE_BASE_REPAIR && !isRelative && candidateTail === null) {
        var storedLower = storedPath.toLowerCase();
        for (var markerLower of markerLowers) {
            var markerIndex = storedLower.indexOf(markerLower);
            if (markerIndex !== -1) {
                var tail = storedPath.slice(markerIndex + markerLower.length);
                // Only meaningful if it is not already under the current base.
                if (!storedLower.startsWith(baseLower + '\\')) {
                    candidateTail = tail.replace(/\//g, '\\');
                    strategy = 'STALE_BASE';
                }
                break;
            }
        }
    }

    // S2 TRAILING_DOT: a component ends with '.' or ' ', which Windows drops.
    if (CONFIG.ENABLE_TRAILING_DOT_REPAIR && candidateTail === null &&
        intendedPath.toLowerCase().startsWith(baseLower + '\\')) {
        var relativeTail = intendedPath.slice(basePath.length + 1);
        var components = relativeTail.split('\\');
        var anyTrimmed = false;
        var trimmedComponents = [];
        for (var component of components) {
            // Trailing dots and spaces only; leading whitespace is legitimate
            // in some author names and is left alone.
            var trimmed = component.replace(/[. ]+$/, '');
            if (trimmed !== component && trimmed.length > 0) {
                anyTrimmed = true;
            }
            trimmedComponents.push(trimmed.length > 0 ? trimmed : component);
        }
        if (anyTrimmed) {
            candidateTail = trimmedComponents.join('\\');
            strategy = 'TRAILING_DOT';
        }
    }

    // --- Verify the candidate before proposing it.
    var repaired = false;
    if (candidateTail !== null) {
        var candidateAbsolute = basePath + '\\' + candidateTail;
        var candidateExists = await IOUtils.exists(candidateAbsolute);
        if (candidateExists) {
            var newStored = 'attachments:' + candidateTail.replace(/\\/g, '/');
            repairs.push({ attachmentItemID: linkRow.attachmentItemID,
                strategy: strategy, oldStored: storedPath, newStored: newStored,
                verifiedPath: candidateAbsolute });
            if (strategy === 'STALE_BASE') {
                timing.repairableStaleBase = timing.repairableStaleBase + 1;
            } else {
                timing.repairableTrailingDot = timing.repairableTrailingDot + 1;
            }
            repaired = true;
        }
    }

    if (!repaired) {
        // Classify what is left so the report is actionable. Conflict copies
        // are deliberately NOT repaired (see header).
        var lastSeparatorIndex = intendedPath.lastIndexOf('\\');
        var leafName = intendedPath.slice(lastSeparatorIndex + 1);
        if (/ \d+\.[A-Za-z0-9]+$/.test(leafName)) {
            timing.unrepairableConflictCopy = timing.unrepairableConflictCopy + 1;
            unrepairable.push({ attachmentItemID: linkRow.attachmentItemID,
                intendedPath: intendedPath,
                classification: 'conflict-copy name; manual review (not auto-repaired by design)' });
        } else {
            timing.unrepairableOther = timing.unrepairableOther + 1;
            unrepairable.push({ attachmentItemID: linkRow.attachmentItemID,
                intendedPath: intendedPath,
                classification: 'no verified candidate found; manual relink' });
        }
    }

    rowsSinceYield = rowsSinceYield + 1;
    if (timing.linkedFileRows % CONFIG.CHECKPOINT_EVERY === 0) {
        report(`scan checkpoint: ${timing.linkedFileRows}/${linkRows.length}, ` +
            `${timing.broken} broken, ${repairs.length} repairable`);
    }
    if (rowsSinceYield >= CONFIG.YIELD_EVERY_ROWS) {
        rowsSinceYield = 0;
        await yieldToEventLoop();
    }
}
timing.scanMs = Date.now() - scanStart;

if (CONFIG.MAX_REPAIRS > 0 && repairs.length > CONFIG.MAX_REPAIRS) {
    report(`capping repairs at MAX_REPAIRS=${CONFIG.MAX_REPAIRS} ` +
        `(${repairs.length} available)`);
    repairs.length = CONFIG.MAX_REPAIRS;
}

report(`scan done: ${timing.present} present, ${timing.broken} broken, ` +
    `${timing.repairableStaleBase} repairable (stale base), ` +
    `${timing.repairableTrailingDot} repairable (trailing dot), ` +
    `${timing.unrepairableConflictCopy} conflict-copy (by design not repaired), ` +
    `${timing.unrepairableOther} other, ${timing.scanMs} ms`);

// --- 5b. Plan, printed in full before any write (A4) -------------------------
report('PLAN:');
report(`  rewrite ${repairs.length} attachment path(s) to verified relative paths`);
report('  every target file was confirmed present on disk during the scan');
report('  no file is moved, renamed, copied, or deleted');
for (var planIndex = 0; planIndex < Math.min(repairs.length, 10); planIndex++) {
    var planRepair = repairs[planIndex];
    report(`    [${planRepair.strategy}] ${planRepair.oldStored}`);
    report(`      -> ${planRepair.newStored}`);
}
if (repairs.length > 10) {
    report(`    ... and ${repairs.length - 10} more (full list in the return value)`);
}

if (CONFIG.DRY_RUN) {
    report('DRY_RUN: nothing written. Set CONFIG.DRY_RUN = false to apply the plan above.');
} else if (repairs.length === 0) {
    report('nothing to repair');
} else {
    var writeStart = Date.now();
    // One transaction for all rewrites (A10.7: one saveTx per item would be
    // one transaction per item, with per-item sync bookkeeping).
    await Zotero.DB.executeTransaction(async function () {
        for (var repair of repairs) {
            try {
                var attachmentItem = await Zotero.Items.getAsync(repair.attachmentItemID);
                attachmentItem.attachmentPath = repair.newStored;
                await attachmentItem.save();
                timing.written = timing.written + 1;
            } catch (writeError) {
                timing.writeErrors = timing.writeErrors + 1;
                if (writeErrorSample.length < 25) {
                    writeErrorSample.push({ attachmentItemID: repair.attachmentItemID,
                        error: writeError.message });
                }
            }
        }
    });
    timing.writeMs = Date.now() - writeStart;
    report(`writes done: ${timing.written} rewritten, ${timing.writeErrors} errors, ` +
        `${timing.writeMs} ms`);
    report('To undo: write the oldStored value back for each entry in repairs[].');
}

} catch (e) {
    Zotero.debug(`[repair_paths] ERROR: ${e.message}\n${e.stack}`);
    throw e;
}

// 6. SUMMARY
timing.totalMs = Date.now() - timing.scriptStart;
report(`done in ${timing.totalMs} ms, assertions ${timing.assertions}, ` +
    `yields ${timing.yieldCount}`);
return {
    dryRun: CONFIG.DRY_RUN,
    scanned: timing.linkedFileRows,
    present: timing.present,
    broken: timing.broken,
    repairableStaleBase: timing.repairableStaleBase,
    repairableTrailingDot: timing.repairableTrailingDot,
    unrepairableConflictCopy: timing.unrepairableConflictCopy,
    unrepairableOther: timing.unrepairableOther,
    written: timing.written,
    writeErrors: timing.writeErrors,
    writeErrorSample: writeErrorSample,
    repairs: repairs.slice(0, CONFIG.REPORT_SAMPLE_MAX),
    unrepairable: unrepairable.slice(0, CONFIG.REPORT_SAMPLE_MAX),
    timing: timing
};
