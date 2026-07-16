// STATUS: COMPLETED SPIKE (thread 2). Run once on Zotero 9.0.6, 2026-07.
// Not maintained. Kept for reference and re-runnability. Findings are
// recorded in handoff/02_orphan_pipeline.md "Verified facts". Re-run only
// to re-confirm on a newer Zotero; bump MAX_ZOTERO_VERSION if you do.
// =============================================================================
// SPIKE S2: LINKED-ATTACHMENT BASE DIRECTORY WALK AT SCALE
// =============================================================================
// Version: 1.1
// Purpose: Verify IOUtils directory enumeration behavior at 60k+ files for
//          the orphan auditor (handoff/02): wall time, throughput, per-call
//          memory bound (largest directory child count), file/dir counts,
//          extension histogram, non-ASCII path count, ignore-list hits.
// Usage:   Tools > Developer > Run JavaScript (Zotero 7+).
//          CHECK THE "Run as async function" CHECKBOX. Paste, run, paste
//          the returned summary back into handoff/02 Verified facts.
// Safety:  Report-only. Zero writes anywhere. Enumerates names and calls
//          IOUtils.stat only (metadata; never reads file contents), so
//          Dropbox online-only placeholders must not be hydrated. VERIFY
//          after the run: spot-check a few known online-only files still
//          show the online-only badge (S3 tests this rigorously).
// Output:  Returns summary object; checkpoints to Zotero.debug.
// Changes in 1.1: no async IIFE (console does not await it; return value was
//          lost, errors were silent); top-level await with loud try/catch;
//          yield keyed to ENTRY count instead of directory count (v1.0 slept
//          ~34 s because this library has ~28k directories); checkpoints
//          report per-interval rate, not cumulative; single-use helpers
//          inlined per convention; MAX_ZOTERO_VERSION 9.0.6.
// =============================================================================

// 1. CONFIGURATION
var CONFIG = {
    BASE_PATH: '',               // '' = derive from Zotero baseAttachmentPath pref
    MAX_ENTRIES: 250000,         // hard cap; abort enumeration beyond this
    YIELD_EVERY_ENTRIES: 2000,   // event-loop yield after this many entries
    DELAY_MS: 15,                // yield duration
    CHECKPOINT_EVERY: 5000,      // debug-log progress every N entries
    MAX_CONSECUTIVE_FAILURES: 20,
    TOP_EXTENSIONS: 20,          // extensions reported in histogram
    LARGEST_DIRS_REPORTED: 10,   // directories with most direct children
    NONASCII_EXAMPLES_MAX: 10,
    // Ignore list per handoff/02; matched case-insensitively on file name.
    IGNORE_EXACT: ['desktop.ini', 'thumbs.db', '.ds_store'],
    IGNORE_PREFIX: ['.dropbox', '~$'],
    IGNORE_SUFFIX: ['.tmp'],
    MIN_ZOTERO_VERSION: '7.0',
    MAX_ZOTERO_VERSION: '9.0.6', // confirmed on 9.0.6 (spike run 2026-07)
    BYPASS_VERSION_CHECK: false
};

// 2. STATE
var timing = {
    scriptStart: Date.now(),
    assertions: 0,
    dirCount: 0,
    fileCount: 0,
    ignoredCount: 0,
    nonAsciiCount: 0,
    totalBytes: 0,
    entryCount: 0,
    statFailures: 0,
    consecutiveFailures: 0,
    maxDepth: 0,
    yieldCount: 0
};
var extensionCounts = {};
var largestDirs = [];        // {path, childCount}, trimmed to top N at the end
var nonAsciiPaths = [];
var failures = [];           // bounded sample of {path, error}
var aborted = null;
var lastCheckpointMs = Date.now();

// 3. HELPERS
function assert(condition, message) {
    timing.assertions = timing.assertions + 1;
    if (!condition) {
        throw new Error(`S2 pre-flight failed: ${message}`);
    }
}

try {

// 4. PRE-FLIGHT
var belowMin = Services.vc.compare(Zotero.version, CONFIG.MIN_ZOTERO_VERSION) < 0;
var aboveMax = Services.vc.compare(Zotero.version, CONFIG.MAX_ZOTERO_VERSION) > 0;
if ((belowMin || aboveMax) && !CONFIG.BYPASS_VERSION_CHECK) {
    throw new Error(`Zotero ${Zotero.version} outside tested range ` +
        `${CONFIG.MIN_ZOTERO_VERSION}..${CONFIG.MAX_ZOTERO_VERSION}. ` +
        `Set CONFIG.BYPASS_VERSION_CHECK = true to override.`);
}
assert(typeof IOUtils !== 'undefined' && typeof IOUtils.getChildren === 'function',
    'IOUtils.getChildren unavailable (requires Zotero 7+)');

var basePath = CONFIG.BASE_PATH;
if (basePath === '') {
    basePath = Zotero.Prefs.get('baseAttachmentPath');
}
assert(typeof basePath === 'string' && basePath.length > 0,
    'No base path: set CONFIG.BASE_PATH or the Zotero linked attachment base directory pref');
var baseExists = await IOUtils.exists(basePath);
assert(baseExists, `Base path does not exist: ${basePath}`);
Zotero.debug(`[S2] walking base: ${basePath}`);

// 5. MAIN: iterative walk, one getChildren call per directory
var stack = [{ path: basePath, depth: 0 }];
var entriesSinceYield = 0;

while (stack.length > 0) {
    if (timing.entryCount >= CONFIG.MAX_ENTRIES) {
        aborted = `hit MAX_ENTRIES cap (${CONFIG.MAX_ENTRIES})`;
        break;
    }
    if (timing.consecutiveFailures >= CONFIG.MAX_CONSECUTIVE_FAILURES) {
        aborted = `hit MAX_CONSECUTIVE_FAILURES (${CONFIG.MAX_CONSECUTIVE_FAILURES})`;
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
        if (failures.length < 25) {
            failures.push({ path: current.path, error: e.message });
        }
        continue;
    }

    timing.dirCount = timing.dirCount + 1;
    largestDirs.push({ path: current.path, childCount: children.length });
    if (largestDirs.length > 200) {
        // Keep memory bounded: sort desc and trim occasionally.
        largestDirs.sort((a, b) => b.childCount - a.childCount);
        largestDirs.length = CONFIG.LARGEST_DIRS_REPORTED;
    }
    if (current.depth > timing.maxDepth) {
        timing.maxDepth = current.depth;
    }

    for (var childPath of children) {
        timing.entryCount = timing.entryCount + 1;
        entriesSinceYield = entriesSinceYield + 1;
        var stat = null;
        try {
            // Metadata only; never reads contents (no hydration).
            stat = await IOUtils.stat(childPath);
            timing.consecutiveFailures = 0;
        } catch (e) {
            timing.statFailures = timing.statFailures + 1;
            timing.consecutiveFailures = timing.consecutiveFailures + 1;
            if (failures.length < 25) {
                failures.push({ path: childPath, error: e.message });
            }
            continue;
        }
        if (stat.type === 'directory') {
            stack.push({ path: childPath, depth: current.depth + 1 });
        } else {
            timing.fileCount = timing.fileCount + 1;
            timing.totalBytes = timing.totalBytes + stat.size;

            // Inline: file name and extension (single textual call site each).
            var slashNormalized = childPath.replace(/\\/g, '/');
            var fileName = slashNormalized.slice(slashNormalized.lastIndexOf('/') + 1);
            var nameLower = fileName.toLowerCase();
            var dotIdx = fileName.lastIndexOf('.');
            var ext = '(none)';
            if (dotIdx > 0) {
                ext = fileName.slice(dotIdx).toLowerCase();
            }

            // Inline: ignore-list match (single textual call site).
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
            }

            if (extensionCounts[ext] === undefined) {
                extensionCounts[ext] = 0;
            }
            extensionCounts[ext] = extensionCounts[ext] + 1;

            if (/[^\x00-\x7F]/.test(childPath)) {
                timing.nonAsciiCount = timing.nonAsciiCount + 1;
                if (nonAsciiPaths.length < CONFIG.NONASCII_EXAMPLES_MAX) {
                    nonAsciiPaths.push(childPath);
                }
            }
        }

        if (timing.entryCount % CONFIG.CHECKPOINT_EVERY === 0) {
            var nowMs = Date.now();
            var intervalRate = Math.round(CONFIG.CHECKPOINT_EVERY / ((nowMs - lastCheckpointMs) / 1000));
            lastCheckpointMs = nowMs;
            Zotero.debug(`[S2] checkpoint: ${timing.entryCount} entries, ` +
                `${timing.fileCount} files, ${timing.dirCount} dirs, ` +
                `${intervalRate}/s over last interval`);
        }
        if (entriesSinceYield >= CONFIG.YIELD_EVERY_ENTRIES) {
            entriesSinceYield = 0;
            timing.yieldCount = timing.yieldCount + 1;
            // Inline event-loop yield (single call site).
            await new Promise(resolve => setTimeout(resolve, CONFIG.DELAY_MS));
        }
    }
}

} catch (e) {
    // Loud failure: log and rethrow so the console shows it.
    Zotero.debug(`[S2] ERROR: ${e.message}\n${e.stack}`);
    throw e;
}

// 6. SUMMARY
timing.totalMs = Date.now() - timing.scriptStart;
largestDirs.sort((a, b) => b.childCount - a.childCount);
largestDirs.length = Math.min(largestDirs.length, CONFIG.LARGEST_DIRS_REPORTED);

var extensionTable = [];
for (var key of Object.keys(extensionCounts)) {
    extensionTable.push({ extension: key, count: extensionCounts[key] });
}
extensionTable.sort((a, b) => b.count - a.count);
extensionTable.length = Math.min(extensionTable.length, CONFIG.TOP_EXTENSIONS);

var summary = {
    zoteroVersion: Zotero.version,
    basePath: basePath,
    aborted: aborted,
    timing: timing,
    entriesPerSecond: Math.round(timing.entryCount / (timing.totalMs / 1000)),
    sleptMs: timing.yieldCount * CONFIG.DELAY_MS,
    totalGB: Math.round(timing.totalBytes / 1e9 * 100) / 100,
    extensionTable: extensionTable,
    largestDirs: largestDirs,
    nonAsciiPaths: nonAsciiPaths,
    failures: failures,
    note: 'getChildren returns a full array per directory; largestDirs bounds per-call memory. Verify a few online-only files kept their badge after this run.'
};
Zotero.debug(`[S2] done: ${timing.fileCount} files, ${timing.dirCount} dirs, ` +
    `${summary.totalGB} GB, ${timing.totalMs} ms (${summary.sleptMs} ms slept), ` +
    `${summary.entriesPerSecond}/s` +
    `${aborted !== null ? ', ABORTED: ' + aborted : ''}`);
return summary;
