// =============================================================================
// REFRESH BETTER BIBTEX CITATION KEYS (dry-run + execute)
// =============================================================================
// Version: 1.0.0
// Date:    2026-07
// Purpose: Report which BBT citation keys would change if recomputed
//          (current vs propose()), and optionally apply the refresh via
//          BBT's own KeyManager.fill(). Emits an old->new map + sed lines
//          so external @citekey references can be updated.
//
// Usage:   Tools > Developer > Run JavaScript.  CHECK "Run as async function".
//          DRY_RUN default: computes the diff, writes nothing.
//          DRY_RUN=false: calls km.fill(ids,{replace:true,warn:true}) --
//          BBT shows its OWN bulk-modify confirmation before writing.
//
// Safety:  propose() is pure (verified: it does not call store()). The write
//          path (fill/update) skips pinned/readonly items internally, so the
//          apply is pin-safe regardless of this script's pin estimate.
//
// !! Changing a citekey breaks external docs that cite the OLD key.        !!
//    The returned `changes` + `sedLines` are your remap for those docs.
// =============================================================================

// 1. CONFIGURATION
var CONFIG = {
    DRY_RUN: true,
    ITEM_CHUNK: 500,          // items loaded per batch
    YIELD_EVERY_CHUNKS: 1,
    DELAY_MS: 15,
    CHANGES_MAX: 8000,        // cap on echoed changes (should be small)
    UNCHANGED_SAMPLE_MAX: 20,

    MIN_ZOTERO_VERSION: '7.0',
    MAX_ZOTERO_VERSION: '9.0.6',
    BYPASS_VERSION_CHECK: false
};

// 2. STATE
var timing = {
    scriptStart: Date.now(), assertions: 0, scanMs: 0, applyMs: 0,
    yieldCount: 0, total: 0, unchanged: 0,
    changedUnpinned: 0, changedPinned: 0, noProposal: 0
};
var changes = [];             // { itemID, from, to, pinned }
var unchangedSample = [];
var debugLines = [];

// 3. HELPERS
function report(l) { debugLines.push(l); Zotero.debug(`[bbt_refresh] ${l}`); }
function assert(c, m) { timing.assertions++; if (!c) throw new Error(`bbt_refresh pre-flight failed: ${m}`); }
async function yieldToEventLoop() { timing.yieldCount++; await new Promise(r => setTimeout(r, CONFIG.DELAY_MS)); }

function proposedKeyOf(item, km) {
    var p = km.propose(item);
    if (p == null) return null;
    if (typeof p === 'string') return p;
    if (typeof p === 'object' && typeof p.citationKey === 'string') return p.citationKey;
    return String(p);
}
// Best-effort pin detection (report estimate only; fill() enforces the truth).
function isPinned(item) {
    var extra = '';
    try { extra = item.getField('extra') || ''; } catch (e) {}
    return /(^|\n)\s*Citation Key\s*:/i.test(extra);
}

try {

// 4. PRE-FLIGHT
report(`version 1.0.0 starting, Zotero ${Zotero.version}, DRY_RUN=${CONFIG.DRY_RUN}`);
var belowMin = Services.vc.compare(Zotero.version, CONFIG.MIN_ZOTERO_VERSION) < 0;
var aboveMax = Services.vc.compare(Zotero.version, CONFIG.MAX_ZOTERO_VERSION) > 0;
if ((belowMin || aboveMax) && !CONFIG.BYPASS_VERSION_CHECK) {
    throw new Error(`Zotero ${Zotero.version} outside tested range; set BYPASS_VERSION_CHECK.`);
}
assert(typeof Zotero.BetterBibTeX !== 'undefined', 'Better BibTeX not present');
var km = Zotero.BetterBibTeX.KeyManager;
assert(km && typeof km.propose === 'function', 'KeyManager.propose unavailable');
assert(typeof km.all === 'function', 'KeyManager.all unavailable');
assert(typeof km.fill === 'function', 'KeyManager.fill unavailable');
assert(typeof Zotero.Items.getAsync === 'function', 'Zotero.Items.getAsync unavailable');

// 5. MAIN
// --- 5a. Current keys from the BBT cache -------------------------------------
var records = Array.from(km.all());
report(`BBT cache holds ${records.length} keys`);
var currentByID = new Map();
var allIDs = [];
for (var rec of records) {
    currentByID.set(rec.itemID, rec.citationKey);
    allIDs.push(rec.itemID);
}

// --- 5b. Propose per item, in batches ----------------------------------------
var scanStart = Date.now();
var chunkIndex = 0;
for (var i = 0; i < allIDs.length; i += CONFIG.ITEM_CHUNK) {
    var idChunk = allIDs.slice(i, i + CONFIG.ITEM_CHUNK);
    var items = await Zotero.Items.getAsync(idChunk);
    for (var item of items) {
        if (!item || !item.isRegularItem()) continue;
        timing.total++;
        var current = currentByID.get(item.id) || '';
        var proposed = proposedKeyOf(item, km);
        if (proposed == null) { timing.noProposal++; continue; }
        if (proposed === current) {
            timing.unchanged++;
            if (unchangedSample.length < CONFIG.UNCHANGED_SAMPLE_MAX) {
                unchangedSample.push({ itemID: item.id, key: current });
            }
            continue;
        }
        var pinned = isPinned(item);
        if (pinned) timing.changedPinned++; else timing.changedUnpinned++;
        if (changes.length < CONFIG.CHANGES_MAX) {
            changes.push({ itemID: item.id, from: current, to: proposed, pinned: pinned });
        }
    }
    chunkIndex++;
    if (chunkIndex % CONFIG.YIELD_EVERY_CHUNKS === 0) await yieldToEventLoop();
}
timing.scanMs = Date.now() - scanStart;
report(`scan done: ${timing.total} items; ${timing.unchanged} unchanged, ` +
    `${timing.changedUnpinned} would change (unpinned), ` +
    `${timing.changedPinned} differ but PINNED (fill skips these), ` +
    `${timing.noProposal} no proposal; ${timing.scanMs} ms`);

// sed lines for pandoc-style @citekey remap (unpinned changes only)
var sedLines = changes
    .filter(c => !c.pinned)
    .map(c => `s/@${c.from}\\b/@${c.to}/g`);

// --- 5c. Plan / apply --------------------------------------------------------
report('PLAN:');
report(`  refresh would rewrite ~${timing.changedUnpinned} unpinned key(s)`);
report('  apply calls km.fill(ids,{replace:true,warn:true}); BBT confirms + is pin-safe');

if (CONFIG.DRY_RUN) {
    report('DRY_RUN: nothing written. Review `changes` and `sedLines` in the return value.');
} else {
    var applyStart = Date.now();
    report('applying via KeyManager.fill(replace:true) -- BBT bulk-modify dialog may appear');
    await km.fill(allIDs, { replace: true, warn: true });
    timing.applyMs = Date.now() - applyStart;
    report(`fill() returned in ${timing.applyMs} ms`);
    report('Verify a few items, then use sedLines from the PRECEDING dry-run to fix docs.');
}

} catch (e) {
    Zotero.debug(`[bbt_refresh] ERROR: ${e.message}\n${e.stack}`);
    throw e;
}

// 6. SUMMARY
timing.totalMs = Date.now() - timing.scriptStart;
report(`done in ${timing.totalMs} ms, assertions ${timing.assertions}, yields ${timing.yieldCount}`);
return {
    dryRun: CONFIG.DRY_RUN,
    totalItems: timing.total,
    unchanged: timing.unchanged,
    changedUnpinned: timing.changedUnpinned,
    changedPinnedSkipped: timing.changedPinned,
    noProposal: timing.noProposal,
    changesTruncated: timing.changedUnpinned + timing.changedPinned > CONFIG.CHANGES_MAX,
    changes: changes,
    sedLines: sedLines,
    unchangedSample: unchangedSample,
    timing: timing
};
