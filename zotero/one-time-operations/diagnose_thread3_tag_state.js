// =============================================================================
// DIAGNOSE THREAD-3 TAG STATE (three one-time checks)
// =============================================================================
// Version: 1.0.0
// Date:    2026-08-11
// Thread:  3 (incoming-item automation). ONE-TIME diagnostics, NOT recurring
//          tools. Report-only; this file writes NOTHING to the library.
// Status:  owner action to run NOW, before migrate_slash_unread.js and before
//          deciding what to do about the auto __unopened population.
//
// Why this file exists, and why it is separate from tag_hygiene_report.js
// (owner decision, 2026-08-11): each check below targets a historically
// contingent situation, not a durable library property. Folding them into the
// recurring hygiene report would make that report carry dead weight forever
// once the situations are resolved. Detect-then-write separation (CONVENTIONS
// D2) applied one level up, to the reports themselves. Run these once, read the
// numbers, act, then this file is archived -- it is in one-time-operations/ for
// that reason (thread-1 precedent: find_files.sh lives here with a completed
// header).
//
// The three checks:
//   CHECK 1  /unread legacy tag: how many top-level regular items carry the
//            legacy "/unread" tag, and which of them ALSO carry a current
//            reading-state tag (__read / __in_progress). The latter are the
//            contradiction cases migrate_slash_unread.js must NOT force to
//            __unopened -- an item marked /unread AND __read has been read
//            since, and the current tag wins (CONVENTIONS B1: tags are the
//            source of truth). This sizes the migration's clean vs
//            leave-alone populations in advance.
//   CHECK 2  manual/auto duplication: the tag dump shows __unopened existing
//            as BOTH a manual tag (~21.6k) and an auto tag (~36.8k), and the
//            same manual/auto split for __in_progress and __revisit. Probed
//            2026-08-11: a Zotero.Search "tag is X" matches by NAME across
//            both types (58,482 for __unopened == manual+auto), so the
//            normalizer's name-only guard is correct and "auto counts" is
//            free. This check quantifies the split per reading-state tag so
//            the owner can decide whether the ~36.8k auto __unopened is worth
//            deleting -- it is flagged as a DELETION HAZARD, see the note in
//            the summary.
//   CHECK 3  Read_Status legacy field: how many items still carry a
//            "Read_Status:" line in their extra field (the pre-tag scheme,
//            CONVENTIONS B1 legacy), and whether that line AGREES with the
//            item's current reading-state tags. Sizes the eventual (separate,
//            out-of-scope-here) field-strip work; does not act.
//
// Usage:   Tools > Developer > Run JavaScript.
//          CHECK THE "Run as async function" CHECKBOX (CONVENTIONS A10.2):
//          this file uses top-level await and returns its summary object.
//          Do NOT wrap it in an async IIFE.
//          Reads only. Safe to run any number of times, in any order relative
//          to the other thread-3 scripts.
//
// Output:  A summary object (returned AND mirrored line-by-line to
//          Zotero.debug, since the console log survives when the returned
//          value is not captured -- CONVENTIONS A8). Numbers are small enough
//          to read inline; no file is written. Bounded samples (titles/ids)
//          are echoed up to a cap so the owner can eyeball specifics without
//          the output exploding (CONVENTIONS A6).
//
// Method / scale: the item populations here are small (thousands, not the
//          full 60k), but the scan that finds them must not materialize the
//          whole library. Each check resolves its target set through
//          Zotero.Search (tag / field conditions) which returns item IDs, then
//          loads them in bounded batches with Zotero.Items.getAsync
//          (CONVENTIONS A10.7: never Zotero.Items.getAll). This is the
//          version-robust path the repo already trusts (bbt_export.js,
//          bbt_citation_key_refresh.js use the same Search idiom) and avoids
//          hand-rolled SQL against the internal schema, which Zotero documents
//          as changing between releases. isRegularItem() / noChildren keep the
//          set to top-level regular items without hardcoding itemTypeIDs
//          (annotation's type id is not even stable across versions).
//
// Scope:   Diagnosis only. No tag is added or removed; no field is edited; no
//          collection is created. The /unread migration, the auto-tag
//          deletion decision, and any Read_Status strip are all separate,
//          later, explicitly-gated operations.
// =============================================================================

// 1. CONFIGURATION
var CONFIG = {
    // The legacy reading tag, exactly as stored. Owner reported a leading
    // slash. Tag names match case-sensitively, so this must be exact. If
    // CHECK 1 reports the tag as absent, confirm the exact string here.
    LEGACY_UNREAD_TAG: '/unread',

    // Current reading-state tags. The "opened-state" set is what the
    // normalizer's guard treats as "already has a reading state" and what
    // suppresses adding __unopened. Per Q1 (2026-08-11): __not_reading and
    // __to_read do NOT suppress (an item with only those still gets
    // __unopened), so they are deliberately absent from OPENED_STATE_TAGS.
    OPENED_STATE_TAGS: ['__unopened', '__in_progress', '__read'],

    // For CHECK 1, the tags whose co-occurrence with /unread is a
    // CONTRADICTION the migration must respect (leave the item alone rather
    // than assert __unopened). __unopened itself is a benign overlap
    // (already-migrated / double-tagged), reported but not a contradiction.
    UNREAD_CONTRADICTION_TAGS: ['__read', '__in_progress'],
    UNREAD_BENIGN_OVERLAP_TAGS: ['__unopened', '__not_reading', '__to_read'],

    // For CHECK 2, the reading-state tags known to exist in both manual and
    // auto form (from the 2026-08-11 tag dump). The check reports each tag's
    // total (name-match) count; the manual/auto split itself is read per item
    // from the item's own tag objects (which carry the type), because
    // Zotero.Search matches by name only and cannot distinguish type.
    DUPLICATED_STATE_TAGS: ['__unopened', '__in_progress', '__revisit'],

    // CHECK 3: the extra-field marker for the legacy read-status scheme, and
    // the mapping from its recorded values to the current tag that would
    // represent the same state. Used only to decide agreement/disagreement;
    // nothing is written. Values are matched case-insensitively and trimmed.
    // The salvage-source convert_readstatus_to_tags.js parsed the same
    // "Read_Status:" line; this mapping mirrors the states it recognized.
    READ_STATUS_MARKER: /Read_Status:\s*(.+)/i,
    READ_STATUS_TO_TAG: {
        'new': '__unopened',
        'unopened': '__unopened',
        'unread': '__unopened',
        'in progress': '__in_progress',
        'reading': '__in_progress',
        'read': '__read',
        'finished': '__read'
    },

    // Bounded sample sizes (A6).
    SAMPLE_MAX: 50,
    UNMAPPED_SAMPLE_PER_VALUE: 3,   // titles kept per distinct unmapped Read_Status value

    // Batch size for getAsync loads. The sets here are small, but batching
    // keeps a single getAsync from being handed thousands of ids at once and
    // lets the event loop breathe between batches on the larger ones.
    LOAD_BATCH_SIZE: 500,
    YIELD_MS: 10,

    // Version guards (A3). Confirmed environment Zotero 9.0.6
    // (VERIFIED_ENVIRONMENT.md, thread-2 spikes).
    MIN_ZOTERO_VERSION: '7.0',
    MAX_ZOTERO_VERSION: '9.0.6',
    BYPASS_VERSION_CHECK: false
};

// 2. STATE
var timing = {
    scriptStart: Date.now(),
    assertions: 0,
    getAsyncBatches: 0
};

var result = {
    check1_unread: {
        legacyTag: CONFIG.LEGACY_UNREAD_TAG,
        legacyTagPresent: false,
        totalItems: 0,
        cleanItems: 0,            // /unread with NONE of the contradiction tags -> straightforward migrate
        contradictionItems: 0,    // /unread with at least one contradiction tag -> leave alone
        contradictionByTag: {},
        benignOverlapByTag: {},
        contradictionSample: []   // { itemID, title, alsoHas: [...] }
    },
    check2_manualAutoSplit: {
        byTag: {}                 // tagName -> { total, manual, auto, both, neither }
    },
    check3_readStatus: {
        searchPath: null,         // 'extra-condition' (fast) or 'full-scan-fallback'
        candidatesScanned: 0,     // items whose extra field was actually read
        itemsWithReadStatusLine: 0,
        agreeWithTags: 0,
        disagreeWithTags: 0,
        reconcilableDisagree: 0,  // disagree AND only tag is __unopened AND extra maps to in_progress/read -> extra may win
        tagWinsDisagree: 0,       // disagree but tag is a deliberate state -> tag wins, extra stale
        noCurrentStateTag: 0,     // has Read_Status line but no opened-state tag at all
        noStateTagButEngaged: 0,  // subset of above where extra maps to in_progress/read -> normalizer would mis-default to __unopened
        unmappedValue: 0,         // Read_Status value not in READ_STATUS_TO_TAG
        unmappedValueCounts: {},  // raw unmapped Read_Status value -> count (to judge reconcilability)
        unmappedSampleByValue: {},// raw unmapped value -> up to N { itemID, title } samples
        disagreeSample: []        // { itemID, title, readStatusValue, expectedTag, actualStateTags: [...] }
    }
};

// 3. HELPERS
// assert(): pre-flight guard, many call sites. loadInBatches(): the
// search-ids -> getAsync-in-batches pattern is used by all three checks (>=3
// call sites), so it is extracted per CONVENTIONS A10.3 rather than inlined
// three times. It is a pure read that yields between batches; named to say so.
function assert(condition, message) {
    timing.assertions = timing.assertions + 1;
    if (!condition) {
        throw new Error(`diagnose_thread3 pre-flight failed: ${message}`);
    }
}

async function loadItemsInBatchesFromIDs(itemIDs) {
    var loaded = [];
    for (var start = 0; start < itemIDs.length; start = start + CONFIG.LOAD_BATCH_SIZE) {
        var batchIDs = itemIDs.slice(start, start + CONFIG.LOAD_BATCH_SIZE);
        var batchItems = await Zotero.Items.getAsync(batchIDs);
        timing.getAsyncBatches = timing.getAsyncBatches + 1;
        for (var bi = 0; bi < batchItems.length; bi = bi + 1) {
            loaded.push(batchItems[bi]);
        }
        // Yield between batches so a large set does not monopolize the loop.
        await new Promise(function (resolve) { setTimeout(resolve, CONFIG.YIELD_MS); });
    }
    return loaded;
}

// Resolve a tag name to the set of top-level regular item IDs carrying it,
// via the Search API (name-match, both tag types, no children). Returns an
// array of ids. Used by checks 1 and 2.
async function searchTopLevelItemIDsWithTag(tagName) {
    var search = new Zotero.Search();
    search.libraryID = Zotero.Libraries.userLibraryID;
    search.addCondition('noChildren', 'true');   // top-level only
    search.addCondition('tag', 'is', tagName);   // name-match; matches manual+auto (probed 2026-08-11)
    return await search.search();
}

// 4. PRE-FLIGHT
assert(typeof Zotero !== 'undefined', 'Zotero global unavailable');
assert(typeof Zotero.Search === 'function', 'Zotero.Search unavailable');
assert(typeof Zotero.Items.getAsync === 'function', 'Zotero.Items.getAsync unavailable');
assert(typeof Zotero.Libraries.userLibraryID === 'number', 'userLibraryID unavailable');

if (!CONFIG.BYPASS_VERSION_CHECK) {
    var zoteroVersion = Zotero.version;
    assert(
        Services.vc.compare(zoteroVersion, CONFIG.MIN_ZOTERO_VERSION) >= 0,
        `Zotero ${zoteroVersion} below tested floor ${CONFIG.MIN_ZOTERO_VERSION}`
    );
    if (Services.vc.compare(zoteroVersion, CONFIG.MAX_ZOTERO_VERSION) > 0) {
        Zotero.debug(`diagnose_thread3: running on Zotero ${zoteroVersion}, above tested ceiling ${CONFIG.MAX_ZOTERO_VERSION}. Search API is stable; confirm and bump the ceiling.`);
    }
}

// 5. MAIN
try {
    // -------------------------------------------------------------------------
    // CHECK 1: /unread legacy tag and its overlaps.
    // -------------------------------------------------------------------------
    var unreadIDs = await searchTopLevelItemIDsWithTag(CONFIG.LEGACY_UNREAD_TAG);
    result.check1_unread.legacyTagPresent = unreadIDs.length > 0;
    result.check1_unread.totalItems = unreadIDs.length;

    if (unreadIDs.length > 0) {
        var unreadItems = await loadItemsInBatchesFromIDs(unreadIDs);

        for (var ci = 0; ci < CONFIG.UNREAD_CONTRADICTION_TAGS.length; ci = ci + 1) {
            result.check1_unread.contradictionByTag[CONFIG.UNREAD_CONTRADICTION_TAGS[ci]] = 0;
        }
        for (var bi2 = 0; bi2 < CONFIG.UNREAD_BENIGN_OVERLAP_TAGS.length; bi2 = bi2 + 1) {
            result.check1_unread.benignOverlapByTag[CONFIG.UNREAD_BENIGN_OVERLAP_TAGS[bi2]] = 0;
        }

        for (var ui = 0; ui < unreadItems.length; ui = ui + 1) {
            var unreadItem = unreadItems[ui];
            var alsoHas = [];
            for (var cti = 0; cti < CONFIG.UNREAD_CONTRADICTION_TAGS.length; cti = cti + 1) {
                var contradictionTag = CONFIG.UNREAD_CONTRADICTION_TAGS[cti];
                if (unreadItem.hasTag(contradictionTag)) {
                    result.check1_unread.contradictionByTag[contradictionTag] =
                        result.check1_unread.contradictionByTag[contradictionTag] + 1;
                    alsoHas.push(contradictionTag);
                }
            }
            for (var bti = 0; bti < CONFIG.UNREAD_BENIGN_OVERLAP_TAGS.length; bti = bti + 1) {
                var benignTag = CONFIG.UNREAD_BENIGN_OVERLAP_TAGS[bti];
                if (unreadItem.hasTag(benignTag)) {
                    result.check1_unread.benignOverlapByTag[benignTag] =
                        result.check1_unread.benignOverlapByTag[benignTag] + 1;
                }
            }
            if (alsoHas.length > 0) {
                result.check1_unread.contradictionItems = result.check1_unread.contradictionItems + 1;
                if (result.check1_unread.contradictionSample.length < CONFIG.SAMPLE_MAX) {
                    result.check1_unread.contradictionSample.push({
                        itemID: unreadItem.id,
                        title: unreadItem.getField('title'),
                        alsoHas: alsoHas
                    });
                }
            } else {
                result.check1_unread.cleanItems = result.check1_unread.cleanItems + 1;
            }
        }
    }

    // -------------------------------------------------------------------------
    // CHECK 2: manual/auto split per duplicated reading-state tag.
    // Zotero.Search matches by name (both types), so the total comes from the
    // search; the split is read from each item's own tag objects. A tag object
    // carries { tag, type } where type 0 = manual, 1 = automatic. An item can
    // carry the SAME name as both a manual AND an auto tag (that is exactly the
    // duplication being measured), so "both" is counted distinctly from
    // manual-only / auto-only.
    // -------------------------------------------------------------------------
    for (var di = 0; di < CONFIG.DUPLICATED_STATE_TAGS.length; di = di + 1) {
        var stateTag = CONFIG.DUPLICATED_STATE_TAGS[di];
        var stateIDs = await searchTopLevelItemIDsWithTag(stateTag);
        var stateItems = await loadItemsInBatchesFromIDs(stateIDs);

        var split = { total: stateIDs.length, manual: 0, auto: 0, both: 0, neither: 0 };
        for (var si = 0; si < stateItems.length; si = si + 1) {
            var itemTags = stateItems[si].getTags();   // [{ tag, type }]
            var hasManual = false;
            var hasAuto = false;
            for (var ti = 0; ti < itemTags.length; ti = ti + 1) {
                if (itemTags[ti].tag === stateTag) {
                    // type is 0 for manual, 1 for automatic. Guard on !== 1 so a
                    // missing/undefined type is treated as manual, matching how
                    // Zotero renders untyped tags.
                    if (itemTags[ti].type === 1) {
                        hasAuto = true;
                    } else {
                        hasManual = true;
                    }
                }
            }
            if (hasManual && hasAuto) {
                split.both = split.both + 1;
            } else if (hasManual) {
                split.manual = split.manual + 1;
            } else if (hasAuto) {
                split.auto = split.auto + 1;
            } else {
                // Should not happen: search matched the name but the item's tag
                // objects do not contain it. Counted so a nonzero value flags a
                // stale-search / API mismatch rather than passing silently.
                split.neither = split.neither + 1;
            }
        }
        result.check2_manualAutoSplit.byTag[stateTag] = split;
    }

    // -------------------------------------------------------------------------
    // CHECK 3: legacy Read_Status line in extra, vs current tags.
    // Find candidate items via a Search on the extra field containing
    // "Read_Status", then read each item's extra field and compare the parsed
    // value against its opened-state tags.
    // -------------------------------------------------------------------------
    // The 'extra' search condition has no precedent elsewhere in this repo and
    // was not confirmed against the Zotero search-fields list, so it is used
    // defensively: if it throws (unknown condition name) or returns an empty
    // set on a library that the owner believes still has Read_Status lines, the
    // check falls back to a whole-library scan filtered in JS. The fallback is
    // the slower path (loads every top-level item's extra field), so it is only
    // taken when the fast path is unavailable, and it records which path ran so
    // a surprising zero is attributable rather than silent. Correctness does
    // not depend on the unverified condition; only speed does.
    var readStatusIDs = [];
    var readStatusPathUsed = 'extra-condition';
    try {
        var readStatusSearch = new Zotero.Search();
        readStatusSearch.libraryID = Zotero.Libraries.userLibraryID;
        readStatusSearch.addCondition('noChildren', 'true');
        readStatusSearch.addCondition('extra', 'contains', 'Read_Status');
        readStatusIDs = await readStatusSearch.search();
    } catch (extraConditionError) {
        Zotero.debug(`diagnose_thread3 CHECK 3: 'extra' search condition unavailable (${extraConditionError.message}); falling back to full top-level scan.`);
        readStatusPathUsed = 'full-scan-fallback';
    }
    if (readStatusPathUsed === 'full-scan-fallback') {
        var allTopLevelSearch = new Zotero.Search();
        allTopLevelSearch.libraryID = Zotero.Libraries.userLibraryID;
        allTopLevelSearch.addCondition('noChildren', 'true');
        readStatusIDs = await allTopLevelSearch.search();
    }
    result.check3_readStatus.searchPath = readStatusPathUsed;
    result.check3_readStatus.candidatesScanned = readStatusIDs.length;
    var readStatusItems = await loadItemsInBatchesFromIDs(readStatusIDs);

    for (var ri = 0; ri < readStatusItems.length; ri = ri + 1) {
        var rsItem = readStatusItems[ri];
        var extra = rsItem.getField('extra') || '';
        var match = extra.match(CONFIG.READ_STATUS_MARKER);
        if (!match) {
            // The search matched "Read_Status" as a substring but the marker
            // regex did not (e.g. it appeared mid-word). Skip; not a real line.
            continue;
        }
        result.check3_readStatus.itemsWithReadStatusLine =
            result.check3_readStatus.itemsWithReadStatusLine + 1;

        var rawValue = match[1].trim();
        var mappedTag = CONFIG.READ_STATUS_TO_TAG[rawValue.toLowerCase()];
        if (!mappedTag) {
            result.check3_readStatus.unmappedValue =
                result.check3_readStatus.unmappedValue + 1;
            // Capture the distinct unmapped values and their counts so the
            // owner can judge reconcilability: a handful of typo/case variants
            // of "read"/"in progress" is trivially reconcilable (extend the
            // mapping); free-text or hundreds of distinct values is not worth
            // it (tags win, per the reconcile disposition 2026-08-11). Keyed on
            // the raw value verbatim -- case and whitespace preserved, since
            // that is exactly what distinguishes a typo-variant from noise.
            var unmappedKey = rawValue;
            if (result.check3_readStatus.unmappedValueCounts[unmappedKey] === undefined) {
                result.check3_readStatus.unmappedValueCounts[unmappedKey] = 0;
                result.check3_readStatus.unmappedSampleByValue[unmappedKey] = [];
            }
            result.check3_readStatus.unmappedValueCounts[unmappedKey] =
                result.check3_readStatus.unmappedValueCounts[unmappedKey] + 1;
            if (result.check3_readStatus.unmappedSampleByValue[unmappedKey].length < CONFIG.UNMAPPED_SAMPLE_PER_VALUE) {
                result.check3_readStatus.unmappedSampleByValue[unmappedKey].push({
                    itemID: rsItem.id,
                    title: rsItem.getField('title')
                });
            }
            continue;
        }

        var currentStateTags = [];
        for (var oti = 0; oti < CONFIG.OPENED_STATE_TAGS.length; oti = oti + 1) {
            if (rsItem.hasTag(CONFIG.OPENED_STATE_TAGS[oti])) {
                currentStateTags.push(CONFIG.OPENED_STATE_TAGS[oti]);
            }
        }

        if (currentStateTags.length === 0) {
            result.check3_readStatus.noCurrentStateTag =
                result.check3_readStatus.noCurrentStateTag + 1;
            // No opened-state tag at all. The normalizer WILL add __unopened to
            // these. If extra says the item was engaged (in_progress/read),
            // that __unopened will be wrong -- so these are reconcilable too,
            // and separating the engaged subset tells the owner how many items
            // the normalizer would mis-default. Counted separately from the
            // onlyUnopened disagreements because these have no state tag to
            // replace -- reconciliation here ADDS the mapped tag rather than
            // swapping __unopened for it.
            if (mappedTag === '__in_progress' || mappedTag === '__read') {
                result.check3_readStatus.noStateTagButEngaged =
                    result.check3_readStatus.noStateTagButEngaged + 1;
            }
        } else if (currentStateTags.indexOf(mappedTag) !== -1) {
            result.check3_readStatus.agreeWithTags =
                result.check3_readStatus.agreeWithTags + 1;
        } else {
            result.check3_readStatus.disagreeWithTags =
                result.check3_readStatus.disagreeWithTags + 1;
            // The reconcile-relevant split. When the ONLY opened-state tag is
            // __unopened but extra says the item was engaged (mapped to
            // __in_progress/__read), __unopened is a never-updated default and
            // extra is positive evidence -- this is the reconcilable population
            // (extra could win). When the tag is itself __in_progress/__read
            // and merely differs from extra's value, the tag is a deliberate
            // state and wins; extra is stale. Counting these separately is what
            // tells the owner whether reconciliation is worth a one-time pass.
            var onlyUnopened = currentStateTags.length === 1 && currentStateTags[0] === '__unopened';
            if (onlyUnopened && (mappedTag === '__in_progress' || mappedTag === '__read')) {
                result.check3_readStatus.reconcilableDisagree =
                    result.check3_readStatus.reconcilableDisagree + 1;
            } else {
                result.check3_readStatus.tagWinsDisagree =
                    result.check3_readStatus.tagWinsDisagree + 1;
            }
            if (result.check3_readStatus.disagreeSample.length < CONFIG.SAMPLE_MAX) {
                result.check3_readStatus.disagreeSample.push({
                    itemID: rsItem.id,
                    title: rsItem.getField('title'),
                    readStatusValue: rawValue,
                    expectedTag: mappedTag,
                    actualStateTags: currentStateTags
                });
            }
        }
    }
} catch (error) {
    Zotero.debug(`diagnose_thread3 FAILED: ${error.message}`);
    throw error;
}

// 6. SUMMARY
timing.totalMs = Date.now() - timing.scriptStart;
result.timing = timing;

var lines = [];
lines.push('=== diagnose_thread3_tag_state ===');

lines.push('--- CHECK 1: /unread legacy tag ---');
lines.push(`legacy tag ${result.check1_unread.legacyTag} present: ${result.check1_unread.legacyTagPresent}`);
if (result.check1_unread.legacyTagPresent) {
    lines.push(`total items carrying it: ${result.check1_unread.totalItems}`);
    lines.push(`  clean (migrate straight to __unopened): ${result.check1_unread.cleanItems}`);
    lines.push(`  contradictions (also __read/__in_progress -- migration must LEAVE ALONE): ${result.check1_unread.contradictionItems}`);
    for (var k1 = 0; k1 < CONFIG.UNREAD_CONTRADICTION_TAGS.length; k1 = k1 + 1) {
        var ctName = CONFIG.UNREAD_CONTRADICTION_TAGS[k1];
        lines.push(`    also ${ctName}: ${result.check1_unread.contradictionByTag[ctName]}`);
    }
    lines.push('  benign overlaps (expected, not flagged):');
    for (var k2 = 0; k2 < CONFIG.UNREAD_BENIGN_OVERLAP_TAGS.length; k2 = k2 + 1) {
        var boName = CONFIG.UNREAD_BENIGN_OVERLAP_TAGS[k2];
        lines.push(`    also ${boName}: ${result.check1_unread.benignOverlapByTag[boName]}`);
    }
    for (var s1 = 0; s1 < result.check1_unread.contradictionSample.length; s1 = s1 + 1) {
        var cs = result.check1_unread.contradictionSample[s1];
        lines.push(`    [${cs.itemID}] also=${cs.alsoHas.join('+')} :: ${cs.title}`);
    }
} else {
    lines.push('nothing to migrate; migrate_slash_unread.js will no-op.');
}

lines.push('--- CHECK 2: manual/auto duplication per reading-state tag ---');
lines.push('DELETION HAZARD: the auto counts below are the population that would');
lines.push('re-appear as MANUAL tags on the next normalizer run if the auto tags');
lines.push('are deleted without running the normalizer first. Do not bulk-delete');
lines.push('auto __unopened without accounting for this (see thread-3 handoff).');
for (var k3 = 0; k3 < CONFIG.DUPLICATED_STATE_TAGS.length; k3 = k3 + 1) {
    var dtName = CONFIG.DUPLICATED_STATE_TAGS[k3];
    var sp = result.check2_manualAutoSplit.byTag[dtName];
    lines.push(`  ${dtName}: total=${sp.total} manual-only=${sp.manual} auto-only=${sp.auto} both=${sp.both} neither=${sp.neither}`);
}

lines.push('--- CHECK 3: legacy Read_Status field vs current tags ---');
lines.push(`search path: ${result.check3_readStatus.searchPath} (candidates scanned: ${result.check3_readStatus.candidatesScanned})`);
lines.push(`items with a Read_Status: line: ${result.check3_readStatus.itemsWithReadStatusLine}`);
lines.push(`  agree with current tags: ${result.check3_readStatus.agreeWithTags}`);
lines.push(`  DISAGREE with current tags: ${result.check3_readStatus.disagreeWithTags}`);
lines.push(`    of which reconcilable (only tag is __unopened, extra says engaged): ${result.check3_readStatus.reconcilableDisagree}`);
lines.push(`    of which tag-wins (tag is a deliberate state, extra stale): ${result.check3_readStatus.tagWinsDisagree}`);
lines.push(`  have line but no current state tag: ${result.check3_readStatus.noCurrentStateTag}`);
lines.push(`    of which extra says engaged (normalizer would mis-default to __unopened): ${result.check3_readStatus.noStateTagButEngaged}`);
lines.push(`  unmapped Read_Status value: ${result.check3_readStatus.unmappedValue}`);
// The distinct unmapped values, most frequent first, are the signal for
// whether reconciliation is straightforward. A short list dominated by
// case/typo variants of read/in-progress means "extend the mapping and
// reconcile"; a long tail of free-text means "tags win, drop it".
var unmappedValueEntries = Object.keys(result.check3_readStatus.unmappedValueCounts).map(function (value) {
    return { value: value, count: result.check3_readStatus.unmappedValueCounts[value] };
});
unmappedValueEntries.sort(function (a, b) { return b.count - a.count; });
lines.push(`  distinct unmapped values: ${unmappedValueEntries.length}`);
for (var uv = 0; uv < unmappedValueEntries.length; uv = uv + 1) {
    var entry = unmappedValueEntries[uv];
    lines.push(`    "${entry.value}" x${entry.count}`);
    var samples = result.check3_readStatus.unmappedSampleByValue[entry.value];
    for (var sv = 0; sv < samples.length; sv = sv + 1) {
        lines.push(`        [${samples[sv].itemID}] ${samples[sv].title}`);
    }
}
for (var s3 = 0; s3 < result.check3_readStatus.disagreeSample.length; s3 = s3 + 1) {
    var ds = result.check3_readStatus.disagreeSample[s3];
    lines.push(`    [${ds.itemID}] Read_Status="${ds.readStatusValue}" expected=${ds.expectedTag} actual=${ds.actualStateTags.join('+')} :: ${ds.title}`);
}

lines.push(`assertions: ${timing.assertions}  getAsync batches: ${timing.getAsyncBatches}  elapsed ms: ${timing.totalMs}`);

for (var li = 0; li < lines.length; li = li + 1) {
    Zotero.debug(lines[li]);
}

return result;
