// =============================================================================
// ZOTERO BETTER BIBTEX CITATION KEY REFRESH
// =============================================================================
// Version: 2.1
// Purpose: Refresh BBT citation keys for all regular items in library
// Usage:   Tools > Developer > Run JavaScript (Zotero 7)
//
// Features:
//   - Batched processing with adaptive throttling
//   - Per-item timeout guard (prevents infinite hangs)
//   - Transaction wrapper for DB safety
//   - Checkpoint logging for crash recovery (use START_INDEX to resume)
//   - Consecutive failure abort (detects unhealthy state)
//   - Canary logging for freeze diagnosis (enable ENABLE_DEBUG_LOGS)
//
// Validation protocol:
//   1. Run with MAX_TO_PROCESS: 1000, verify stable
//   2. Increase to 5000, verify stable
//   3. Increase to 10000, verify stable
//   4. Set to null for full library run
//
// Output:  Returns summary object with timing, throttling stats, and failures
// =============================================================================

// 1. CONFIGURATION
var CONFIG = {
    HARD_CAP: 70000,            // Safety limit - abort if library exceeds this
    MAX_TO_PROCESS: 1000,       // Start with 1000, increase after stable: 5000  10000  null (full)
    BATCH_SIZE: 15,             // Items per batch
    YIELD_MS: 500,              // Pause between batches for UI responsiveness
    ITEM_TIMEOUT_MS: 30000,     // 30s max per item before skip
    USE_TRANSACTION_WRAPPER: true,  // Wrap updates in executeTransaction
    BASE_YIELD_MS: 100,         // Starting delay between batches
    MAX_YIELD_MS: 10000,        // Cap for adaptive backoff (increased for heavy loads)
    SLOW_BATCH_MS: 1000,        // Batch duration that triggers backoff
    GC_EVERY: 2000,             // Force garbage collection every N items (0 to disable)
    ENABLE_DEBUG_LOGS: false,   // Verbose logging
    LOG_EVERY: 500,             // Progress interval when debug enabled
    CAPTURE_CHANGES: false,     // Track before/after keys (slower)
    MAX_CHANGED_RETURN: 5,      // Limit captured changes in result
    START_INDEX: 0,             // Resume from this index after crash
    CHECKPOINT_EVERY: 500,      // Log checkpoint for resume every N items
    MAX_CONSECUTIVE_FAILURES: 10  // Abort if this many items fail in a row
};

// 2. STATE
var timing = {
    scriptStart: Date.now(),
    assertions: 0,
    search: 0,
    sqlCheck: 0,
    itemLoad: 0,
    keyRefresh: 0,
    totalYieldMs: 0,
    batchCount: 0,
    processedCount: 0,
    failedCount: 0,
    timeoutCount: 0,
    backoffCount: 0,
    gcCount: 0
};

var failed = [];
var changed = [];
var planned = 0;
var currentYieldMs = CONFIG.BASE_YIELD_MS;
var consecutiveFailures = 0;
var aborted = false;

// 3. HELPERS
var debugLog = (msg) => { if (CONFIG.ENABLE_DEBUG_LOGS) Zotero.debug(msg); };

var withTimeout = (promise, ms, label) => {
    return Promise.race([
        promise,
        new Promise((_, reject) => 
            setTimeout(() => reject(new Error(`Timeout after ${ms}ms: ${label}`)), ms)
        )
    ]);
};

var yieldToEventLoop = (ms) => new Promise(resolve => setTimeout(resolve, ms));

var gcAvailable = typeof Components !== 'undefined' && typeof Components.utils?.forceGC === 'function';

var tryForceGC = () => {
    if (gcAvailable) {
        try { 
            Components.utils.forceGC(); 
            return true;
        } catch (e) { 
            return false; 
        }
    }
    return false;
};

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

if (CONFIG.USE_TRANSACTION_WRAPPER && typeof Zotero.DB.executeTransaction !== "function") {
    throw new Error("Zotero.DB.executeTransaction not available");
}

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
if (CONFIG.START_INDEX > 0) {
    Zotero.debug(`[BBT Refresh] Resuming from index ${CONFIG.START_INDEX}`);
}

// 8. MAIN LOOP
for (let i = CONFIG.START_INDEX; i < itemIDs.length; i += CONFIG.BATCH_SIZE) {
    var batchIds = itemIDs.slice(i, i + CONFIG.BATCH_SIZE);
    var batchNum = Math.floor(i / CONFIG.BATCH_SIZE) + 1;
    var batchStart = Date.now();
    
    if (Zotero.isShuttingDown) break;
    if (aborted) break;
    
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
                var updateFn = async () => {
                    await Zotero.BetterBibTeX.KeyManager.update(item);
                };
                
                if (CONFIG.USE_TRANSACTION_WRAPPER) {
                    await withTimeout(
                        Zotero.DB.executeTransaction(updateFn),
                        CONFIG.ITEM_TIMEOUT_MS,
                        `item ${item.id}`
                    );
                } else {
                    await withTimeout(
                        updateFn(),
                        CONFIG.ITEM_TIMEOUT_MS,
                        `item ${item.id}`
                    );
                }
                timing.keyRefresh += Date.now() - refreshStart;
                
                consecutiveFailures = 0;  // Reset on success
                
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
                consecutiveFailures++;
                timing.failedCount++;
                
                if (itemErr.message?.startsWith('Timeout after')) {
                    timing.timeoutCount++;
                    failed.push({ itemID: item.id, error: itemErr.message });
                    Zotero.debug(`[BBT Refresh] TIMEOUT: Item ${item.id} exceeded ${CONFIG.ITEM_TIMEOUT_MS}ms`);
                } else {
                    failed.push({ itemID: item.id, error: itemErr.message });
                    debugLog(`[BBT Refresh] Item ${item.id} failed: ${itemErr.message}`);
                }
                
                if (consecutiveFailures >= CONFIG.MAX_CONSECUTIVE_FAILURES) {
                    Zotero.debug(`[BBT Refresh] ABORT: ${consecutiveFailures} consecutive failures. Last index: ${i}`);
                    aborted = true;
                    break;
                }
            }
        }
        
        timing.batchCount++;
        
        // Checkpoint logging for crash recovery
        if (timing.processedCount % CONFIG.CHECKPOINT_EVERY === 0 && timing.processedCount > 0) {
            Zotero.debug(`[BBT Refresh] CHECKPOINT: processed=${timing.processedCount}, nextIndex=${i + CONFIG.BATCH_SIZE}, failed=${timing.failedCount}`);
        }
        
        // Garbage collection hint to reduce memory pressure
        if (CONFIG.GC_EVERY > 0 && timing.processedCount % CONFIG.GC_EVERY === 0 && timing.processedCount > 0) {
            if (tryForceGC()) {
                timing.gcCount++;
                debugLog(`[BBT Refresh] GC forced at ${timing.processedCount} items`);
            }
        }
        
        if (CONFIG.ENABLE_DEBUG_LOGS && timing.processedCount % CONFIG.LOG_EVERY === 0) {
            debugLog(`[BBT Refresh] Progress: ${timing.processedCount}/${planned}`);
        }
        
    } catch (batchErr) {
        failed.push({ batch: batchNum, sampleIds: batchIds.slice(0, 5), error: batchErr.message });
        timing.failedCount += batchIds.length;
        Zotero.debug(`[BBT Refresh] Batch ${batchNum} failed: ${batchErr.message}`);
    }
    
    // Adaptive throttling
    var batchDuration = Date.now() - batchStart;
    if (batchDuration > CONFIG.SLOW_BATCH_MS) {
        // Batch was slow - back off
        currentYieldMs = Math.min(currentYieldMs * 1.5, CONFIG.MAX_YIELD_MS);
        timing.backoffCount++;
        Zotero.debug(`[BBT Refresh] Backoff: batch ${batchNum} took ${batchDuration}ms, yield now ${Math.round(currentYieldMs)}ms`);
    } else if (batchDuration < 200 && currentYieldMs > CONFIG.BASE_YIELD_MS) {
        // Batch was fast and we're above base - recover slowly
        currentYieldMs = Math.max(currentYieldMs * 0.9, CONFIG.BASE_YIELD_MS);
    }
    // Else: batch was moderate or we're at base - hold steady
    
    timing.totalYieldMs += currentYieldMs;
    
    // Canary logging - diagnose freezes
    debugLog(`[BBT Refresh] Batch ${batchNum} done (${batchDuration}ms). Yielding ${Math.round(currentYieldMs)}ms...`);
    await yieldToEventLoop(currentYieldMs);
    debugLog(`[BBT Refresh] Batch ${batchNum} yield complete. Continuing...`);
}

// 9. SUMMARY
timing.total = Date.now() - timing.scriptStart;

var summary = {
    status: aborted ? 'ABORTED' : 'COMPLETE',
    processed: timing.processedCount,
    planned: planned,
    libraryTotal: sqlCount,
    coverage: ((planned / sqlCount) * 100).toFixed(1) + '%',
    failed: timing.failedCount,
    timeouts: timing.timeoutCount,
    batches: timing.batchCount,
    totalSeconds: (timing.total / 1000).toFixed(1),
    breakdown: {
        assertionsMs: timing.assertions,
        searchMs: timing.search,
        sqlCheckMs: timing.sqlCheck,
        itemLoadMs: timing.itemLoad,
        keyRefreshMs: timing.keyRefresh,
        totalYieldMs: Math.round(timing.totalYieldMs)
    },
    rates: {
        itemsPerSecond: (timing.processedCount / (timing.total / 1000)).toFixed(1),
        avgRefreshMs: timing.processedCount > 0 ? (timing.keyRefresh / timing.processedCount).toFixed(2) : 0
    },
    throttling: {
        startYieldMs: CONFIG.BASE_YIELD_MS,
        finalYieldMs: Math.round(currentYieldMs),
        backoffEvents: timing.backoffCount,
        gcEvents: timing.gcCount
    },
    failedBatches: failed.length > 0 ? failed : 'None'
};

if (CONFIG.CAPTURE_CHANGES) {
    summary.changedCaptured = changed.length;
    summary.changed = changed;
}

Zotero.debug(`[BBT Refresh] ${summary.status}. ${timing.processedCount}/${planned} (${summary.coverage} of library) in ${summary.totalSeconds}s`);

return summary;
