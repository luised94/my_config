// =============================================================================
// SPIKE S4: WRITE RELIABILITY AND REPORTING SURFACES (Actions & Tags action)
// =============================================================================
// STATUS: PENDING owner run (thread 3). Findings go into
// handoff/03_incoming_automation.md "Verified facts". Gates OQ3 (logging
// standard) and -- more importantly -- the WRITE STRATEGY of
// normalize-incoming-item.js.
//
// Version: 1.0.0
// Date:    2026-08
//
// THIS IS NOT A CONSOLE SCRIPT. It is an Actions & Tags ACTION.
// Registration: Event "Create Item", Operation "Script" (labels verified
// 2026-07). Disable the S3 action before enabling this one, so the two do
// not interleave in the same log analysis.
//
// WHY THIS SPIKE CHANGED SHAPE. It was originally scoped as "which logging
// surface should rules use" (OQ3). S3 run 2 found something that outranks
// that: an UNAWAITED saveTx at fire time was SILENTLY LOST on an item that
// was still being written (a Google Books item with an attachment landing
// concurrently), with probeError null because the rejection surfaced after
// the synchronous block returned. A rule that silently fails to apply is
// worse than one that throws. So S4 leads with write reliability and
// treats reporting surfaces as the secondary question.
//
// QUESTIONS, in priority order:
//   T1 Does an async function body actually run to completion inside an
//      A&T action? (If the host discards the promise, does our code after
//      the first await still execute?)
//   T2 Does an AWAITED save land where an unawaited one did not --
//      specifically on the high-risk case, an item still being written
//      because it arrived with an attachment?
//   T3 If a write is lost, does READ-BACK VERIFICATION detect it, and does
//      a retry recover it? This is the mechanism normalize-incoming-item.js
//      would have to use if awaiting alone is insufficient.
//   T4 ProgressWindow: does it work from inside an action, and is it
//      tolerable during a burst, or does it stack/stomp? (OQ3)
//
// NOTE ON TOP-LEVEL AWAIT. This script does NOT use a bare top-level
// `await`, deliberately: if the A&T host does not wrap action bodies in an
// async function, a top-level await is a PARSE error and the entire script
// fails to run, producing no log at all -- the failure mode would erase its
// own evidence. Instead everything async happens inside an async IIFE,
// which parses under either host behavior. To test top-level await
// separately, register a THROWAWAY action containing exactly these two
// lines and watch Debug Output:
//      Zotero.debug('[s4_tla] before');
//      await Promise.resolve(); Zotero.debug('[s4_tla] after');
//   Both lines  -> top-level await is supported.
//   Neither     -> parse error; top-level await is NOT supported.
//   Only first  -> supported but the continuation is being dropped.
//
// Safety:  This spike WRITES: it adds a marker tag to at most
//          PROBE_MAX_ITEMS items per scope, exactly as S3 did, and that is
//          the write whose reliability is being measured. Remove the tag
//          afterwards (search MARKER_TAG in Zotero). No field, file, or
//          path is touched. Loop safety is unnecessary for Create Item
//          (S3 run 2 proved saves do not re-trigger) but the marker-tag
//          guard is retained as defence in depth.
//
// REMEMBER the persisted-scope trap from S3: the action scope survives
//          across fires within a Zotero session, so PROBE_MAX_ITEMS is
//          consumed cumulatively. RESTART ZOTERO to reset it, or raise the
//          cap. probeBlocked in the log tells you which happened.
//
// HOW TO RUN
//   1. Disable the S3 action. Register this one. Restart Zotero (fresh
//      scope, so the cap is unspent).
//   2. Add 2-3 items THAT ARRIVE WITH ATTACHMENTS -- a Google Books save,
//      or a connector save of a PDF-bearing article. These reproduce the
//      concurrency that lost the write in S3 run 2. This is the case that
//      matters; plain metadata-only items are the easy path.
//   3. Add 1-2 items WITHOUT attachments as a control.
//   4. Watch for the ProgressWindow popups while doing so; note whether
//      they are informative or intrusive.
//   5. Run the ANALYZE snippet below and paste the result.
//
// ANALYZE -- Tools > Developer > Run JavaScript, "Run as async function"
// CHECKED:
//
//   var logPath = PathUtils.join(Zotero.DataDirectory.dir, 'spike_s4',
//       's4_write_log.jsonl');
//   var text = await IOUtils.readUTF8(logPath);
//   var entries = text.split('\n').filter(l => l.trim().length > 0)
//       .map(l => JSON.parse(l));
//   var summary = { totalFires: entries.length, asyncBodyCompleted: 0,
//       awaitResolved: 0, landedFirstTry: 0, landedAfterRetry: 0,
//       lostDespiteRetry: 0, probeBlocked: 0, progressWindowOk: 0,
//       progressWindowFailed: 0, withAttachment: 0, errors: [] };
//   for (var e of entries) {
//       if (e.asyncBodyCompleted) summary.asyncBodyCompleted++;
//       if (e.awaitResolved) summary.awaitResolved++;
//       if (e.writeOutcome === 'landed_first_try') summary.landedFirstTry++;
//       if (e.writeOutcome === 'landed_after_retry') summary.landedAfterRetry++;
//       if (e.writeOutcome === 'lost_despite_retry') summary.lostDespiteRetry++;
//       if (e.writeOutcome === 'probe_blocked') summary.probeBlocked++;
//       if (e.progressWindowOk === true) summary.progressWindowOk++;
//       if (e.progressWindowOk === false) summary.progressWindowFailed++;
//       if (e.attachmentCountAtFire > 0) summary.withAttachment++;
//       if (e.errorMessage) summary.errors.push(e.errorMessage);
//   }
//   summary.perFire = entries.map(e => ({ itemID: e.itemID,
//       attach: e.attachmentCountAtFire, outcome: e.writeOutcome,
//       msSinceModified: e.msSinceDateModified, retries: e.retryCount }));
//   return summary;
//
// READING THE RESULT
//   asyncBodyCompleted == totalFires -> async bodies run to completion.
//   landedFirstTry == probes         -> awaiting alone is sufficient; the
//                                       rules engine can just await.
//   landedAfterRetry > 0             -> awaiting is NOT sufficient;
//                                       read-back verification plus retry
//                                       is MANDATORY in the rules engine.
//   lostDespiteRetry > 0             -> writes at fire time are unsafe
//                                       even with retry; the engine must
//                                       defer writes out of the handler.
// =============================================================================

// 1. CONFIGURATION
var CONFIG = {
    PROBE_ENABLED: true,          // this spike exists to write; false makes it inert
    PROBE_MAX_ITEMS: 5,           // per scope; consumed cumulatively (see header)

    MARKER_TAG: '__spike-s4-write',
    LOG_SUBDIR: 'spike_s4',
    LOG_FILE: 's4_write_log.jsonl',

    VERIFY_DELAY_MS: 400,         // settle time before read-back; ~1 burst gap (S3: 415ms)
    MAX_RETRIES: 2,               // retries after a failed verification
    RETRY_BACKOFF_MS: 800,

    TEST_PROGRESS_WINDOW: true,   // T4 (OQ3)
    PROGRESS_WINDOW_MS: 1500
};

// 2. STATE (persists across fires within a session -- S3 finding)
if (typeof globalThis.__spikeS4Session === 'undefined') {
    globalThis.__spikeS4Session = {
        sessionID: String(Date.now()) + '-' + String(Math.floor(Math.random() * 100000)),
        fireCount: 0,
        probeCount: 0
    };
}
var session = globalThis.__spikeS4Session;

// 3. MAIN
try {
    session.fireCount = session.fireCount + 1;
    var observedItem = (typeof item !== 'undefined') ? item : null;

    // Snapshot the concurrency context SYNCHRONOUSLY, before any await, so
    // it reflects the item as the handler first saw it. msSinceDateModified
    // is the key correlate: S3's lost write happened on an item modified
    // ~1s before the fire, i.e. still actively being written.
    var attachmentCountAtFire = -1;
    var msSinceDateModified = null;
    var itemIDAtFire = null;
    var itemTypeAtFire = null;
    if (observedItem !== null) {
        itemIDAtFire = observedItem.id;
        itemTypeAtFire = observedItem.itemType;
        try { attachmentCountAtFire = observedItem.getAttachments().length; } catch (attachError) { attachmentCountAtFire = -1; }
        try {
            // dateModified is a SQL-style UTC string; treat it as UTC.
            var modifiedMs = Date.parse(String(observedItem.dateModified).replace(' ', 'T') + 'Z');
            if (!isNaN(modifiedMs)) {
                msSinceDateModified = Date.now() - modifiedMs;
            }
        } catch (dateError) {
            msSinceDateModified = null;
        }
    }

    var entry = {
        when: new Date().toISOString(),
        epochMs: Date.now(),
        sessionID: session.sessionID,
        fireOrdinalInSession: session.fireCount,
        itemID: itemIDAtFire,
        itemType: itemTypeAtFire,
        attachmentCountAtFire: attachmentCountAtFire,
        msSinceDateModified: msSinceDateModified,
        asyncBodyCompleted: false,   // T1
        awaitResolved: false,        // T1
        writeOutcome: 'not_attempted',
        retryCount: 0,
        progressWindowOk: null,      // T4
        errorMessage: null
    };

    // --- T4 ProgressWindow, synchronous part. Done before the async work so
    // it is visible even if the async body is discarded by the host.
    if (CONFIG.TEST_PROGRESS_WINDOW) {
        try {
            var progressWindow = new Zotero.ProgressWindow();
            progressWindow.changeHeadline('Spike S4');
            progressWindow.addDescription(`fire ${session.fireCount} item ${itemIDAtFire}`);
            progressWindow.show();
            progressWindow.startCloseTimer(CONFIG.PROGRESS_WINDOW_MS);
            entry.progressWindowOk = true;
        } catch (progressError) {
            entry.progressWindowOk = false;
            entry.errorMessage = `ProgressWindow: ${progressError.message}`;
        }
    }

    // --- Async IIFE. Parses regardless of whether the host wraps action
    // bodies in an async function (see header). If the host discards the
    // promise, the work may still run -- asyncBodyCompleted records it.
    (async function () {
        try {
            // T1: does execution survive an await at all?
            await new Promise(function (resolve) { setTimeout(resolve, 1); });
            entry.awaitResolved = true;

            if (observedItem === null) {
                entry.writeOutcome = 'no_item_binding';
            } else if (!CONFIG.PROBE_ENABLED) {
                entry.writeOutcome = 'probe_disabled';
            } else if (session.probeCount >= CONFIG.PROBE_MAX_ITEMS) {
                // Cap consumed earlier in this scope (the S3 trap).
                entry.writeOutcome = 'probe_blocked';
            } else {
                session.probeCount = session.probeCount + 1;

                // T2 + T3: awaited write, then READ-BACK VERIFICATION, then
                // retry. Verification re-fetches the item rather than
                // trusting the in-memory object, because the whole failure
                // mode being tested is a write that appears to succeed on a
                // stale object while another writer wins.
                var attemptIndex = 0;
                var landed = false;
                while (attemptIndex <= CONFIG.MAX_RETRIES && !landed) {
                    if (attemptIndex > 0) {
                        entry.retryCount = attemptIndex;
                        await new Promise(function (resolve) {
                            setTimeout(resolve, CONFIG.RETRY_BACKOFF_MS);
                        });
                    }
                    try {
                        var writeTarget = await Zotero.Items.getAsync(itemIDAtFire);
                        writeTarget.addTag(CONFIG.MARKER_TAG);
                        await writeTarget.saveTx();
                    } catch (saveError) {
                        entry.errorMessage = `save attempt ${attemptIndex}: ${saveError.message}`;
                    }

                    await new Promise(function (resolve) {
                        setTimeout(resolve, CONFIG.VERIFY_DELAY_MS);
                    });

                    try {
                        var verifyItem = await Zotero.Items.getAsync(itemIDAtFire);
                        var verifyTags = verifyItem.getTags();
                        for (var verifyTag of verifyTags) {
                            if (verifyTag.tag === CONFIG.MARKER_TAG) {
                                landed = true;
                                break;
                            }
                        }
                    } catch (verifyError) {
                        entry.errorMessage = `verify attempt ${attemptIndex}: ${verifyError.message}`;
                    }
                    attemptIndex = attemptIndex + 1;
                }

                if (landed && entry.retryCount === 0) {
                    entry.writeOutcome = 'landed_first_try';
                } else if (landed) {
                    entry.writeOutcome = 'landed_after_retry';
                } else {
                    entry.writeOutcome = 'lost_despite_retry';
                }
            }

            entry.asyncBodyCompleted = true;
        } catch (asyncError) {
            entry.errorMessage = `async body: ${asyncError.message}`;
        }

        // Log LAST, so the entry reflects the final outcome. The debug
        // mirror is the guarantee; the file is the convenience (S3 lesson).
        Zotero.debug(`[spike_s4_entry] ${JSON.stringify(entry)}`);
        var logDirectory = PathUtils.join(Zotero.DataDirectory.dir, CONFIG.LOG_SUBDIR);
        var logPath = PathUtils.join(logDirectory, CONFIG.LOG_FILE);
        try {
            await IOUtils.makeDirectory(logDirectory,
                { createAncestors: true, ignoreExisting: true });
            // 'appendOrCreate', never 'append': 'append' refuses to create a
            // missing file (IOUtils WebIDL). This cost the first S3 run.
            await IOUtils.writeUTF8(logPath, JSON.stringify(entry) + '\n',
                { mode: 'appendOrCreate' });
        } catch (writeError) {
            Zotero.debug(`[spike_s4] LOG WRITE FAILED (entry preserved in the ` +
                `[spike_s4_entry] line above): ${writeError.message}`);
        }
    })();

} catch (spikeError) {
    Zotero.debug(`[spike_s4] ERROR (item creation NOT affected): ${spikeError.message}`);
}
