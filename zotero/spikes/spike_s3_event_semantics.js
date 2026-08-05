// =============================================================================
// SPIKE S3: ITEM-ADDED EVENT SEMANTICS (Actions & Tags action)
// =============================================================================
// STATUS: PENDING owner run (thread 3). Findings go into
// handoff/03_incoming_automation.md "Verified facts". Gates the design of
// normalize-incoming-item.js -- especially loop safety (OQ2), which the
// handoff says must be DESIGNED FROM S3 FINDINGS, NOT ASSUMED.
//
// Version: 1.0.0
// Date:    2026-07
//
// THIS IS NOT A CONSOLE SCRIPT. It is an Actions & Tags ACTION, registered
// once and then fired by Zotero every time an item is added. Setup is in
// the "SETUP" block below; do not paste this into Run JavaScript.
//
// Purpose: answer the four S3 questions from handoff/03, by observation
//          rather than assumption:
//   Q1 When does item-added fire relative to translator metadata
//      population? -> every fire writes a full field snapshot, so an empty
//      title/creators/date at fire time means the event precedes
//      population and rules CANNOT trust fields at fire time.
//   Q2 Does a save inside the handler re-trigger the event / re-run the
//      action? -> the opt-in PROBE performs one benign write and records
//      whether a second fire follows for the same item.
//   Q3 Bulk import of N items: N events? burst timing? missed events?
//      -> every fire is timestamped to the millisecond and stamped with a
//      session id; compare the line count against what you imported.
//   Q4 Does the action receive child attachments/notes as separate items?
//      -> every fire records itemType, isRegularItem/isAttachment/isNote,
//      and parentItemID.
//
// Safety:  READ-ONLY BY DEFAULT. With CONFIG.PROBE_ENABLED = false (the
//          default) this action writes NOTHING to the library; its only
//          write is appending to its own log file. The probe, when enabled,
//          adds one marker tag to at most PROBE_MAX_ITEMS items -- a tag is
//          the cheapest reversible write available (remove the tag to
//          undo), and it doubles as the durable loop guard.
//
// Loop safety OF THE SPIKE ITSELF: the probe only ever fires for an item
//          that does NOT already carry MARKER_TAG, and it adds MARKER_TAG
//          as part of the same save. So a re-trigger cannot probe again --
//          the recursion terminates after one level by construction. In-
//          memory state is NOT relied on, because an action may be
//          evaluated in a fresh scope each fire (itself an S3 unknown; the
//          log records whether the scope persisted).
//
// -----------------------------------------------------------------------------
// SETUP (Actions & Tags)
// -----------------------------------------------------------------------------
// 1. Zotero > Edit > Settings > Actions & Tags > Actions > "+" (new action).
// 2. Name:      Spike S3 event log
//    Event:     Add Item        (the item-added trigger)
//    Operation: Run JavaScript  (script/code operation)
//    Enabled:   yes
// 3. Paste this entire file as the action's script body.
// 4. IMPORTANT -- the WSL/Windows transport caveat (handoff/03, Q5): this
//    repository lives in WSL and Zotero runs on Windows. Copy this file to
//    the Windows-side folder first, or paste its contents directly into the
//    action. The repository copy stays canonical (D6); if you edit the
//    action in place, copy the change back.
// 5. Refresh the Actions & Tags yml backup after adding the action.
//
// HOW TO RUN THE SPIKE
//   Pass A (fire timing + children + bursts), PROBE_ENABLED = false:
//     A1. Add ONE item via a web translator (browser connector). Note the
//         translator used.
//     A2. Repeat with at least 3 DIFFERENT translators (e.g. a journal
//         article, a book from Google Books, a news/web page).
//     A3. Add one item MANUALLY (New Item > by type) -- no translator.
//     A4. Add one item by DOI/ISBN lookup (Add Item by Identifier).
//     A5. BULK: import a batch of N items at once (a .bib/.ris file, or a
//         multi-select save from the connector). WRITE DOWN N.
//     A6. Attach a file to an existing item, and add a child note.
//   Pass B (re-trigger question), only after Pass A is logged:
//     B1. Set CONFIG.PROBE_ENABLED = true in the action, save the action.
//     B2. Add 2-3 items. Then set PROBE_ENABLED back to false.
//   Then read the log (see ANALYZE below) and paste the summary into
//   handoff/03_incoming_automation.md.
//
// ANALYZE -- paste this into Tools > Developer > Run JavaScript with
// "Run as async function" CHECKED, to summarize the log without pasting
// hundreds of raw lines:
//
//   var logPath = PathUtils.join(Zotero.DataDirectory.dir, 'spike_s3',
//       's3_event_log.jsonl');
//   var text = await IOUtils.readUTF8(logPath);
//   var entries = text.split('\n').filter(l => l.trim().length > 0)
//       .map(l => JSON.parse(l));
//   var byType = {}, emptyTitle = 0, emptyCreators = 0, emptyDate = 0;
//   var children = 0, repeats = {}, sessions = {};
//   for (var e of entries) {
//       byType[e.itemType] = (byType[e.itemType] || 0) + 1;
//       if (!e.hasTitle) emptyTitle++;
//       if (e.creatorCount === 0) emptyCreators++;
//       if (!e.hasDate) emptyDate++;
//       if (e.parentItemID !== null) children++;
//       repeats[e.itemID] = (repeats[e.itemID] || 0) + 1;
//       sessions[e.sessionID] = (sessions[e.sessionID] || 0) + 1;
//   }
//   var refired = Object.keys(repeats).filter(k => repeats[k] > 1);
//   return { totalFires: entries.length, byType: byType,
//       firedWithEmptyTitle: emptyTitle, firedWithNoCreators: emptyCreators,
//       firedWithNoDate: emptyDate, childItemFires: children,
//       itemsFiredMoreThanOnce: refired.length, refiredItemIDs: refired,
//       distinctScopeSessions: Object.keys(sessions).length,
//       firstEntry: entries[0], lastEntry: entries[entries.length - 1] };
//
// TO RESET between passes: delete the log file, or move it aside. The
// action recreates it.
// =============================================================================

// 1. CONFIGURATION
var CONFIG = {
    // Pass A default. true only for Pass B (the re-trigger question).
    PROBE_ENABLED: false,
    PROBE_MAX_ITEMS: 3,           // hard cap on probe writes per scope

    MARKER_TAG: '__spike-s3-probe',   // durable loop guard AND the probe write
    LOG_SUBDIR: 'spike_s3',
    LOG_FILE: 's3_event_log.jsonl',

    // Fields snapshotted at fire time. Presence, not content, answers Q1;
    // titles are truncated because the log is for timing, not for text.
    TITLE_TRUNCATE: 60
};

// 2. STATE
// Module-scope state. Whether this SURVIVES between fires is itself an S3
// unknown: if the action is re-evaluated per fire, sessionID differs every
// line and probeCount always starts at 0 (so PROBE_MAX_ITEMS would not cap
// across fires -- which is exactly why MARKER_TAG, not this counter, is the
// real guard). The log records sessionID so the answer is measurable.
if (typeof globalThis.__spikeS3Session === 'undefined') {
    globalThis.__spikeS3Session = {
        sessionID: String(Date.now()) + '-' + String(Math.floor(Math.random() * 100000)),
        fireCount: 0,
        probeCount: 0
    };
}
var session = globalThis.__spikeS3Session;

// 3. MAIN
// Wrapped so a failure inside the action can never block item creation --
// a spike must not damage the workflow it is measuring.
try {
    session.fireCount = session.fireCount + 1;

    // The A&T action receives the added item as `item`. This is the one
    // assumption the spike cannot self-verify; if it is wrong, the log line
    // below records the failure instead of silently logging nothing.
    var observedItem = (typeof item !== 'undefined') ? item : null;

    var entry = null;
    if (observedItem === null) {
        entry = {
            when: new Date().toISOString(),
            epochMs: Date.now(),
            sessionID: session.sessionID,
            fireOrdinalInSession: session.fireCount,
            error: 'no `item` binding in action scope -- verify the A&T API ' +
                'variable name and re-run'
        };
    } else {
        // Classify the item. Q4 is answered by these three flags plus
        // parentItemID: if attachments and notes fire the action, rules must
        // filter on them explicitly.
        var isRegular = (typeof observedItem.isRegularItem === 'function') ?
            observedItem.isRegularItem() : null;
        var isAttachment = (typeof observedItem.isAttachment === 'function') ?
            observedItem.isAttachment() : null;
        var isNote = (typeof observedItem.isNote === 'function') ?
            observedItem.isNote() : null;

        // Field snapshot AT FIRE TIME. Presence flags, not values: an empty
        // title here means the event fired before the translator populated
        // the item, which would make field-dependent rules unsafe at fire
        // time (OQ2 / rule design).
        var titleValue = '';
        var dateValue = '';
        var doiValue = '';
        var urlValue = '';
        var libraryCatalogValue = '';
        var publicationValue = '';
        var extraValue = '';
        var abstractValue = '';
        if (typeof observedItem.getField === 'function') {
            // getField throws for fields invalid on the item type, so each
            // read is guarded individually rather than in one block.
            try { titleValue = observedItem.getField('title') || ''; } catch (fieldError) { titleValue = ''; }
            try { dateValue = observedItem.getField('date') || ''; } catch (fieldError) { dateValue = ''; }
            try { doiValue = observedItem.getField('DOI') || ''; } catch (fieldError) { doiValue = ''; }
            try { urlValue = observedItem.getField('url') || ''; } catch (fieldError) { urlValue = ''; }
            try { libraryCatalogValue = observedItem.getField('libraryCatalog') || ''; } catch (fieldError) { libraryCatalogValue = ''; }
            try { publicationValue = observedItem.getField('publicationTitle') || ''; } catch (fieldError) { publicationValue = ''; }
            try { extraValue = observedItem.getField('extra') || ''; } catch (fieldError) { extraValue = ''; }
            try { abstractValue = observedItem.getField('abstractNote') || ''; } catch (fieldError) { abstractValue = ''; }
        }

        var creatorCount = 0;
        if (typeof observedItem.getCreators === 'function') {
            try { creatorCount = observedItem.getCreators().length; } catch (creatorError) { creatorCount = -1; }
        }

        var tagNames = [];
        if (typeof observedItem.getTags === 'function') {
            try {
                var rawTags = observedItem.getTags();
                for (var rawTag of rawTags) {
                    tagNames.push(rawTag.tag);
                }
            } catch (tagError) {
                tagNames = ['<getTags failed>'];
            }
        }

        var attachmentCount = -1;
        var noteCount = -1;
        if (isRegular === true) {
            try { attachmentCount = observedItem.getAttachments().length; } catch (childError) { attachmentCount = -1; }
            try { noteCount = observedItem.getNotes().length; } catch (childError) { noteCount = -1; }
        }

        var parentItemID = null;
        if (typeof observedItem.parentItemID !== 'undefined') {
            parentItemID = observedItem.parentItemID;
        }

        entry = {
            when: new Date().toISOString(),
            epochMs: Date.now(),
            sessionID: session.sessionID,
            fireOrdinalInSession: session.fireCount,
            probeEnabled: CONFIG.PROBE_ENABLED,
            itemID: observedItem.id,
            itemKey: observedItem.key,
            itemType: (typeof observedItem.itemType !== 'undefined') ? observedItem.itemType : null,
            isRegularItem: isRegular,
            isAttachment: isAttachment,
            isNote: isNote,
            parentItemID: parentItemID,
            // Q1 evidence: presence of translator-populated fields at fire time.
            hasTitle: titleValue.length > 0,
            titlePreview: titleValue.slice(0, CONFIG.TITLE_TRUNCATE),
            creatorCount: creatorCount,
            hasDate: dateValue.length > 0,
            hasDOI: doiValue.length > 0,
            hasURL: urlValue.length > 0,
            hasAbstract: abstractValue.length > 0,
            libraryCatalog: libraryCatalogValue,
            publicationTitle: publicationValue.slice(0, CONFIG.TITLE_TRUNCATE),
            extraPreview: extraValue.slice(0, CONFIG.TITLE_TRUNCATE),
            tags: tagNames,
            carriesMarkerTag: tagNames.indexOf(CONFIG.MARKER_TAG) !== -1,
            attachmentCount: attachmentCount,
            noteCount: noteCount,
            dateAdded: (typeof observedItem.dateAdded !== 'undefined') ? observedItem.dateAdded : null,
            dateModified: (typeof observedItem.dateModified !== 'undefined') ? observedItem.dateModified : null,
            probeAttempted: false,
            probeError: null
        };

        // --- Q2 PROBE: does a save inside the handler re-trigger the action?
        // Guarded three ways: opt-in flag, per-scope cap, and -- the guard
        // that actually holds if scopes do not persist -- the marker tag,
        // which is added BY the probe, so a re-fired item can never probe
        // twice. If a second log line appears for the same itemID with
        // carriesMarkerTag true, the answer to Q2 is YES.
        if (CONFIG.PROBE_ENABLED &&
            isRegular === true &&
            entry.carriesMarkerTag === false &&
            session.probeCount < CONFIG.PROBE_MAX_ITEMS &&
            typeof observedItem.addTag === 'function' &&
            typeof observedItem.saveTx === 'function') {
            session.probeCount = session.probeCount + 1;
            entry.probeAttempted = true;
            try {
                observedItem.addTag(CONFIG.MARKER_TAG);
                // Deliberately NOT awaited: whether an A&T action may await
                // is itself unverified, and a spike must not hang the add
                // path. Failures land in probeError on the NEXT fire's line
                // via the catch below.
                observedItem.saveTx();
            } catch (probeError) {
                entry.probeError = probeError.message;
            }
        }
    }

    // --- Append one JSON line. Fire-and-forget: the action must not block
    // item creation, and awaiting inside an A&T action is unverified (an
    // S3 unknown in its own right).
    var logDirectory = PathUtils.join(Zotero.DataDirectory.dir, CONFIG.LOG_SUBDIR);
    var logPath = PathUtils.join(logDirectory, CONFIG.LOG_FILE);
    var logLine = JSON.stringify(entry) + '\n';
    IOUtils.makeDirectory(logDirectory, { createAncestors: true, ignoreExisting: true })
        .then(function () {
            return IOUtils.writeUTF8(logPath, logLine, { mode: 'append' });
        })
        .catch(function (writeError) {
            Zotero.debug(`[spike_s3] log write failed: ${writeError.message}`);
        });

    // Mirror to debug as well, so a single fire is visible live in the
    // Debug Output window even before the log is analyzed.
    Zotero.debug(`[spike_s3] fire ${session.fireCount} session ${session.sessionID} ` +
        `item ${entry.itemID} type ${entry.itemType} hasTitle ${entry.hasTitle} ` +
        `creators ${entry.creatorCount} parent ${entry.parentItemID} ` +
        `probeAttempted ${entry.probeAttempted}`);

} catch (spikeError) {
    // A spike must never break the workflow it measures.
    Zotero.debug(`[spike_s3] ERROR (item creation NOT affected): ${spikeError.message}`);
}
