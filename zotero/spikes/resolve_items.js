// =============================================================================
// RESOLVE ITEMS  (read-only auditing helper)
// =============================================================================
// Given a list of itemIDs, print a table of: itemID, BBT citation key (if Better
// BibTeX is present), itemType, every creator with its creatorType, and title.
// Purpose: make R4 (and any tag rule) auditable -- a bare itemID in a probe result
// cannot be inspected in the GUI without this.
//
// READ-ONLY: no writes, no tag changes, no saves. Safe on the real library.
//
// Usage: Tools > Developer > Run JavaScript. CHECK "Run as async function".
//   Put the itemIDs to inspect in CONFIG.ITEM_IDS. Leave it empty to instead
//   inspect every item currently carrying CONFIG.TAG_FILTER (e.g. '__add-metadata')
//   -- handy for auditing exactly the items a rule flagged.
// =============================================================================

var CONFIG = {
    // Explicit itemIDs to inspect. If empty, falls back to TAG_FILTER below.
    ITEM_IDS: [1271, 1272, 2379],

    // If ITEM_IDS is empty, inspect all items carrying this tag instead. Set to ''
    // to disable. Lets you audit "everything R4 flagged" by tag, not by id list.
    TAG_FILTER: '',

    // Cap output so a huge tag set does not flood the console. 0 = no cap.
    MAX_ROWS: 500
};

function assert(condition, message) {
    if (!condition) { throw new Error('resolve_items failed: ' + message); }
}

assert(typeof Zotero !== 'undefined', 'Zotero global unavailable');
assert(typeof Zotero.Items !== 'undefined' && typeof Zotero.Items.getAsync === 'function',
    'Zotero.Items.getAsync unavailable');

// Better BibTeX citation key lookup. BBT exposes keys via its KeyManager; the API
// has shifted across BBT versions, so probe a couple of shapes and degrade to
// '(no BBT)' rather than throwing if none is present. Pure read.
function getCitationKey(item) {
    try {
        if (typeof Zotero.BetterBibTeX === 'undefined' || !Zotero.BetterBibTeX) { return '(no BBT)'; }
        var km = Zotero.BetterBibTeX.KeyManager;
        if (!km) { return '(no BBT)'; }
        // Newer BBT: KeyManager.get(itemID) -> { citationKey } (or similar).
        if (typeof km.get === 'function') {
            var rec = km.get(item.id);
            if (rec && (rec.citationKey || rec.citekey)) { return rec.citationKey || rec.citekey; }
        }
        return '(no key)';
    } catch (e) {
        return '(BBT error)';
    }
}

var result = { rowsRequested: 0, rows: [] };

try {
    var itemIDs = CONFIG.ITEM_IDS.slice();

    // If no explicit ids, resolve by tag. Read-only Zotero.Search.
    if (itemIDs.length === 0 && CONFIG.TAG_FILTER) {
        var search = new Zotero.Search();
        search.libraryID = Zotero.Libraries.userLibraryID;
        search.addCondition('tag', 'is', CONFIG.TAG_FILTER);
        itemIDs = await search.search();
    }
    assert(itemIDs.length > 0, 'no itemIDs to inspect (set CONFIG.ITEM_IDS or CONFIG.TAG_FILTER)');

    if (CONFIG.MAX_ROWS > 0 && itemIDs.length > CONFIG.MAX_ROWS) {
        Zotero.debug('resolve_items: capping ' + itemIDs.length + ' items to MAX_ROWS=' + CONFIG.MAX_ROWS);
        itemIDs = itemIDs.slice(0, CONFIG.MAX_ROWS);
    }
    result.rowsRequested = itemIDs.length;

    var items = await Zotero.Items.getAsync(itemIDs);
    for (var i = 0; i < items.length; i = i + 1) {
        var item = items[i];

        // Build a "type:name" list for every creator, so authorship is auditable at
        // a glance -- this is exactly what R4 inspects.
        var creatorParts = [];
        var creatorCount = item.numCreators();
        for (var c = 0; c < creatorCount; c = c + 1) {
            var creator = item.getCreatorJSON(c);
            var name = creator ? ((creator.lastName || '') + (creator.firstName ? ', ' + creator.firstName : '')
                || creator.name || '(unnamed)') : '(null)';
            var type = creator ? creator.creatorType : '(null)';
            creatorParts.push(type + ':' + name);
        }

        var row = {
            itemID: item.id,
            citationKey: getCitationKey(item),
            itemType: Zotero.ItemTypes.getName(item.itemTypeID),
            creators: creatorParts.length ? creatorParts.join(' | ') : '(none)',
            title: item.getField('title') || '(no title)'
        };
        result.rows.push(row);

        Zotero.debug('[' + row.itemID + ']  key=' + row.citationKey + '  type=' + row.itemType
            + '  creators=[' + row.creators + ']  title=' + row.title);
    }

    Zotero.debug('resolve_items: ' + result.rows.length + ' item(s) resolved.');
} catch (error) {
    Zotero.debug('resolve_items FAILED: ' + error.message + '\n' + error.stack);
    throw error;
}

return result;
