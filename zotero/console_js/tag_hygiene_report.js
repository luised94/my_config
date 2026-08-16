// =============================================================================
// TAG HYGIENE REPORT  (recurring, lean, read-only)
// =============================================================================
// Version: 1.0.0
// Date:    2026-08-12
// Thread:  3 (incoming-item automation).
// Status:  recurring diagnostic the owner runs whenever they want the durable
//          picture of reading-state tag health. Report-only: adds/removes no
//          tag, edits no field, creates no collection (D2).
//
// Scope (deliberately LEAN, owner decision 2026-08-11): only the DURABLE
//          questions worth asking on every run --
//            1. count per workflow tag (reading-state, action, ownership);
//            2. how many top-level regular items have NO opened-state tag
//               (the population the normalizer's R1 would act on);
//            3. CONTRADICTIONS: items carrying __unopened together with a
//               real opened state (__in_progress or __read). Per the settled
//               Q1 rules, __unopened is exclusive with those, so co-presence
//               is a genuine contradiction to surface. (In contrast,
//               __in_progress + __read is a LEGAL revisit combo, and
//               __unopened + __to_read / __unopened + __not_reading are
//               LEGAL, so none of those are flagged.)
//          Historically contingent checks (/unread, manual-vs-auto tag
//          duplication, Read_Status-vs-tags) are NOT here -- they live in the
//          one-time diagnose_thread3_tag_state.js, so this recurring report
//          does not carry dead weight once those situations are resolved
//          (D2 applied to the reports themselves).
//
// Usage:   Tools > Developer > Run JavaScript. CHECK "Run as async function".
//          Read-only; safe to run any time, any number of times.
//
// Method:  Counts come from Zotero.Search 'tag is X' (name-match across manual
//          and auto types -- verified 2026-08-12). The zero-state and
//          contradiction populations need per-item tag inspection, so the
//          union of opened-state-tagged item ids is loaded in batches
//          (getAsync, never getAll) and checked in memory. No writes, so none
//          of the write-path perf concerns apply; the only cost is the scan.
// =============================================================================

// 1. CONFIGURATION
var CONFIG = {
    // Reading-state tags. OPENED_STATE are the three that count as "has a
    // reading state" for R1's guard and for the zero-state count. The full
    // reading-state vocabulary is listed for per-tag counts.
    OPENED_STATE_TAGS: ['__unopened', '__in_progress', '__read'],
    READING_STATE_TAGS: ['__unopened', '__to_read', '__in_progress', '__read', '__not_reading'],
    ACTION_TAGS: ['__add-metadata', '__add-file'],
    OWNERSHIP_TAGS: ['__print'],

    // Contradiction: __unopened present alongside any of these real states.
    // (__in_progress + __read together is a LEGAL revisit combo and is NOT a
    // contradiction; only __unopened co-present with a real state is.)
    UNOPENED_TAG: '__unopened',
    CONTRADICTS_UNOPENED: ['__in_progress', '__read'],

    CONTRADICTION_SAMPLE_MAX: 50,
    ZERO_STATE_SAMPLE_MAX: 50,
    LOAD_BATCH_SIZE: 500,
    YIELD_MS: 10,

    MIN_ZOTERO_VERSION: '7.0',
    MAX_ZOTERO_VERSION: '9.0.6',
    BYPASS_VERSION_CHECK: false
};

// 2. STATE
var timing = { scriptStart: Date.now(), assertions: 0 };
var result = {
    totalTopLevelRegular: 0,
    tagCounts: {},                 // tagName -> item count (name-match)
    zeroOpenedState: 0,            // top-level regular items with none of OPENED_STATE_TAGS
    zeroOpenedStateSample: [],     // { itemID, title }
    contradictions: 0,             // items with __unopened AND a CONTRADICTS_UNOPENED tag
    contradictionByTag: {},        // which state it collides with -> count
    contradictionSample: []        // { itemID, title, collidesWith: [...] }
};

// 3. HELPERS
function assert(condition, message) {
    timing.assertions = timing.assertions + 1;
    if (!condition) { throw new Error(`tag_hygiene_report pre-flight failed: ${message}`); }
}

async function loadItemsInBatchesFromIDs(itemIDs) {
    var loaded = [];
    for (var start = 0; start < itemIDs.length; start = start + CONFIG.LOAD_BATCH_SIZE) {
        var batch = await Zotero.Items.getAsync(itemIDs.slice(start, start + CONFIG.LOAD_BATCH_SIZE));
        for (var bi = 0; bi < batch.length; bi = bi + 1) { loaded.push(batch[bi]); }
        await new Promise(function (r) { setTimeout(r, CONFIG.YIELD_MS); });
    }
    return loaded;
}

async function countItemsWithTag(tagName) {
    var search = new Zotero.Search();
    search.libraryID = Zotero.Libraries.userLibraryID;
    search.addCondition('noChildren', 'true');
    search.addCondition('tag', 'is', tagName);
    var ids = await search.search();
    return ids.length;
}

// 4. PRE-FLIGHT
assert(typeof Zotero !== 'undefined', 'Zotero global unavailable');
assert(typeof Zotero.Search === 'function', 'Zotero.Search unavailable');
assert(typeof Zotero.Items.getAsync === 'function', 'Zotero.Items.getAsync unavailable');
var userLibraryID = Zotero.Libraries.userLibraryID;
assert(typeof userLibraryID === 'number', 'userLibraryID unavailable');

if (!CONFIG.BYPASS_VERSION_CHECK) {
    var zoteroVersion = Zotero.version;
    assert(Services.vc.compare(zoteroVersion, CONFIG.MIN_ZOTERO_VERSION) >= 0,
        `Zotero ${zoteroVersion} below tested floor ${CONFIG.MIN_ZOTERO_VERSION}`);
    if (Services.vc.compare(zoteroVersion, CONFIG.MAX_ZOTERO_VERSION) > 0) {
        Zotero.debug(`tag_hygiene_report: Zotero ${zoteroVersion} above tested ceiling ${CONFIG.MAX_ZOTERO_VERSION}; confirm and bump.`);
    }
}

// 5. MAIN
try {
    // Total top-level regular items (denominator for the zero-state rate).
    var totalSearch = new Zotero.Search();
    totalSearch.libraryID = userLibraryID;
    totalSearch.addCondition('itemType', 'isNot', 'attachment');
    totalSearch.addCondition('itemType', 'isNot', 'note');
    totalSearch.addCondition('itemType', 'isNot', 'annotation');
    var allTopLevelIDs = await totalSearch.search();
    result.totalTopLevelRegular = allTopLevelIDs.length;

    // Per-tag counts (name-match, so manual+auto of the same name sum together).
    var allTrackedTags = []
        .concat(CONFIG.READING_STATE_TAGS)
        .concat(CONFIG.ACTION_TAGS)
        .concat(CONFIG.OWNERSHIP_TAGS);
    for (var ti = 0; ti < allTrackedTags.length; ti = ti + 1) {
        result.tagCounts[allTrackedTags[ti]] = await countItemsWithTag(allTrackedTags[ti]);
    }

    // Zero-opened-state and contradictions both need per-item tag inspection.
    // Only items that carry AT LEAST ONE opened-state tag can be a
    // contradiction, and the zero-state set is exactly the complement, so:
    //   - the union of opened-state-tagged items -> scan for contradictions;
    //   - zero-state count = total - |union of opened-state-tagged|.
    // Build the union of ids carrying any opened-state tag via searches.
    var openedStateIDSet = new Set();
    for (var oi = 0; oi < CONFIG.OPENED_STATE_TAGS.length; oi = oi + 1) {
        var stateSearch = new Zotero.Search();
        stateSearch.libraryID = userLibraryID;
        stateSearch.addCondition('noChildren', 'true');
        stateSearch.addCondition('tag', 'is', CONFIG.OPENED_STATE_TAGS[oi]);
        var stateIDs = await stateSearch.search();
        for (var si = 0; si < stateIDs.length; si = si + 1) { openedStateIDSet.add(stateIDs[si]); }
    }

    result.zeroOpenedState = result.totalTopLevelRegular - openedStateIDSet.size;

    // Zero-state sample: items in allTopLevel not in the opened-state union.
    // Load a bounded number for titles rather than the whole complement.
    var zeroStateIDs = [];
    for (var ai = 0; ai < allTopLevelIDs.length && zeroStateIDs.length < CONFIG.ZERO_STATE_SAMPLE_MAX; ai = ai + 1) {
        if (!openedStateIDSet.has(allTopLevelIDs[ai])) { zeroStateIDs.push(allTopLevelIDs[ai]); }
    }
    var zeroStateItems = await loadItemsInBatchesFromIDs(zeroStateIDs);
    for (var zi = 0; zi < zeroStateItems.length; zi = zi + 1) {
        result.zeroOpenedStateSample.push({ itemID: zeroStateItems[zi].id, title: zeroStateItems[zi].getField('title') });
    }

    // Contradictions: scan only items that carry __unopened (a contradiction
    // requires __unopened present), and check whether they also carry a real
    // state. Loading the __unopened set (large, ~21.6k manual) is the heaviest
    // read here, so it is batched.
    for (var cti = 0; cti < CONFIG.CONTRADICTS_UNOPENED.length; cti = cti + 1) {
        result.contradictionByTag[CONFIG.CONTRADICTS_UNOPENED[cti]] = 0;
    }
    var unopenedSearch = new Zotero.Search();
    unopenedSearch.libraryID = userLibraryID;
    unopenedSearch.addCondition('noChildren', 'true');
    unopenedSearch.addCondition('tag', 'is', CONFIG.UNOPENED_TAG);
    var unopenedIDs = await unopenedSearch.search();
    var unopenedItems = await loadItemsInBatchesFromIDs(unopenedIDs);

    for (var ui = 0; ui < unopenedItems.length; ui = ui + 1) {
        var item = unopenedItems[ui];
        var collidesWith = [];
        for (var cj = 0; cj < CONFIG.CONTRADICTS_UNOPENED.length; cj = cj + 1) {
            if (item.hasTag(CONFIG.CONTRADICTS_UNOPENED[cj])) {
                collidesWith.push(CONFIG.CONTRADICTS_UNOPENED[cj]);
                result.contradictionByTag[CONFIG.CONTRADICTS_UNOPENED[cj]] =
                    result.contradictionByTag[CONFIG.CONTRADICTS_UNOPENED[cj]] + 1;
            }
        }
        if (collidesWith.length > 0) {
            result.contradictions = result.contradictions + 1;
            if (result.contradictionSample.length < CONFIG.CONTRADICTION_SAMPLE_MAX) {
                result.contradictionSample.push({ itemID: item.id, title: item.getField('title'), collidesWith: collidesWith });
            }
        }
    }
} catch (error) {
    Zotero.debug(`tag_hygiene_report FAILED: ${error.message}\n${error.stack}`);
    throw error;
}

// 6. SUMMARY
timing.totalMs = Date.now() - timing.scriptStart;
result.timing = timing;

var lines = [];
lines.push('=== tag_hygiene_report ===');
lines.push(`top-level regular items: ${result.totalTopLevelRegular}`);
lines.push('--- reading-state tag counts (name-match, manual+auto) ---');
for (var r1 = 0; r1 < CONFIG.READING_STATE_TAGS.length; r1 = r1 + 1) {
    lines.push(`  ${CONFIG.READING_STATE_TAGS[r1]}: ${result.tagCounts[CONFIG.READING_STATE_TAGS[r1]]}`);
}
lines.push('--- action / ownership tag counts ---');
for (var a1 = 0; a1 < CONFIG.ACTION_TAGS.length; a1 = a1 + 1) {
    lines.push(`  ${CONFIG.ACTION_TAGS[a1]}: ${result.tagCounts[CONFIG.ACTION_TAGS[a1]]}`);
}
for (var o1 = 0; o1 < CONFIG.OWNERSHIP_TAGS.length; o1 = o1 + 1) {
    lines.push(`  ${CONFIG.OWNERSHIP_TAGS[o1]}: ${result.tagCounts[CONFIG.OWNERSHIP_TAGS[o1]]}`);
}
lines.push('--- health ---');
lines.push(`items with NO opened-state tag (R1 would tag these): ${result.zeroOpenedState}`);
lines.push(`CONTRADICTIONS -- __unopened co-present with a real state: ${result.contradictions}`);
for (var c1 = 0; c1 < CONFIG.CONTRADICTS_UNOPENED.length; c1 = c1 + 1) {
    lines.push(`    __unopened + ${CONFIG.CONTRADICTS_UNOPENED[c1]}: ${result.contradictionByTag[CONFIG.CONTRADICTS_UNOPENED[c1]]}`);
}
for (var cs = 0; cs < result.contradictionSample.length; cs = cs + 1) {
    var c = result.contradictionSample[cs];
    lines.push(`    [${c.itemID}] __unopened+${c.collidesWith.join('+')} :: ${c.title}`);
}
lines.push(`assertions: ${timing.assertions}  elapsed ms: ${timing.totalMs}`);
for (var li = 0; li < lines.length; li = li + 1) { Zotero.debug(lines[li]); }

return result;
