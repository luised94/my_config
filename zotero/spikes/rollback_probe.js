// =============================================================================
// ROLLBACK PROBE  (perf investigation follow-up to P2(c))
// =============================================================================
// P2(c) reported that a throw inside Zotero.DB.executeTransaction did NOT roll
// back a tag write -- the tag was still present on getAsync re-fetch. That finding
// breaks the failure model M3 (chunked transactions with clean per-chunk
// rollback) and M4 (batch failure model) rested on. But P2(c) is SUSPECT: its
// re-fetch used Zotero.Items.getAsync, which can return a CACHED object, so it
// may have measured in-memory state rather than what committed to disk. Three
// explanations were indistinguishable there:
//   (1) the txn genuinely committed despite the throw (real; kills M3),
//   (2) the txn rolled back the DB but the cached object kept the tag (probe
//       artifact; P2(c) lied),
//   (3) the write was flushed outside the txn's rollback scope.
//
// This probe distinguishes them by reading DISK TRUTH via SQL (bypassing the
// object cache entirely) and by testing THREE cases that localize the cause to
// a layer instead of re-confirming the symptom:
//
//   Case C  control: txn + write + CLEAN return (no throw). Confirms the write
//           DOES persist on the normal path. Without this, A/B are
//           uninterpretable -- "tag absent" could mean rollback OR that the write
//           never landed. Run/report first.
//   Case A  txn + item API addTag + item.save() + throw. Reproduces P2(c)
//           exactly, but verifies against disk.
//   Case B  txn + RAW SQL write + throw, no item.save(). Isolates the
//           transaction layer from the item-save layer:
//             A rolls back, B rolls back      -> rollback works; P2(c) was a
//                                                cache artifact (explanation 2).
//             A does NOT, B DOES              -> non-rollback is in the item-save
//                                                layer (explanation 1/3, localized).
//             neither rolls back              -> the transaction layer itself does
//                                                not roll back on this build (deepest
//                                                finding; M3 dead, M1 needs an
//                                                idempotent-re-run safety story).
//
// SCOPE: this probe DIAGNOSES. It does not fix. If non-rollback is confirmed, the
// response (rely on idempotent re-run, redesign M3) is a separate design turn and
// is deliberately NOT in here.
//
// SQL CONVENTIONS (house style, stated once, applied everywhere below):
//   - Parameter binding ALWAYS. Never string interpolation into SQL, even for an
//     integer itemID we control: a bound undefined THROWS (loud, correct) where an
//     interpolated undefined would read the WRONG rows and return plausible ground
//     truth -- the worst failure for a probe whose job is ground truth.
//   - The schema is Zotero's, not ours, and can drift. Table/column names are
//     UNVERIFIED until the schema check below confirms them against sqlite_master,
//     failing loudly with the actual schema if they are wrong (same discipline the
//     normalizer applies to unverified search-condition names). A renamed column
//     would otherwise return empty and masquerade as "rollback worked".
//   - Read-only stays read-only structurally: disk-truth reads use queryAsync with
//     SELECT only. The ONE raw write (Case B, and the setup writes) is the minimum
//     needed to test the transaction layer, is on the scratch clone, and is marked
//     at its site.
//
// SAFETY: writes and deletes real tags -> SCRATCH / COPIED library only. Gated
//   behind I_UNDERSTAND_THIS_WRITES. Unique throwaway tag per run so every write is
//   real and cleanup deletes exactly what it created. Self-cleans in a finally.
//
// Usage: Tools > Developer > Run JavaScript. CHECK "Run as async function".
// =============================================================================

var CONFIG = {
    // Writes and deletes real tags; run on a scratch clone. Must be flipped true.
    I_UNDERSTAND_THIS_WRITES: false,

    MIN_ZOTERO_VERSION: '7.0',
    MAX_ZOTERO_VERSION: '9.0.6',
    BYPASS_VERSION_CHECK: false
};

// Unique per run: cannot collide with a real tag, guarantees every write is a
// genuine insert, makes cleanup unambiguous.
var PROBE_TAG_BASE = '__rollback_probe_' + Date.now();

var report = {
    probeTagBase: PROBE_TAG_BASE,
    schema: { tablesConfirmed: false, tagsTable: null, itemTagsTable: null, note: null },
    caseC_control_persistsOnCleanReturn: null,
    caseA_itemSaveThrow_rolledBack: null,
    caseB_rawWriteThrow_rolledBack: null,
    conclusion: null,
    cleanup: { tagsDeletedFromItemTags: 0, tagRowsDeleted: 0, failures: [] }
};

function assert(condition, message) {
    if (!condition) { throw new Error('rollback_probe pre-flight failed: ' + message); }
}

// --- disk-truth read: does this item carry this tag NAME on disk? ------------
// Reads itemTags joined to tags by tagID. queryAsync = SELECT only, bound params.
// Bypasses the object cache: this is committed-on-disk state regardless of memory.
// Returns the integer count of matching itemTags rows (0 = absent on disk).
async function diskTruthTagCount(itemID, tagName) {
    // SELECT only. Bound params (itemID integer, tagName string). Read establishes
    // ground truth; it never writes.
    var sql = 'SELECT COUNT(*) AS c FROM itemTags '
        + 'JOIN tags ON tags.tagID = itemTags.tagID '
        + 'WHERE itemTags.itemID = ? AND tags.name = ?';
    var rows = await Zotero.DB.queryAsync(sql, [itemID, tagName]);
    // queryAsync returns an array of row objects; COUNT(*) always yields one row.
    return rows && rows.length ? rows[0].c : 0;
}

// --- PRE-FLIGHT --------------------------------------------------------------
assert(typeof Zotero !== 'undefined', 'Zotero global unavailable');
assert(typeof Zotero.Search === 'function', 'Zotero.Search unavailable');
assert(typeof Zotero.Items !== 'undefined' && typeof Zotero.Items.getAsync === 'function',
    'Zotero.Items.getAsync unavailable');
assert(typeof Zotero.DB !== 'undefined', 'Zotero.DB unavailable');
assert(typeof Zotero.DB.executeTransaction === 'function', 'Zotero.DB.executeTransaction unavailable');
assert(typeof Zotero.DB.queryAsync === 'function', 'Zotero.DB.queryAsync unavailable -- disk-truth read not possible');
var userLibraryID = Zotero.Libraries.userLibraryID;
assert(typeof userLibraryID === 'number', 'userLibraryID unavailable');

if (!CONFIG.BYPASS_VERSION_CHECK) {
    var zoteroVersion = Zotero.version;
    assert(Services.vc.compare(zoteroVersion, CONFIG.MIN_ZOTERO_VERSION) >= 0,
        'Zotero ' + zoteroVersion + ' below tested floor ' + CONFIG.MIN_ZOTERO_VERSION);
    if (Services.vc.compare(zoteroVersion, CONFIG.MAX_ZOTERO_VERSION) > 0) {
        Zotero.debug('rollback_probe: Zotero ' + zoteroVersion + ' above tested ceiling '
            + CONFIG.MAX_ZOTERO_VERSION + '; confirm APIs and bump.');
    }
}

assert(CONFIG.I_UNDERSTAND_THIS_WRITES === true,
    'this probe writes and deletes real tags; set CONFIG.I_UNDERSTAND_THIS_WRITES = true '
    + 'and run it on a SCRATCH / COPIED library, not your real one');

// Track raw-inserted tagIDs and the itemIDs we touched, so cleanup removes exactly
// what this probe created regardless of which case created it or whether a case threw.
var touchedItemIDs = new Set();

try {
    // --- SCHEMA CHECK (first SQL action). The schema is Zotero's, not ours. ---
    // Confirm the tables and the columns the disk-truth read depends on actually
    // exist under these names on this build. Fail loudly with what WAS found, so a
    // rename cannot return empty and masquerade as "rollback worked".
    var masterRows = await Zotero.DB.queryAsync(
        "SELECT name FROM sqlite_master WHERE type = 'table' AND name IN (?, ?)",
        ['tags', 'itemTags']);
    var foundTables = [];
    for (var mi = 0; mi < masterRows.length; mi = mi + 1) { foundTables.push(masterRows[mi].name); }
    assert(foundTables.indexOf('tags') !== -1 && foundTables.indexOf('itemTags') !== -1,
        "expected tables 'tags' and 'itemTags'; sqlite_master returned: [" + foundTables.join(', ') + ']');

    // Confirm the columns used below: tags(tagID, name), itemTags(itemID, tagID).
    // PRAGMA table_info returns one row per column with a 'name' field.
    var tagsCols = (await Zotero.DB.queryAsync('PRAGMA table_info(tags)')).map(function (r) { return r.name; });
    var itemTagsCols = (await Zotero.DB.queryAsync('PRAGMA table_info(itemTags)')).map(function (r) { return r.name; });
    assert(tagsCols.indexOf('tagID') !== -1 && tagsCols.indexOf('name') !== -1,
        "tags table missing tagID/name; has: [" + tagsCols.join(', ') + ']');
    assert(itemTagsCols.indexOf('itemID') !== -1 && itemTagsCols.indexOf('tagID') !== -1,
        "itemTags table missing itemID/tagID; has: [" + itemTagsCols.join(', ') + ']');

    // If queryAsync returned an unexpected ROW SHAPE (arrays instead of named-column
    // objects), the .name accesses above throw here in pre-flight -- the right place
    // to fail. A reader hitting a schema-check throw should suspect either a renamed
    // table/column OR a queryAsync row-shape difference on this build, not just names.
    report.schema.tablesConfirmed = true;
    report.schema.tagsTable = 'tags(' + tagsCols.join(',') + ')';
    report.schema.itemTagsTable = 'itemTags(' + itemTagsCols.join(',') + ')';
    Zotero.debug('rollback_probe: schema confirmed. ' + report.schema.tagsTable + '  ' + report.schema.itemTagsTable);

    // --- Pick three distinct items (one per case), top-level regular items. ---
    var search = new Zotero.Search();
    search.libraryID = userLibraryID;
    search.addCondition('itemType', 'isNot', 'attachment');
    search.addCondition('itemType', 'isNot', 'note');
    search.addCondition('itemType', 'isNot', 'annotation');
    var candidateIDs = await search.search();
    assert(candidateIDs.length >= 3, 'need at least 3 top-level items; found ' + candidateIDs.length);
    var itemIdC = candidateIDs[0];   // control
    var itemIdA = candidateIDs[1];   // item.save + throw
    var itemIdB = candidateIDs[2];   // raw write + throw

    var tagC = PROBE_TAG_BASE + '_C';
    var tagA = PROBE_TAG_BASE + '_A';
    var tagB = PROBE_TAG_BASE + '_B';

    // =========================================================================
    // CASE C -- CONTROL: txn + item write + CLEAN return. Must persist on disk.
    // Establishes that the write path lands, so absence in A/B means rollback.
    // =========================================================================
    var itemC = await Zotero.Items.getAsync(itemIdC);
    touchedItemIDs.add(itemIdC);
    await Zotero.DB.executeTransaction(async function () {
        itemC.addTag(tagC);
        await itemC.save();          // joins outer txn (confirmed by P2(a))
    });                              // clean return -> should commit
    var diskC = await diskTruthTagCount(itemIdC, tagC);
    report.caseC_control_persistsOnCleanReturn = (diskC > 0);
    Zotero.debug('rollback_probe CASE C (control): disk tag count after clean commit = ' + diskC
        + ' -> persists=' + report.caseC_control_persistsOnCleanReturn);

    // =========================================================================
    // CASE A -- txn + item.save() + THROW. Reproduces P2(c), verified vs disk.
    // =========================================================================
    var itemA = await Zotero.Items.getAsync(itemIdA);
    touchedItemIDs.add(itemIdA);
    var sentinelA = 'rollback_probe_intentional_A';
    try {
        await Zotero.DB.executeTransaction(async function () {
            itemA.addTag(tagA);
            await itemA.save();
            throw new Error(sentinelA);   // force rollback
        });
    } catch (innerA) {
        if (innerA.message !== sentinelA) { throw innerA; }   // real error -> re-raise
    }
    var diskA = await diskTruthTagCount(itemIdA, tagA);
    report.caseA_itemSaveThrow_rolledBack = (diskA === 0);
    Zotero.debug('rollback_probe CASE A (item.save + throw): disk tag count = ' + diskA
        + ' -> rolledBack=' + report.caseA_itemSaveThrow_rolledBack);

    // =========================================================================
    // CASE B -- txn + RAW SQL write + THROW, no item.save(). Isolates the txn
    // layer from the item-save layer.
    // The raw INSERT here is the ONE unavoidable write to test the transaction
    // layer directly. It is the minimum needed, on the scratch clone, marked here.
    // Insert the tag row (if absent) then the itemTags link, then throw. If the
    // txn rolls back, neither survives.
    // =========================================================================
    var itemB = await Zotero.Items.getAsync(itemIdB);
    touchedItemIDs.add(itemIdB);
    // The timestamped PROBE_TAG_BASE is load-bearing here, not just tidy: if a prior
    // aborted run had left a stale itemTags link for this name, INSERT OR IGNORE below
    // would no-op and diskB would read the STALE row as ">0", falsely reporting "did
    // not roll back". A unique name per run cannot collide with a prior run, so diskB
    // reflects only THIS run's write.
    var sentinelB = 'rollback_probe_intentional_B';
    try {
        await Zotero.DB.executeTransaction(async function () {
            // RAW WRITE (marked): create the tag name row if it does not exist.
            // INSERT ... bound params, no interpolation.
            await Zotero.DB.queryAsync('INSERT OR IGNORE INTO tags (name) VALUES (?)', [tagB]);
            var idRows = await Zotero.DB.queryAsync('SELECT tagID FROM tags WHERE name = ?', [tagB]);
            var tagIdB = idRows[0].tagID;
            // RAW WRITE (marked): link item to tag. type 0 = manual tag (Zotero
            // convention). Type is set for a well-formed row; the rollback reading is
            // unaffected by it because diskTruthTagCount matches by NAME only, and raw
            // cleanup also matches by name -- so a wrong type convention cannot corrupt
            // the finding, only the row's cosmetic type.
            await Zotero.DB.queryAsync(
                'INSERT OR IGNORE INTO itemTags (itemID, tagID, type) VALUES (?, ?, 0)',
                [itemIdB, tagIdB]);
            throw new Error(sentinelB);   // force rollback of the raw writes
        });
    } catch (innerB) {
        if (innerB.message !== sentinelB) { throw innerB; }
    }
    var diskB = await diskTruthTagCount(itemIdB, tagB);
    report.caseB_rawWriteThrow_rolledBack = (diskB === 0);
    Zotero.debug('rollback_probe CASE B (raw write + throw): disk tag count = ' + diskB
        + ' -> rolledBack=' + report.caseB_rawWriteThrow_rolledBack);

    // =========================================================================
    // CONCLUSION -- localize the cause from the three booleans.
    // =========================================================================
    var controlOk = report.caseC_control_persistsOnCleanReturn;
    var aRolled = report.caseA_itemSaveThrow_rolledBack;
    var bRolled = report.caseB_rawWriteThrow_rolledBack;

    if (!controlOk) {
        report.conclusion = 'INCONCLUSIVE: control (Case C) did not persist on a clean commit, so '
            + 'the write path itself is not landing as expected. A/B rollback readings cannot be '
            + 'trusted until the control passes. Investigate the write path before interpreting rollback.';
    } else if (aRolled && bRolled) {
        report.conclusion = 'ROLLBACK WORKS. Both the item-save path and the raw-write path rolled back '
            + 'on throw (verified against disk). P2(c) was a CACHE ARTIFACT: its getAsync re-fetch read a '
            + 'stale in-memory object, not disk. M3/M4 clean-rollback assumption is SOUND; the earlier '
            + 'finding does not block batched writes.';
    } else if (!aRolled && bRolled) {
        report.conclusion = 'NON-ROLLBACK LOCALIZED TO THE ITEM-SAVE LAYER. The transaction layer rolls '
            + 'back raw writes (Case B) but the item.save() path (Case A) left state on disk. Batched '
            + 'item.save() inside one transaction is NOT safely atomic on throw. M3 chunked-rollback is '
            + 'not available via item.save(); M1/M3 must rely on the normalizer being idempotent '
            + '(re-run reconciles) rather than on rollback. Separate design turn.';
    } else if (!aRolled && !bRolled) {
        report.conclusion = 'TRANSACTION LAYER DOES NOT ROLL BACK ON THROW on this build (both raw write '
            + 'and item.save persisted despite the throw). This is the deepest finding: executeTransaction '
            + 'does not undo committed statements on a JS exception here. M3 is dead. Any batched-write fix '
            + 'must be safe under partial application -- i.e. lean entirely on idempotent re-run. Separate '
            + 'design turn; do NOT proceed to a batched-write patch on rollback assumptions.';
    } else {
        // aRolled && !bRolled: item-save rolled back but raw write did not. Surprising;
        // would suggest item.save routes through a path that DOES roll back while direct
        // SQL in the same txn does not. Flag for investigation rather than conclude.
        report.conclusion = 'ANOMALY: item.save() rolled back (Case A) but the raw write did not (Case B). '
            + 'This inverts the expected layering and suggests the raw INSERT is committing outside the '
            + 'transaction scope (e.g. autocommit) while item.save participates. Investigate before relying '
            + 'on either path.';
    }
    Zotero.debug('rollback_probe CONCLUSION: ' + report.conclusion);

} catch (error) {
    Zotero.debug('rollback_probe FAILED: ' + error.message + '\n' + error.stack);
    report.conclusion = 'PROBE ERRORED before conclusion: ' + error.message;
    // fall through to cleanup
} finally {
    // =========================================================================
    // CLEANUP (untimed): remove every PROBE_TAG_BASE-prefixed tag this probe
    // created, from the items it touched, then delete the now-orphan tag rows.
    // Uses the item API for the itemTags removal to stay consistent, and a raw
    // read+delete only for orphan tag-name rows the raw Case B may have created.
    // Removes ONLY names starting with PROBE_TAG_BASE, so nothing real is touched.
    // =========================================================================
    var touchedList = Array.from(touchedItemIDs);
    for (var ci = 0; ci < touchedList.length; ci = ci + 1) {
        try {
            var cleanupItem = await Zotero.Items.getAsync(touchedList[ci]);
            var tags = cleanupItem.getTags();   // [{tag, type}]
            var removedAny = false;
            for (var ti = 0; ti < tags.length; ti = ti + 1) {
                if (tags[ti].tag.indexOf(PROBE_TAG_BASE) === 0) {
                    cleanupItem.removeTag(tags[ti].tag);
                    report.cleanup.tagsDeletedFromItemTags = report.cleanup.tagsDeletedFromItemTags + 1;
                    removedAny = true;
                }
            }
            if (removedAny) { await cleanupItem.saveTx(); }
        } catch (cleanupErr) {
            report.cleanup.failures.push({ itemID: touchedList[ci], error: cleanupErr.message });
        }
    }
    // Case B's raw INSERT may have created a tags-name row not attached via the item
    // API (or attached rawly). Remove any orphan probe tag rows by name. queryAsync
    // DELETE with bound LIKE param; prefix match on the unique base is exact enough.
    try {
        // Delete itemTags links to any probe tag first (FK hygiene), then the tag rows.
        await Zotero.DB.queryAsync(
            'DELETE FROM itemTags WHERE tagID IN (SELECT tagID FROM tags WHERE name LIKE ?)',
            [PROBE_TAG_BASE + '%']);
        var delRows = await Zotero.DB.queryAsync('SELECT tagID FROM tags WHERE name LIKE ?', [PROBE_TAG_BASE + '%']);
        report.cleanup.tagRowsDeleted = delRows.length;
        await Zotero.DB.queryAsync('DELETE FROM tags WHERE name LIKE ?', [PROBE_TAG_BASE + '%']);
    } catch (rawCleanupErr) {
        report.cleanup.failures.push({ stage: 'raw_tag_row_cleanup', error: rawCleanupErr.message });
    }
    Zotero.debug('rollback_probe cleanup: removed ' + report.cleanup.tagsDeletedFromItemTags
        + ' itemTags link(s), ' + report.cleanup.tagRowsDeleted + ' orphan tag row(s); '
        + report.cleanup.failures.length + ' failure(s).');
    if (report.cleanup.failures.length > 0) {
        Zotero.debug('rollback_probe cleanup failures (remove names starting "' + PROBE_TAG_BASE
            + '" manually): ' + JSON.stringify(report.cleanup.failures.slice(0, 20)));
    }
}

return report;
