// =============================================================================
// AUDIT ORPHAN ATTACHMENTS
// =============================================================================
// Version: 1.0.0
// Date:    2026-07
// Purpose: Report-only detection of (a) orphan files in the linked-attachment
//          base directory that no library item links to, and (b) items whose
//          linked file is missing on disk (broken links, bucketed missing vs
//          stale historical base). Design and verified facts:
//          handoff/02_orphan_pipeline.md, VERIFIED_ENVIRONMENT.md.
//
// Usage:   Tools > Developer > Run JavaScript.
//          CHECK THE "Run as async function" CHECKBOX (A10.2; the console
//          does not await an async IIFE). Paste, run. Outputs are written to
//          <Zotero data dir>/orphan_audit/<YYYY-MM-DD_HHMMSS>/ (ID1) and a
//          summary object is returned (also mirrored to Zotero.debug).
//
// Validation protocol (A4, ID5): run with CONFIG.MAX_ATTACHMENTS = 1000 and
//          CONFIG.MAX_ENTRIES = 5000 first, then 5000 / 25000, then 0 / 0
//          (full). On capped runs the reconciliation identity is reported
//          but not asserted; it is asserted only on a full run.
//
// Safety:  Zero writes to the Zotero library. Reads the DB and walks the
//          base directory with IOUtils.getChildren / IOUtils.stat only
//          (metadata; never reads file contents, so Dropbox online-only
//          placeholders are not hydrated -- S2, VERIFIED_ENVIRONMENT.md).
//          The only writes are the report files in the run output folder.
//          This script never moves or deletes anything (D2); the mover
//          (powershell/Move-OrphanFiles.ps1) consumes orphans.txt after
//          human review.
//
// Method (finalized design, handoff/02):
//          Phase 1: DB-driven collection of intended absolute paths for
//                   LINK_MODE_LINKED_FILE attachments in My Library, trash
//                   excluded. No item objects materialized (A10.7) except
//                   the pre-flight trust-but-verify sample.
//          Phase 2: IOUtils walk of the base directory, yields keyed on
//                   ENTRY count (S2 v1.1 lesson).
//          Phase 3: two-way set difference on normalized keys (separators
//                   unified, NFC, lowercased). Disk-only -> orphan.
//                   Library-only -> broken (missing or stale). Matched pairs
//                   whose raw forms differ only by NFC are flagged to
//                   normalization_mismatches.txt, never treated as orphans.
//
// Outputs (ID1, ID2): in the timestamped run folder --
//          orphans.txt                   one absolute Windows path per line,
//                                        UTF-8 with BOM, CRLF
//          broken_links_missing.txt      itemID<TAB>intended absolute path
//          broken_links_stale.txt        itemID<TAB>stored path<TAB>reason
//          normalization_mismatches.txt  library raw<TAB>disk raw
//          run_summary.json              counts, durations, config snapshot,
//                                        version stamps, per-folder
//                                        breakdown, metadata-gap sample
//                                        (UTF-8, no BOM)
//
// Dated exception to A5 (ID6, 2026-07): checkpoint logging is present but
//          START_INDEX resume is omitted. This script is report-only and a
//          full run costs ~2 min of walk plus fast DB queries; rerunning is
//          cheaper than resuming.
// =============================================================================

// 1. CONFIGURATION
var CONFIG = {
    // --- ramp caps (ID5). 0 = no cap (full run). ---
    MAX_ATTACHMENTS: 1000,        // Phase-1 linked-file rows processed (ramp: 1000, 5000, 0)
    MAX_ENTRIES: 5000,            // Phase-2 walk entries (ramp: 5000, 25000, 0)

    // --- paths ---
    BASE_PATH: '',                // '' = derive from Zotero baseAttachmentPath pref
    OUTPUT_SUBDIR: 'orphan_audit',// under the Zotero data directory (ID1)
    // Known historical bases (OQ1). Compared prefix-wise against the 5
    // absolute-path outliers after normalization. Extend as discovered.
    HISTORICAL_BASES: [
        'C:\\Users\\Luised94\\Dropbox (MIT)\\zotero-storage'
    ],

    // --- pre-flight trust-but-verify (handoff/02) ---
    SAMPLE_VERIFY_COUNT: 200,     // random linked-file items; reconstructed path must equal getFilePath()

    // --- metadata-gap side report (OQ2, ID7). Off the orphan critical path. ---
    METADATA_GAP_REPORT: true,
    METADATA_GAP_SAMPLE_MAX: 50,  // offending parent-item keys sampled into run_summary

    // --- ignore list (data-driven, D3). Matched case-insensitively on file name. ---
    IGNORE_EXACT: ['desktop.ini', 'thumbs.db', '.ds_store'],
    IGNORE_PREFIX: ['.dropbox', '~$'],
    IGNORE_SUFFIX: ['.tmp'],

    // --- scale treatment (A5, S2-informed) ---
    DB_YIELD_EVERY_ROWS: 5000,    // event-loop yield while processing Phase-1 rows
    WALK_YIELD_EVERY_ENTRIES: 2000,
    DELAY_MS: 15,                 // yield duration
    ADAPTIVE_DELAY_MAX_MS: 120,   // backoff cap when an interval runs slow
    SLOW_INTERVAL_MS: 4000,       // an inter-checkpoint interval slower than this triggers backoff
    CHECKPOINT_EVERY: 5000,       // Zotero.debug progress every N entries/rows
    MAX_CONSECUTIVE_FAILURES: 20, // abort threshold for the walk
    FAILURE_SAMPLE_MAX: 25,       // bounded failure sample kept (A6)

    // --- reporting bounds ---
    PER_FOLDER_TOP_N: 20,         // largest folders echoed to the debug summary
    DUPLICATE_SAMPLE_MAX: 25,     // sample of duplicate links / duplicate disk keys

    // --- version guards (A3) ---
    MIN_ZOTERO_VERSION: '7.0',
    MAX_ZOTERO_VERSION: '9.0.6',  // spikes S1/S2 confirmed on 9.0.6 (2026-07)
    BYPASS_VERSION_CHECK: false   // named bypass; bypassing is a visible decision
};

// 2. STATE
var timing = {
    scriptStart: Date.now(),
    assertions: 0,
    phase1Ms: 0,
    walkMs: 0,
    diffMs: 0,
    writeMs: 0,
    yieldCount: 0,
    currentDelayMs: CONFIG.DELAY_MS,
    // Phase 1
    linkedFileRows: 0,
    relativePathRows: 0,
    absolutePathRows: 0,
    duplicateLinks: 0,
    // Phase 2
    dirCount: 0,
    fileCount: 0,          // statted OK, not a directory
    ignoredCount: 0,
    statFailures: 0,
    consecutiveFailures: 0,
    maxDepth: 0,
    duplicateDiskKeys: 0,
    // Phase 3
    matched: 0,
    orphans: 0,
    brokenMissing: 0,
    brokenStale: 0,
    nfcOnlyMatches: 0
};

// normalizedKey -> { raw: <absolute path as reconstructed>, itemIDs: [..] }
var libraryPaths = new Map();
// normalizedKey -> { raw: <absolute path as found on disk> }
var diskPaths = new Map();
// Stale-base rows never enter the comparison (they cannot match the walk).
var staleRows = [];            // { itemID, rawStored, reason }
var duplicateLinkSample = [];  // { itemID, raw }
var duplicateDiskSample = [];  // raw paths
var walkFailures = [];         // { path, error }
var folderStats = {};          // topFolder -> { matched, orphans }
var capsHit = [];              // which caps truncated the run (ID5)
var debugLines = [];

// 3. HELPERS

function report(line) {
    debugLines.push(line);
    Zotero.debug(`[audit_orphans] ${line}`);
}

function assert(condition, message) {
    timing.assertions = timing.assertions + 1;
    if (!condition) {
        throw new Error(`audit_orphan_attachments pre-flight failed: ${message}`);
    }
}

// Normalization for comparison keys (handoff/02): unify separators, NFC,
// then lowercase. NFC before toLowerCase so composed characters case-fold
// consistently. Raw paths are preserved separately for reporting.
function normalizeKey(path) {
    return path.replace(/\//g, '\\').normalize('NFC').toLowerCase();
}

// Same fold WITHOUT NFC; used only to detect matches that succeeded solely
// because of NFC folding (those pairs are flagged, never orphans).
function foldWithoutNfc(path) {
    return path.replace(/\//g, '\\').toLowerCase();
}

async function yieldToEventLoop() {
    timing.yieldCount = timing.yieldCount + 1;
    await new Promise(resolve => setTimeout(resolve, timing.currentDelayMs));
}

try {

// 4. PRE-FLIGHT
report(`version 1.0.0 starting, Zotero ${Zotero.version}`);
var belowMin = Services.vc.compare(Zotero.version, CONFIG.MIN_ZOTERO_VERSION) < 0;
var aboveMax = Services.vc.compare(Zotero.version, CONFIG.MAX_ZOTERO_VERSION) > 0;
if ((belowMin || aboveMax) && !CONFIG.BYPASS_VERSION_CHECK) {
    throw new Error(`Zotero ${Zotero.version} outside tested range ` +
        `${CONFIG.MIN_ZOTERO_VERSION}..${CONFIG.MAX_ZOTERO_VERSION}. ` +
        `Set CONFIG.BYPASS_VERSION_CHECK = true to override.`);
}
assert(typeof Zotero.DB.queryAsync === 'function', 'Zotero.DB.queryAsync unavailable');
assert(typeof Zotero.Items.getAsync === 'function', 'Zotero.Items.getAsync unavailable');
assert(typeof IOUtils !== 'undefined' && typeof IOUtils.getChildren === 'function',
    'IOUtils.getChildren unavailable (requires Zotero 7+)');
assert(typeof IOUtils.writeUTF8 === 'function', 'IOUtils.writeUTF8 unavailable');
assert(typeof PathUtils !== 'undefined' && typeof PathUtils.join === 'function',
    'PathUtils.join unavailable');
assert(typeof ''.normalize === 'function', 'String.prototype.normalize unavailable');
assert(typeof Zotero.DataDirectory === 'object' &&
    typeof Zotero.DataDirectory.dir === 'string' && Zotero.DataDirectory.dir.length > 0,
    'Zotero.DataDirectory.dir unavailable');

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
// Strip a trailing separator so base + '\' + relative is well-formed.
if (basePath.endsWith('\\') || basePath.endsWith('/')) {
    basePath = basePath.slice(0, basePath.length - 1);
}
var baseExists = await IOUtils.exists(basePath);
assert(baseExists, `Base path does not exist: ${basePath}`);
var baseKey = normalizeKey(basePath);
report(`base path: ${basePath}`);
report(`caps: MAX_ATTACHMENTS=${CONFIG.MAX_ATTACHMENTS} MAX_ENTRIES=${CONFIG.MAX_ENTRIES} (0 = full)`);

// Trust-but-verify (handoff/02): random sample of linked-file attachments,
// loaded as items; the DB-reconstructed absolute path must equal
// getFilePath() exactly. Abort before any bulk work on mismatch.
var sampleRows = await Zotero.DB.queryAsync(
    'SELECT ia.itemID AS itemID, ia.path AS path ' +
    'FROM itemAttachments ia ' +
    'JOIN items i ON ia.itemID = i.itemID ' +
    'LEFT JOIN deletedItems di ON ia.itemID = di.itemID ' +
    'WHERE ia.linkMode = ? AND i.libraryID = ? AND di.itemID IS NULL ' +
    'ORDER BY RANDOM() LIMIT ?',
    [linkedFileMode, userLibraryID, CONFIG.SAMPLE_VERIFY_COUNT]);
var sampleIds = [];
var sampleStoredPath = {};
for (var sRow of sampleRows) {
    sampleIds.push(sRow.itemID);
    sampleStoredPath[sRow.itemID] = sRow.path;
}
var sampleItems = await Zotero.Items.getAsync(sampleIds);
var sampleMismatches = 0;
for (var sItem of sampleItems) {
    var stored = sampleStoredPath[sItem.id];
    var reconstructed = null;
    if (stored !== null && stored.startsWith('attachments:')) {
        reconstructed = basePath + '\\' +
            stored.slice('attachments:'.length).replace(/\//g, '\\');
    } else {
        reconstructed = stored;
    }
    var official = sItem.getFilePath();
    if (official !== reconstructed) {
        sampleMismatches = sampleMismatches + 1;
        report(`SAMPLE MISMATCH itemID=${sItem.id} stored=${stored} ` +
            `reconstructed=${reconstructed} getFilePath=${official}`);
    }
}
assert(sampleMismatches === 0,
    `${sampleMismatches} of ${sampleItems.length} sampled paths mismatch getFilePath(); ` +
    'DB reconstruction is not trustworthy on this library -- aborting before bulk pass');
report(`trust-but-verify: ${sampleItems.length} sampled, 0 mismatches`);

// linkMode inventory for reconciliation context (recorded, not acted on).
var linkModeCounts = {};
var lmRows = await Zotero.DB.queryAsync(
    'SELECT ia.linkMode AS linkMode, COUNT(*) AS n ' +
    'FROM itemAttachments ia ' +
    'JOIN items i ON ia.itemID = i.itemID ' +
    'LEFT JOIN deletedItems di ON ia.itemID = di.itemID ' +
    'WHERE i.libraryID = ? AND di.itemID IS NULL ' +
    'GROUP BY ia.linkMode',
    [userLibraryID]);
for (var lmRow of lmRows) {
    linkModeCounts[String(lmRow.linkMode)] = lmRow.n;
}
report(`linkMode inventory (My Library, trash excluded): ${JSON.stringify(linkModeCounts)}`);

// 5. MAIN

// --- 5a. Phase 1: DB-driven library path collection --------------------------
var phase1Start = Date.now();
var phase1Sql =
    'SELECT ia.itemID AS itemID, ia.path AS path ' +
    'FROM itemAttachments ia ' +
    'JOIN items i ON ia.itemID = i.itemID ' +
    'LEFT JOIN deletedItems di ON ia.itemID = di.itemID ' +
    'WHERE ia.linkMode = ? AND i.libraryID = ? AND di.itemID IS NULL ' +
    'ORDER BY ia.itemID';
var phase1Params = [linkedFileMode, userLibraryID];
if (CONFIG.MAX_ATTACHMENTS > 0) {
    phase1Sql = phase1Sql + ' LIMIT ?';
    phase1Params.push(CONFIG.MAX_ATTACHMENTS);
}
var linkRows = await Zotero.DB.queryAsync(phase1Sql, phase1Params);
if (CONFIG.MAX_ATTACHMENTS > 0 && linkRows.length === CONFIG.MAX_ATTACHMENTS) {
    capsHit.push('MAX_ATTACHMENTS');
}

// Historical bases, normalized once for prefix comparison.
var historicalBaseKeys = [];
for (var hb of CONFIG.HISTORICAL_BASES) {
    historicalBaseKeys.push(normalizeKey(hb));
}

var rowsSinceYield = 0;
for (var linkRow of linkRows) {
    timing.linkedFileRows = timing.linkedFileRows + 1;
    var storedPath = linkRow.path;

    if (storedPath === null || storedPath === '') {
        // Defensive: a linked-file row with no path cannot be located.
        staleRows.push({ itemID: linkRow.itemID, rawStored: String(storedPath),
            reason: 'empty path' });
        timing.brokenStale = timing.brokenStale + 1;
        continue;
    }

    var absolutePath = null;
    if (storedPath.startsWith('attachments:')) {
        timing.relativePathRows = timing.relativePathRows + 1;
        absolutePath = basePath + '\\' +
            storedPath.slice('attachments:'.length).replace(/\//g, '\\');
    } else {
        // One of the ~5 absolute-path outliers (S1). Classify by base.
        timing.absolutePathRows = timing.absolutePathRows + 1;
        var storedKey = normalizeKey(storedPath);
        if (storedKey.startsWith(baseKey + '\\')) {
            absolutePath = storedPath;   // under the current base; compares normally
        } else {
            var matchedHistorical = false;
            for (var hbKey of historicalBaseKeys) {
                if (storedKey.startsWith(hbKey + '\\')) {
                    matchedHistorical = true;
                    break;
                }
            }
            var staleReason = 'absolute path under unknown base';
            if (matchedHistorical) {
                staleReason = 'absolute path under known historical base ' +
                    '(fixable with adjust_attachment_paths.js)';
            }
            staleRows.push({ itemID: linkRow.itemID, rawStored: storedPath,
                reason: staleReason });
            timing.brokenStale = timing.brokenStale + 1;
            continue;
        }
    }

    var key = normalizeKey(absolutePath);
    var existing = libraryPaths.get(key);
    if (existing === undefined) {
        libraryPaths.set(key, { raw: absolutePath, itemIDs: [linkRow.itemID] });
    } else {
        // Two items link the same file (after folding): duplicate-link surplus.
        existing.itemIDs.push(linkRow.itemID);
        timing.duplicateLinks = timing.duplicateLinks + 1;
        if (duplicateLinkSample.length < CONFIG.DUPLICATE_SAMPLE_MAX) {
            duplicateLinkSample.push({ itemID: linkRow.itemID, raw: absolutePath });
        }
    }

    rowsSinceYield = rowsSinceYield + 1;
    if (timing.linkedFileRows % CONFIG.CHECKPOINT_EVERY === 0) {
        report(`phase1 checkpoint: ${timing.linkedFileRows}/${linkRows.length} rows`);
    }
    if (rowsSinceYield >= CONFIG.DB_YIELD_EVERY_ROWS) {
        rowsSinceYield = 0;
        await yieldToEventLoop();
    }
}
timing.phase1Ms = Date.now() - phase1Start;
report(`phase1 done: ${timing.linkedFileRows} rows ` +
    `(${timing.relativePathRows} relative, ${timing.absolutePathRows} absolute), ` +
    `${libraryPaths.size} unique keys, ${timing.duplicateLinks} duplicate links, ` +
    `${timing.brokenStale} stale, ${timing.phase1Ms} ms`);

// --- 5b. Metadata-gap side report (OQ2, ID7): pure SQL, no item objects -----
var metadataGap = null;
if (CONFIG.METADATA_GAP_REPORT) {
    var fieldRows = await Zotero.DB.queryAsync(
        'SELECT fieldID FROM fields WHERE fieldName = ?', ['date']);
    assert(fieldRows.length === 1, 'could not resolve the date fieldID');
    var dateFieldID = fieldRows[0].fieldID;

    var gapCountRows = await Zotero.DB.queryAsync(
        'SELECT ' +
        '  COUNT(*) AS parents, ' +
        '  SUM(noCreator) AS noCreator, ' +
        '  SUM(noDate) AS noDate, ' +
        '  SUM(noCreator * noDate) AS noBoth ' +
        'FROM ( ' +
        '  SELECT DISTINCT ia.parentItemID AS itemID, ' +
        '    NOT EXISTS (SELECT 1 FROM itemCreators ic WHERE ic.itemID = ia.parentItemID) AS noCreator, ' +
        '    NOT EXISTS (SELECT 1 FROM itemData idata WHERE idata.itemID = ia.parentItemID AND idata.fieldID = ?) AS noDate ' +
        '  FROM itemAttachments ia ' +
        '  JOIN items i ON ia.itemID = i.itemID ' +
        '  LEFT JOIN deletedItems di ON ia.itemID = di.itemID ' +
        '  WHERE ia.linkMode = ? AND i.libraryID = ? AND di.itemID IS NULL ' +
        '    AND ia.parentItemID IS NOT NULL ' +
        ')',
        [dateFieldID, linkedFileMode, userLibraryID]);

    var standaloneRows = await Zotero.DB.queryAsync(
        'SELECT COUNT(*) AS n ' +
        'FROM itemAttachments ia ' +
        'JOIN items i ON ia.itemID = i.itemID ' +
        'LEFT JOIN deletedItems di ON ia.itemID = di.itemID ' +
        'WHERE ia.linkMode = ? AND i.libraryID = ? AND di.itemID IS NULL ' +
        '  AND ia.parentItemID IS NULL',
        [linkedFileMode, userLibraryID]);

    var gapSampleRows = await Zotero.DB.queryAsync(
        'SELECT p.key AS key, ' +
        '  NOT EXISTS (SELECT 1 FROM itemCreators ic WHERE ic.itemID = p.itemID) AS noCreator, ' +
        '  NOT EXISTS (SELECT 1 FROM itemData idata WHERE idata.itemID = p.itemID AND idata.fieldID = ?) AS noDate ' +
        'FROM (SELECT DISTINCT ia.parentItemID AS itemID ' +
        '      FROM itemAttachments ia ' +
        '      JOIN items i ON ia.itemID = i.itemID ' +
        '      LEFT JOIN deletedItems di ON ia.itemID = di.itemID ' +
        '      WHERE ia.linkMode = ? AND i.libraryID = ? AND di.itemID IS NULL ' +
        '        AND ia.parentItemID IS NOT NULL) parents ' +
        'JOIN items p ON parents.itemID = p.itemID ' +
        'WHERE NOT EXISTS (SELECT 1 FROM itemCreators ic2 WHERE ic2.itemID = p.itemID) ' +
        '   OR NOT EXISTS (SELECT 1 FROM itemData idata2 WHERE idata2.itemID = p.itemID AND idata2.fieldID = ?) ' +
        'ORDER BY p.itemID LIMIT ?',
        [dateFieldID, linkedFileMode, userLibraryID, dateFieldID, CONFIG.METADATA_GAP_SAMPLE_MAX]);

    var gapSample = [];
    for (var gRow of gapSampleRows) {
        gapSample.push({ key: gRow.key,
            missingCreator: gRow.noCreator === 1,
            missingDate: gRow.noDate === 1 });
    }
    metadataGap = {
        parentsOfLinkedFiles: gapCountRows[0].parents,
        missingCreator: gapCountRows[0].noCreator,
        missingDate: gapCountRows[0].noDate,
        missingBoth: gapCountRows[0].noBoth,
        standaloneLinkedFileAttachments: standaloneRows[0].n,
        sample: gapSample
    };
    report(`metadata gap: ${metadataGap.parentsOfLinkedFiles} parents, ` +
        `${metadataGap.missingCreator} missing creator, ` +
        `${metadataGap.missingDate} missing date, ` +
        `${metadataGap.missingBoth} missing both, ` +
        `${metadataGap.standaloneLinkedFileAttachments} standalone attachments`);
}

// --- 5c. Phase 2: walk the base directory (S2 method) ------------------------
var walkStart = Date.now();
var walkAborted = null;
var stack = [{ path: basePath, depth: 0 }];
var entryCount = 0;
var entriesSinceYield = 0;
var lastCheckpointMs = Date.now();

while (stack.length > 0) {
    if (CONFIG.MAX_ENTRIES > 0 && entryCount >= CONFIG.MAX_ENTRIES) {
        capsHit.push('MAX_ENTRIES');
        walkAborted = `hit MAX_ENTRIES cap (${CONFIG.MAX_ENTRIES})`;
        break;
    }
    if (timing.consecutiveFailures >= CONFIG.MAX_CONSECUTIVE_FAILURES) {
        walkAborted = `hit MAX_CONSECUTIVE_FAILURES (${CONFIG.MAX_CONSECUTIVE_FAILURES})`;
        break;
    }

    var current = stack.pop();
    var children = null;
    try {
        children = await IOUtils.getChildren(current.path);
        timing.consecutiveFailures = 0;
    } catch (e) {
        timing.statFailures = timing.statFailures + 1;
        timing.consecutiveFailures = timing.consecutiveFailures + 1;
        if (walkFailures.length < CONFIG.FAILURE_SAMPLE_MAX) {
            walkFailures.push({ path: current.path, error: e.message });
        }
        continue;
    }
    timing.dirCount = timing.dirCount + 1;
    if (current.depth > timing.maxDepth) {
        timing.maxDepth = current.depth;
    }

    for (var childPath of children) {
        entryCount = entryCount + 1;
        entriesSinceYield = entriesSinceYield + 1;
        var stat = null;
        try {
            // Metadata only; never reads contents (no hydration -- S2).
            stat = await IOUtils.stat(childPath);
            timing.consecutiveFailures = 0;
        } catch (e) {
            timing.statFailures = timing.statFailures + 1;
            timing.consecutiveFailures = timing.consecutiveFailures + 1;
            if (walkFailures.length < CONFIG.FAILURE_SAMPLE_MAX) {
                walkFailures.push({ path: childPath, error: e.message });
            }
            continue;
        }
        if (stat.type === 'directory') {
            stack.push({ path: childPath, depth: current.depth + 1 });
        } else {
            timing.fileCount = timing.fileCount + 1;

            // Inline: file name for the ignore check (single textual call site).
            var slashNormalized = childPath.replace(/\\/g, '/');
            var fileName = slashNormalized.slice(slashNormalized.lastIndexOf('/') + 1);
            var nameLower = fileName.toLowerCase();

            var ignored = CONFIG.IGNORE_EXACT.indexOf(nameLower) !== -1;
            if (!ignored) {
                for (var prefix of CONFIG.IGNORE_PREFIX) {
                    if (nameLower.startsWith(prefix)) {
                        ignored = true;
                        break;
                    }
                }
            }
            if (!ignored) {
                for (var suffix of CONFIG.IGNORE_SUFFIX) {
                    if (nameLower.endsWith(suffix)) {
                        ignored = true;
                        break;
                    }
                }
            }
            if (ignored) {
                timing.ignoredCount = timing.ignoredCount + 1;
            } else {
                var diskKey = normalizeKey(childPath);
                if (diskPaths.has(diskKey)) {
                    // Two on-disk files fold to the same key (case/NFC twins).
                    // Ambiguous: excluded from orphan candidacy, counted apart.
                    timing.duplicateDiskKeys = timing.duplicateDiskKeys + 1;
                    if (duplicateDiskSample.length < CONFIG.DUPLICATE_SAMPLE_MAX) {
                        duplicateDiskSample.push(childPath);
                    }
                } else {
                    diskPaths.set(diskKey, { raw: childPath });
                }
            }
        }

        if (entryCount % CONFIG.CHECKPOINT_EVERY === 0) {
            var nowMs = Date.now();
            var intervalMs = nowMs - lastCheckpointMs;
            var intervalRate = Math.round(CONFIG.CHECKPOINT_EVERY / (intervalMs / 1000));
            lastCheckpointMs = nowMs;
            report(`walk checkpoint: ${entryCount} entries, ${timing.fileCount} files, ` +
                `${timing.dirCount} dirs, ${intervalRate}/s over last interval, ` +
                `delay ${timing.currentDelayMs} ms`);
            // Adaptive backoff (A5): a slow interval increases the yield, capped.
            if (intervalMs > CONFIG.SLOW_INTERVAL_MS &&
                timing.currentDelayMs < CONFIG.ADAPTIVE_DELAY_MAX_MS) {
                timing.currentDelayMs = Math.min(
                    timing.currentDelayMs * 2, CONFIG.ADAPTIVE_DELAY_MAX_MS);
            }
        }
        if (entriesSinceYield >= CONFIG.WALK_YIELD_EVERY_ENTRIES) {
            entriesSinceYield = 0;
            await yieldToEventLoop();
        }
    }
}
timing.walkMs = Date.now() - walkStart;
if (walkAborted !== null) {
    report(`walk ABORTED: ${walkAborted}`);
}
report(`phase2 done: ${entryCount} entries, ${timing.fileCount} files, ` +
    `${timing.dirCount} dirs, maxDepth ${timing.maxDepth}, ` +
    `${timing.ignoredCount} ignored, ${timing.statFailures} stat failures, ` +
    `${timing.duplicateDiskKeys} duplicate disk keys, ${timing.walkMs} ms`);
if (timing.maxDepth > 2) {
    report('WARNING: maxDepth exceeds 2; the no-snapshot-resource-folder ' +
        'assumption (handoff/02) may no longer hold -- inspect before moving anything');
}

// --- 5d. Phase 3: two-way set difference -------------------------------------
var diffStart = Date.now();
var orphanRaws = [];             // absolute disk paths, orphans.txt payload
var brokenMissing = [];          // { itemID, raw }
var nfcMismatchPairs = [];       // { libraryRaw, diskRaw }

// Disk side: orphan or matched; per-folder tally either way.
for (var diskEntry of diskPaths) {
    var dKey = diskEntry[0];
    var dVal = diskEntry[1];

    // Inline: top-level folder relative to base (single textual call site).
    var relative = dVal.raw.slice(basePath.length + 1);
    var sepIdx = relative.replace(/\//g, '\\').indexOf('\\');
    var topFolder = '(base root)';
    if (sepIdx > 0) {
        topFolder = relative.slice(0, sepIdx);
    }
    if (folderStats[topFolder] === undefined) {
        folderStats[topFolder] = { matched: 0, orphans: 0 };
    }

    var libVal = libraryPaths.get(dKey);
    if (libVal === undefined) {
        timing.orphans = timing.orphans + 1;
        folderStats[topFolder].orphans = folderStats[topFolder].orphans + 1;
        orphanRaws.push(dVal.raw);
    } else {
        timing.matched = timing.matched + 1;
        folderStats[topFolder].matched = folderStats[topFolder].matched + 1;
        // NFC-only match detection: raw forms differ even after separator
        // and case folding, so only NFC unified them. Flagged, never orphan.
        if (foldWithoutNfc(libVal.raw) !== foldWithoutNfc(dVal.raw)) {
            timing.nfcOnlyMatches = timing.nfcOnlyMatches + 1;
            nfcMismatchPairs.push({ libraryRaw: libVal.raw, diskRaw: dVal.raw });
        }
    }
}

// Library side: claimed but not on disk -> broken (missing).
for (var libEntry of libraryPaths) {
    var lKey = libEntry[0];
    var lVal = libEntry[1];
    if (!diskPaths.has(lKey)) {
        timing.brokenMissing = timing.brokenMissing + 1;
        brokenMissing.push({ itemID: lVal.itemIDs[0], raw: lVal.raw });
    }
}
orphanRaws.sort();
timing.diffMs = Date.now() - diffStart;
report(`phase3 done: ${timing.matched} matched, ${timing.orphans} orphans, ` +
    `${timing.brokenMissing} broken (missing), ${timing.brokenStale} broken (stale), ` +
    `${timing.nfcOnlyMatches} NFC-only matches, ${timing.diffMs} ms`);

// Reconciliation identity (handoff/02). Asserted only on a full run (ID5).
var isFullRun = capsHit.length === 0 && walkAborted === null;
var diskIdentityLeft = timing.fileCount;
var diskIdentityRight = timing.matched + timing.orphans + timing.ignoredCount +
    timing.duplicateDiskKeys;
var libIdentityLeft = timing.linkedFileRows;
var libIdentityRight = timing.matched + timing.brokenMissing + timing.brokenStale +
    timing.duplicateLinks;
var identity = {
    disk: { files: diskIdentityLeft,
        matchedPlusOrphansPlusIgnoredPlusDupKeys: diskIdentityRight,
        residual: diskIdentityLeft - diskIdentityRight },
    library: { linkedFileRows: libIdentityLeft,
        matchedPlusBrokenPlusDupLinks: libIdentityRight,
        residual: libIdentityLeft - libIdentityRight },
    assertedThisRun: isFullRun
};
report(`identity disk: ${diskIdentityLeft} = ${diskIdentityRight} ` +
    `(residual ${identity.disk.residual})`);
report(`identity library: ${libIdentityLeft} = ${libIdentityRight} ` +
    `(residual ${identity.library.residual})`);
if (isFullRun) {
    assert(identity.disk.residual === 0,
        `disk reconciliation identity does not close (residual ${identity.disk.residual})`);
    assert(identity.library.residual === 0,
        `library reconciliation identity does not close (residual ${identity.library.residual})`);
} else {
    report(`partial run (caps: ${capsHit.join(', ') || 'walk aborted'}); ` +
        'identity reported, not asserted (ID5)');
}

// --- 5e. Write outputs (ID1, ID2) --------------------------------------------
var writeStart = Date.now();
var now = new Date();
// Inline timestamp build (single textual call site).
var pad2 = function (n) { return String(n).padStart(2, '0'); };
var runStamp = `${now.getFullYear()}-${pad2(now.getMonth() + 1)}-${pad2(now.getDate())}` +
    `_${pad2(now.getHours())}${pad2(now.getMinutes())}${pad2(now.getSeconds())}`;
var outputDir = PathUtils.join(Zotero.DataDirectory.dir, CONFIG.OUTPUT_SUBDIR, runStamp);
await IOUtils.makeDirectory(outputDir, { createAncestors: true });

// UTF-8 BOM + CRLF for the .txt lists (ID2: Windows PowerShell 5.1 consumer).
var BOM = '\uFEFF';
var CRLF = '\r\n';

var orphanText = BOM + orphanRaws.join(CRLF);
if (orphanRaws.length > 0) {
    orphanText = orphanText + CRLF;
}
await IOUtils.writeUTF8(PathUtils.join(outputDir, 'orphans.txt'), orphanText);

var missingLines = [];
for (var bm of brokenMissing) {
    missingLines.push(`${bm.itemID}\t${bm.raw}`);
}
var missingText = BOM + missingLines.join(CRLF);
if (missingLines.length > 0) {
    missingText = missingText + CRLF;
}
await IOUtils.writeUTF8(PathUtils.join(outputDir, 'broken_links_missing.txt'), missingText);

var staleLines = [];
for (var st of staleRows) {
    staleLines.push(`${st.itemID}\t${st.rawStored}\t${st.reason}`);
}
var staleText = BOM + staleLines.join(CRLF);
if (staleLines.length > 0) {
    staleText = staleText + CRLF;
}
await IOUtils.writeUTF8(PathUtils.join(outputDir, 'broken_links_stale.txt'), staleText);

var nfcLines = [];
for (var pair of nfcMismatchPairs) {
    nfcLines.push(`${pair.libraryRaw}\t${pair.diskRaw}`);
}
var nfcText = BOM + nfcLines.join(CRLF);
if (nfcLines.length > 0) {
    nfcText = nfcText + CRLF;
}
await IOUtils.writeUTF8(PathUtils.join(outputDir, 'normalization_mismatches.txt'), nfcText);

// Per-folder breakdown for the JSON: every folder with at least one orphan,
// plus the special "_" and "undefined" folders, plus the top-N by file count.
var folderBreakdown = [];
var folderNames = Object.keys(folderStats);
for (var fName of folderNames) {
    var fs = folderStats[fName];
    var isSpecial = fName === '_' || fName === 'undefined' || fName === '(base root)';
    if (fs.orphans > 0 || isSpecial) {
        folderBreakdown.push({ folder: fName, matched: fs.matched, orphans: fs.orphans });
    }
}
folderBreakdown.sort(function (a, b) { return b.orphans - a.orphans; });
var topFoldersByFiles = [];
for (var fName2 of folderNames) {
    var fs2 = folderStats[fName2];
    topFoldersByFiles.push({ folder: fName2, files: fs2.matched + fs2.orphans });
}
topFoldersByFiles.sort(function (a, b) { return b.files - a.files; });
topFoldersByFiles.length = Math.min(topFoldersByFiles.length, CONFIG.PER_FOLDER_TOP_N);

timing.writeMs = Date.now() - writeStart;   // JSON written just below; close enough
timing.totalMs = Date.now() - timing.scriptStart;

var runSummary = {
    script: 'audit_orphan_attachments.js',
    version: '1.0.0',
    runStamp: runStamp,
    zoteroVersion: Zotero.version,
    basePath: basePath,
    config: CONFIG,
    capsHit: capsHit,
    walkAborted: walkAborted,
    isFullRun: isFullRun,
    linkModeCounts: linkModeCounts,
    timing: timing,
    identity: identity,
    counts: {
        libraryLinkedFileRows: timing.linkedFileRows,
        uniqueLibraryKeys: libraryPaths.size,
        duplicateLinks: timing.duplicateLinks,
        filesOnDisk: timing.fileCount,
        ignored: timing.ignoredCount,
        duplicateDiskKeys: timing.duplicateDiskKeys,
        statFailures: timing.statFailures,
        matched: timing.matched,
        orphans: timing.orphans,
        brokenMissing: timing.brokenMissing,
        brokenStale: timing.brokenStale,
        nfcOnlyMatches: timing.nfcOnlyMatches
    },
    duplicateLinkSample: duplicateLinkSample,
    duplicateDiskSample: duplicateDiskSample,
    walkFailureSample: walkFailures,
    folderBreakdown: folderBreakdown,
    topFoldersByFiles: topFoldersByFiles,
    metadataGap: metadataGap,
    outputs: {
        directory: outputDir,
        files: ['orphans.txt', 'broken_links_missing.txt',
            'broken_links_stale.txt', 'normalization_mismatches.txt',
            'run_summary.json']
    }
};
// JSON is UTF-8 WITHOUT BOM (ID2).
await IOUtils.writeUTF8(PathUtils.join(outputDir, 'run_summary.json'),
    JSON.stringify(runSummary, null, 2));
report(`outputs written to ${outputDir}`);

} catch (e) {
    // Loud failure: log and rethrow so the console shows it (A10.2).
    Zotero.debug(`[audit_orphans] ERROR: ${e.message}\n${e.stack}`);
    throw e;
}

// 6. SUMMARY
report(`done in ${timing.totalMs} ms ` +
    `(phase1 ${timing.phase1Ms}, walk ${timing.walkMs}, diff ${timing.diffMs}, ` +
    `write ${timing.writeMs}), assertions ${timing.assertions}, ` +
    `yields ${timing.yieldCount}`);
return {
    orphans: timing.orphans,
    brokenMissing: timing.brokenMissing,
    brokenStale: timing.brokenStale,
    matched: timing.matched,
    nfcOnlyMatches: timing.nfcOnlyMatches,
    capsHit: capsHit,
    isFullRun: isFullRun,
    outputDir: outputDir,
    identity: identity,
    timing: timing
};
