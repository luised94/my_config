// =============================================================================
// ZOTERO BETTER BIBTEX CITATION KEY REFRESH
// =============================================================================
// Version: 1.3
// Purpose: Refresh BBT citation keys for all regular items in library
// Usage:   Tools > Developer > Run JavaScript (Zotero 7)
//
// Features:
//   - Batched processing to avoid UI freezes
//   - Pre-flight validation (API checks, count cross-check)
//   - Optional change capture (before/after keys)
//   - Timing instrumentation for performance analysis
//   - Continues on individual item failures
//
// Output:  Returns summary object with timing breakdown and any failures
// =============================================================================

// 1. CONFIGURATION
var CONFIG = {
    HARD_CAP: 70000,            // Safety limit - abort if library exceeds this
    MAX_TO_PROCESS: 10000,      // null for full run, N for first N items
    BATCH_SIZE: 15,             // Items per batch
    YIELD_MS: 500,              // Pause between batches for UI responsiveness
    ENABLE_DEBUG_LOGS: false,   // Verbose logging
    LOG_EVERY: 250,             // Progress interval when debug enabled
    CAPTURE_CHANGES: false,     // Track before/after keys (slower)
    MAX_CHANGED_RETURN: 5       // Limit captured changes in result
};

// 2. STATE
var timing = {
    scriptStart: Date.now(),
    assertions: 0,
    search: 0,
    sqlCheck: 0,
    itemLoad: 0,
    keyRefresh: 0,
    batchCount: 0,
    processedCount: 0,
    failedCount: 0
};

var failed = [];
var changed = [];
var planned = 0;

// 3. HELPERS
var debugLog = (msg) => { if (CONFIG.ENABLE_DEBUG_LOGS) Zotero.debug(msg); };

// 4. ASSERTIONS
var assertStart = Date.now();
Zotero.debug("[BBT Refresh] Running assertions...");

if (!Zotero?.Search || !Zotero?.DB || !Zotero?.Items?.getAsync) {
    throw new Error("Missing Zotero APIs (Search/DB/Items.getAsync)");
}
if (!Zotero?.BetterBibTeX?.KeyManager?.update) {
    throw new Error("BBT KeyManager.update missing");
}
if (CONFIG.CAPTURE_CHANGES && typeof Zotero.BetterBibTeX.KeyManager.get !== "function") {
    throw new Error("BBT KeyManager.get missing (needed for CAPTURE_CHANGES)");
}

timing.assertions = Date.now() - assertStart;

// 5. SEARCH REGULAR ITEMS
var searchStart = Date.now();

var search = new Zotero.Search();
search.libraryID = Zotero.Libraries.userLibraryID;
search.addCondition("itemType", "isNot", "attachment");
search.addCondition("itemType", "isNot", "note");
search.addCondition("itemType", "isNot", "annotation");

var itemIDs = await search.search();

if (!Array.isArray(itemIDs) || itemIDs.some(id => typeof id !== "number")) {
    throw new Error("Search did not return integer itemIDs");
}

timing.search = Date.now() - searchStart;

// 6. SQL CROSS-CHECK
var sqlStart = Date.now();

var libraryID = Zotero.Libraries.userLibraryID;
var sqlCount = await Zotero.DB.valueQueryAsync(`
    SELECT COUNT(*)
    FROM items i
    JOIN itemTypes it ON it.itemTypeID = i.itemTypeID
    WHERE i.libraryID = ?
      AND i.itemID NOT IN (SELECT itemID FROM deletedItems)
      AND it.typeName NOT IN ('attachment','note','annotation')
`, [libraryID]);

if (itemIDs.length !== sqlCount) {
    throw new Error(`Count mismatch: Search=${itemIDs.length} vs SQL=${sqlCount}`);
}
if (itemIDs.length > CONFIG.HARD_CAP) {
    throw new Error(`Hard cap exceeded: ${itemIDs.length} > ${CONFIG.HARD_CAP}`);
}

timing.sqlCheck = Date.now() - sqlStart;

// 7. APPLY RUN LIMIT
planned = (CONFIG.MAX_TO_PROCESS == null) ? itemIDs.length : Math.min(CONFIG.MAX_TO_PROCESS, itemIDs.length);
itemIDs = itemIDs.slice(0, planned);

Zotero.debug(`[BBT Refresh] Assertions passed. Processing ${planned}/${sqlCount} items in batches of ${CONFIG.BATCH_SIZE}.`);

// 8. MAIN LOOP
for (let i = 0; i < itemIDs.length; i += CONFIG.BATCH_SIZE) {
    var batchIds = itemIDs.slice(i, i + CONFIG.BATCH_SIZE);
    var batchNum = Math.floor(i / CONFIG.BATCH_SIZE) + 1;
    
    if (Zotero.isShuttingDown) break;
    
    try {
        var loadStart = Date.now();
        var items = await Zotero.Items.getAsync(batchIds);
        timing.itemLoad += Date.now() - loadStart;
        
        for (const item of items) {
            if (!item || typeof item.isRegularItem !== "function" || !item.isRegularItem()) continue;
            
            try {
                var beforeKey = null;
                if (CONFIG.CAPTURE_CHANGES && changed.length < CONFIG.MAX_CHANGED_RETURN) {
                    beforeKey = Zotero.BetterBibTeX.KeyManager.get(item.id)?.citationKey ?? null;
                }
                
                var refreshStart = Date.now();
                await Zotero.BetterBibTeX.KeyManager.update(item);
                timing.keyRefresh += Date.now() - refreshStart;
                
                if (CONFIG.CAPTURE_CHANGES && changed.length < CONFIG.MAX_CHANGED_RETURN) {
                    var afterKey = Zotero.BetterBibTeX.KeyManager.get(item.id)?.citationKey ?? null;
                    if (beforeKey !== afterKey) {
                        changed.push({
                            itemID: item.id,
                            itemKey: item.key,
                            title: item.getField("title"),
                            before: beforeKey,
                            after: afterKey
                        });
                    }
                }
                
                timing.processedCount++;
                
            } catch (itemErr) {
                failed.push({ itemID: item.id, error: itemErr.message });
                timing.failedCount++;
                debugLog(`[BBT Refresh] Item ${item.id} failed: ${itemErr.message}`);
            }
        }
        
        timing.batchCount++;
        
        if (CONFIG.ENABLE_DEBUG_LOGS && timing.processedCount % CONFIG.LOG_EVERY === 0) {
            debugLog(`[BBT Refresh] Progress: ${timing.processedCount}/${planned}`);
        }
        
    } catch (batchErr) {
        failed.push({ batch: batchNum, sampleIds: batchIds.slice(0, 5), error: batchErr.message });
        timing.failedCount += batchIds.length;
        Zotero.debug(`[BBT Refresh] Batch ${batchNum} failed: ${batchErr.message}`);
    }
    
    await Zotero.Promise.delay(CONFIG.YIELD_MS);
}

// 9. SUMMARY
timing.total = Date.now() - timing.scriptStart;

var summary = {
    processed: timing.processedCount,
    planned: planned,
    failed: timing.failedCount,
    batches: timing.batchCount,
    totalSeconds: (timing.total / 1000).toFixed(1),
    breakdown: {
        assertionsMs: timing.assertions,
        searchMs: timing.search,
        sqlCheckMs: timing.sqlCheck,
        itemLoadMs: timing.itemLoad,
        keyRefreshMs: timing.keyRefresh,
        delayMs: CONFIG.YIELD_MS * timing.batchCount
    },
    rates: {
        itemsPerSecond: (timing.processedCount / (timing.total / 1000)).toFixed(1),
        avgRefreshMs: timing.processedCount > 0 ? (timing.keyRefresh / timing.processedCount).toFixed(2) : 0
    },
    failedBatches: failed.length > 0 ? failed : 'None'
};

if (CONFIG.CAPTURE_CHANGES) {
    summary.changedCaptured = changed.length;
    summary.changed = changed;
}

Zotero.debug(`[BBT Refresh] Complete. ${timing.processedCount}/${planned} in ${summary.totalSeconds}s (${summary.rates.itemsPerSecond} items/sec)`);

return summary;
