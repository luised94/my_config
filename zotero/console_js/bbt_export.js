// =============================================================================
// ZOTERO BETTER BIBTEX BATCH EXPORT
// =============================================================================
// Version: 2.7
// Purpose: Export large Zotero libraries to BibTeX via Better BibTeX
// Usage:   Tools > Developer > Run JavaScript (Zotero 7)
// 
// Features:
//   - Batched processing to avoid UI freezes
//   - True event loop yield for UI responsiveness
//   - Pre-flight validation (item count, write permissions)
//   - Entry count verification after export
//   - Detailed timing breakdown and failure tracking
//   - DRY_RUN mode for testing without export
//
// Output:  Returns summary object; creates .bib file in Zotero data directory
// =============================================================================

// 1. CONFIGURATION
var CONFIG = {
    BATCH_SIZE: 1000,       // Items per batch
    DELAY_MS: 100,          // Pause between batches for UI responsiveness
    LIMIT: 110000,          // Safety limit - abort if library exceeds this
    MAX_RUN: 0,             // 0 = all items, N = first N items only
    DRY_RUN: false,         // true = preflight + load only, skip export/write
    MASTER_NAME: 'full_library_export.bib',
    TEMP_NAME: 'batch_tmp.bib',
    TRANSLATOR_ID: 'f895aa0d-f28e-47fe-b247-2ea77c6ed583',  // Better BibLaTeX

    // Incremental export state (commit 1 scaffolding; behavior unchanged)
    STATE_NAME: 'full_library_export.state.json',
    RESUME_ENABLED: true,      // Allows mode decision + state read/write (no slicing yet)
    FORCE_FULL: false,         // Manual override (mode decision only in commit 1)
    FULL_INTERVAL_DAYS: 7      // "Lazy" weekly full: triggers on next run after N days
};

// 2. PATHS
var masterPath = PathUtils.join(Zotero.DataDirectory.dir, CONFIG.MASTER_NAME);
var tempPath = PathUtils.join(Zotero.DataDirectory.dir, CONFIG.TEMP_NAME);
var tempFile = Zotero.File.pathToFile(tempPath);  // nsIFile required by setLocation()
var statePath = PathUtils.join(Zotero.DataDirectory.dir, CONFIG.STATE_NAME);

// 3. STATE
var timing = {
    scriptStart: Date.now(),
    preflight: 0,
    itemLoad: 0,
    export: 0,
    fileWrite: 0,
    verification: 0,
    batchCount: 0,
    processedCount: 0,
    failedCount: 0
};

var failedBatches = [];

// 4. HELPERS
var yieldToEventLoop = (ms) => new Promise(resolve => setTimeout(resolve, ms));

// 5. PRE-FLIGHT ASSERTIONS
var preflightStart = Date.now();
Zotero.debug("[Export] Running pre-flight assertions...");

if (!CONFIG.DRY_RUN) {
    try {
        await IOUtils.write(masterPath, new Uint8Array(0));
        await IOUtils.read(masterPath);
    } catch (e) {
        throw new Error(`Pre-flight failed: Cannot write/read ${masterPath}`);
    }
}

var search = new Zotero.Search();
search.libraryID = Zotero.Libraries.userLibrary.id;
search.addCondition('itemType', 'isNot', 'attachment');
search.addCondition('itemType', 'isNot', 'note');
search.addCondition('itemType', 'isNot', 'annotation');
var idsFromSearch = await search.search();

var idsFromDB = await Zotero.DB.columnQueryAsync(
    "SELECT itemID FROM items WHERE itemID NOT IN (SELECT itemID FROM itemAttachments UNION SELECT itemID FROM itemNotes UNION SELECT itemID FROM itemAnnotations)"
);

if (idsFromSearch.length !== idsFromDB.length) {
    Zotero.debug(`[Export] Warning: Count mismatch - Search API (${idsFromSearch.length}) vs DB (${idsFromDB.length})`);
}

if (idsFromSearch.length > CONFIG.LIMIT) {
    throw new Error(`Pre-flight failed: Library has ${idsFromSearch.length} items (limit: ${CONFIG.LIMIT})`);
}

timing.preflight = Date.now() - preflightStart;

// 5b. STATE LOAD + MODE DECISION
var now = Date.now();

var exportState = {
    stateVersion: 1,
    lastRunAt: 0,
    lastRunMode: 'UNKNOWN',
    lastRunReason: '',
    lastFullExportAt: 0
};

var stateLoadStatus = 'DISABLED';
var stateLoadError = '';

if (CONFIG.RESUME_ENABLED) {
    stateLoadStatus = 'MISSING';

    if (await IOUtils.exists(statePath)) {
        stateLoadStatus = 'FOUND';
        try {
            var rawStateText = await IOUtils.readUTF8(statePath);
            var parsedState = rawStateText ? JSON.parse(rawStateText) : null;

            if (parsedState && typeof parsedState === 'object') {
                // Only copy known fields to keep state stable
                if (typeof parsedState.stateVersion === 'number') exportState.stateVersion = parsedState.stateVersion;
                if (typeof parsedState.lastRunAt === 'number') exportState.lastRunAt = parsedState.lastRunAt;
                if (typeof parsedState.lastRunMode === 'string') exportState.lastRunMode = parsedState.lastRunMode;
                if (typeof parsedState.lastRunReason === 'string') exportState.lastRunReason = parsedState.lastRunReason;
                if (typeof parsedState.lastFullExportAt === 'number') exportState.lastFullExportAt = parsedState.lastFullExportAt;
            } else {
                stateLoadStatus = 'INVALID';
            }
        } catch (e) {
            stateLoadStatus = 'CORRUPT';
            stateLoadError = e.message;
        }
    }
}

var fullIntervalMs = CONFIG.FULL_INTERVAL_DAYS * 24 * 60 * 60 * 1000;
var daysSinceLastFull = exportState.lastFullExportAt > 0 ? ((now - exportState.lastFullExportAt) / (24 * 60 * 60 * 1000)) : null;

var modeDecision = { mode: 'FULL', reason: 'default' };

// Order matters: force > bad/missing state > timer > incremental
if (CONFIG.FORCE_FULL) {
    modeDecision = { mode: 'FULL', reason: 'force' };
} else if (!CONFIG.RESUME_ENABLED) {
    modeDecision = { mode: 'FULL', reason: 'resume_disabled' };
} else if (stateLoadStatus === 'CORRUPT' || stateLoadStatus === 'INVALID') {
    modeDecision = { mode: 'FULL', reason: 'state_bad' };
} else if (stateLoadStatus === 'MISSING') {
    modeDecision = { mode: 'FULL', reason: 'state_missing' };
} else if (exportState.lastFullExportAt === 0) {
    modeDecision = { mode: 'FULL', reason: 'no_last_full' };
} else if (fullIntervalMs > 0 && (now - exportState.lastFullExportAt) >= fullIntervalMs) {
    modeDecision = { mode: 'FULL', reason: 'timer_due' };
} else {
    modeDecision = { mode: 'INCREMENTAL', reason: 'timer_not_due' };
}

Zotero.debug(
    `[Export] State: ${stateLoadStatus}` +
    (stateLoadError ? ` (error="${stateLoadError}")` : '') +
    `; ModeDecision=${modeDecision.mode} reason=${modeDecision.reason}` +
    (daysSinceLastFull !== null ? ` daysSinceLastFull=${daysSinceLastFull.toFixed(2)}` : '')
);

// 6. DATA SLICING
var allIds = idsFromSearch.sort((a, b) => a - b);

if (CONFIG.MAX_RUN > 0) {
    Zotero.debug(`[Export] MAX_RUN active: processing first ${CONFIG.MAX_RUN} items only`);
    allIds = allIds.slice(0, CONFIG.MAX_RUN);
}

// 7. MAIN LOOP
var modeLabel = CONFIG.DRY_RUN ? '[DRY RUN] ' : '';
Zotero.debug(`[Export] ${modeLabel}Pre-flight passed. Processing ${allIds.length} items in batches of ${CONFIG.BATCH_SIZE}.`);

for (let i = 0; i < allIds.length; i += CONFIG.BATCH_SIZE) {
    let batchNum = Math.floor(i / CONFIG.BATCH_SIZE) + 1;
    let batchIds = allIds.slice(i, i + CONFIG.BATCH_SIZE);

    if (Zotero.isShuttingDown) break;

    try {
        // Load items
        let loadStart = Date.now();
        let items = await Zotero.Items.getAsync(batchIds);
        timing.itemLoad += Date.now() - loadStart;

        if (!items || items.length === 0) {
            failedBatches.push({ batch: batchNum, index: i, reason: 'No items loaded', sampleIds: batchIds.slice(0, 5) });
            timing.failedCount += batchIds.length;
            continue;
        }

        // Dry run: skip export and file operations
        if (CONFIG.DRY_RUN) {
            timing.processedCount += batchIds.length;
            timing.batchCount++;
            Zotero.debug(`[Export] ${modeLabel}Batch ${batchNum}: ${timing.processedCount}/${allIds.length}`);
            await yieldToEventLoop(CONFIG.DELAY_MS);
            continue;
        }

        // Export batch to temp file
        let exportStart = Date.now();
        if (await IOUtils.exists(tempPath)) await IOUtils.remove(tempPath);

        let exportSession = new Zotero.Translate.Export();
        exportSession.setItems(items);
        exportSession.setTranslator(CONFIG.TRANSLATOR_ID);
        exportSession.setLocation(tempFile);

        await new Promise((resolve, reject) => {
            exportSession.setHandler("done", (obj, success) => {
                success ? resolve() : reject(new Error("Export handler returned failure"));
            });
            exportSession.translate();
        });
        timing.export += Date.now() - exportStart;

        // Append temp file to master
        let writeStart = Date.now();

        if (!await IOUtils.exists(tempPath)) {
            failedBatches.push({ batch: batchNum, index: i, reason: 'Temp file not created', itemCount: items.length });
            timing.failedCount += batchIds.length;
            continue;
        }

        let batchBytes = await IOUtils.read(tempPath);

        if (batchBytes.length === 0) {
            failedBatches.push({ batch: batchNum, index: i, reason: 'Empty export output', itemCount: items.length });
            timing.failedCount += batchIds.length;
            continue;
        }

        await IOUtils.write(masterPath, batchBytes, { mode: 'append' });
        timing.fileWrite += Date.now() - writeStart;

        timing.processedCount += batchIds.length;
        timing.batchCount++;

        Zotero.debug(`[Export] Batch ${batchNum}: ${timing.processedCount}/${allIds.length}`);

    } catch (e) {
        failedBatches.push({ batch: batchNum, index: i, reason: 'Exception', error: e.message, sampleIds: batchIds.slice(0, 5) });
        timing.failedCount += batchIds.length;
        Zotero.debug(`[Export] Batch ${batchNum} failed: ${e.message}`);
    }

    await yieldToEventLoop(CONFIG.DELAY_MS);
}

// 8. CLEANUP
if (await IOUtils.exists(tempPath)) {
    try {
        await IOUtils.remove(tempPath);
        Zotero.debug("[Export] Temp file removed.");
    } catch (e) {
        Zotero.debug(`[Export] Warning: Could not remove temp file - ${e.message}`);
    }
}

// 9. VERIFICATION
var verifyStart = Date.now();
var verification = { status: 'SKIPPED (DRY RUN)' };

if (!CONFIG.DRY_RUN) {
    Zotero.debug("[Export] Verifying output...");

    verification = {
        expectedItems: allIds.length,
        entriesInFile: 0,
        fileSizeBytes: 0,
        status: 'UNKNOWN'
    };

    try {
        let content = await IOUtils.readUTF8(masterPath);
        verification.fileSizeBytes = content.length;

        // Count BibTeX entries: lines starting with @type{
        verification.entriesInFile = (content.match(/^@\w+\{/gm) || []).length;

        if (verification.entriesInFile === verification.expectedItems) {
            verification.status = 'MATCH';
        } else if (verification.entriesInFile > verification.expectedItems) {
            verification.status = 'EXTRA ENTRIES';
        } else {
            verification.status = 'MISSING ENTRIES';
            verification.missing = verification.expectedItems - verification.entriesInFile;
        }
    } catch (e) {
        verification.status = 'VERIFICATION FAILED';
        verification.error = e.message;
    }
}

timing.verification = Date.now() - verifyStart;

// 10. SUMMARY
timing.total = Date.now() - timing.scriptStart;

// 9b. STATE SAVE
if (CONFIG.RESUME_ENABLED) {
    exportState.stateVersion = 1;
    // Timestamps in exportState use Unix epoch milliseconds (ms since 1970-01-01T00:00:00Z)
    exportState.lastRunAt = Date.now(); 
    exportState.lastRunMode = modeDecision.mode;
    exportState.lastRunReason = modeDecision.reason;

    // Note: lastFullExportAt is not updated yet in commit 1 (behavior unchanged)

    try {
        await IOUtils.writeUTF8(statePath, JSON.stringify(exportState, null, 2));
        Zotero.debug(`[Export] State saved: ${statePath}`);
    } catch (e) {
        Zotero.debug(`[Export] Warning: Could not write state file: ${e.message}`);
    }
}

var summary = {
    mode: CONFIG.DRY_RUN ? 'DRY RUN' : 'FULL EXPORT',
    processed: timing.processedCount,
    failed: timing.failedCount,
    batches: timing.batchCount,
    totalSeconds: (timing.total / 1000).toFixed(1),
    breakdown: {
        preflightMs: timing.preflight,
        itemLoadMs: timing.itemLoad,
        exportMs: timing.export,
        fileWriteMs: timing.fileWrite,
        verificationMs: timing.verification,
        delayMs: CONFIG.DELAY_MS * timing.batchCount
    },
    rates: {
        itemsPerSecond: (timing.processedCount / (timing.total / 1000)).toFixed(1),
        avgBatchMs: timing.batchCount > 0 ? Math.round(timing.total / timing.batchCount) : 0
    },
    verification: verification,
    failedBatches: failedBatches.length > 0 ? failedBatches : 'None'
};

Zotero.debug(`[Export] ${modeLabel}Complete. Verification: ${verification.status}`);

return summary;
