// =============================================================================
// SPIKE S5: ANNOTATION MODEL AND EXPORT PATHWAY INTROSPECTION
// =============================================================================
// STATUS: PENDING owner run (thread 4). Findings go into
// handoff/04_annotation_export.md "Verified facts". Thread 4 is EXPLORATORY
// and its handoff forbids drafting implementation before this spike
// populates that section -- so this script DECIDES NOTHING. It only
// measures.
//
// Version: 1.0.0
// Date:    2026-08
//
// Usage:   Tools > Developer > Run JavaScript.
//          CHECK THE "Run as async function" CHECKBOX (A10.2).
//          This IS a console script (unlike S3/S4, which were A&T actions).
//
// Safety:  STRICTLY READ-ONLY. It reads the database and reads bytes from
//          attachment files. It writes NOTHING to the library and NOTHING
//          to disk -- not even a log file, because the result is small
//          enough to return directly. No annotation, item, file, or path
//          is modified.
//
// Reads file bytes: yes, and deliberately. Answering "does an exported PDF
//          embed the Zotero item key" requires inspecting raw PDF bytes.
//          NOTE this is the one place in the repo where reading file
//          CONTENT is required -- the orphan tooling was careful to use
//          metadata only so Dropbox online-only placeholders would not
//          hydrate (S2). This script DOES hydrate the files it samples.
//          That is why SAMPLE_ATTACHMENT_COUNT is small and why it prefers
//          attachments that are already local. Keep the sample small.
//
// S5 questions (from handoff/04), and how each is answered:
//   Q1 What do the annotation APIs expose? -> enumerate annotations on
//      sampled attachments and report the shape of one, plus a
//      library-wide census by type/color, done in SQL.
//   Q2 Are annotations stored in the DB or in the file? -> compare the DB
//      annotation count for an attachment against whether the PDF bytes
//      contain PDF annotation markers (/Annots, /Highlight, /Popup).
//   Q3 Does any PDF embed the Zotero item key or another identifier?
//      -> scan the sampled PDF bytes for the attachment key, the parent
//      key, and generic Zotero markers.
//   Q4 What write pathways exist for embedding annotations into a PDF?
//      -> probe for the presence (NOT invocation) of plausible internal
//      APIs and report which exist on this build.
//   Q5 Does Better Notes pull annotations? -> report which item-note
//      relationships exist and whether note content references
//      annotation keys.
//   Q6 Are citation keys a stabler external identifier than item keys?
//      -> report BBT citation key availability for the sampled items.
//   Q7 (OQ4) scope: are there annotations on non-PDF attachments
//      (epub/html/snapshot)? -> census by attachment content type.
//
// WHAT TO DO WITH THE RESULT: paste the returned object into
//      handoff/04_annotation_export.md. Then OQ1 (primary purpose:
//      backup vs external reading vs notes workflow) is an OWNER decision
//      that the data informs but does not make.
// =============================================================================

// 1. CONFIGURATION
var CONFIG = {
    // Keep small: sampling reads file bytes and WILL hydrate online-only
    // placeholders (see header).
    SAMPLE_ATTACHMENT_COUNT: 5,
    PDF_HEAD_BYTES: 65536,        // bytes read from the start of each sampled PDF
    PDF_TAIL_BYTES: 65536,        // and from the end, where /Annots often live
    MAX_ANNOTATIONS_DETAILED: 5,  // full field dump for this many annotations
    ANNOTATION_TEXT_PREVIEW: 80,

    // Internal APIs to PROBE FOR EXISTENCE ONLY. None are called.
    CANDIDATE_EXPORT_APIS: [
        'Zotero.Annotations',
        'Zotero.Annotations.toJSON',
        'Zotero.Annotations.saveFromJSON',
        'Zotero.Attachments.exportPDF',
        'Zotero.Attachments.hasEmbeddedAnnotations',
        'Zotero.Reader',
        'Zotero.Reader.getByTabID',
        'Zotero.PDFWorker',
        'Zotero.PDFWorker.export',
        'Zotero.PDFWorker.import',
        'Zotero.PDFWorker.getFulltext'
    ],

    MIN_ZOTERO_VERSION: '7.0',
    MAX_ZOTERO_VERSION: '9.0.6',
    BYPASS_VERSION_CHECK: false
};

// 2. STATE
var timing = { scriptStart: Date.now(), assertions: 0 };
var debugLines = [];

function report(line) {
    debugLines.push(line);
    Zotero.debug(`[spike_s5] ${line}`);
}

function assert(condition, message) {
    timing.assertions = timing.assertions + 1;
    if (!condition) {
        throw new Error(`spike_s5 pre-flight failed: ${message}`);
    }
}

try {

// 3. PRE-FLIGHT
report(`starting, Zotero ${Zotero.version}`);
var belowMin = Services.vc.compare(Zotero.version, CONFIG.MIN_ZOTERO_VERSION) < 0;
var aboveMax = Services.vc.compare(Zotero.version, CONFIG.MAX_ZOTERO_VERSION) > 0;
if ((belowMin || aboveMax) && !CONFIG.BYPASS_VERSION_CHECK) {
    throw new Error(`Zotero ${Zotero.version} outside tested range; ` +
        'set CONFIG.BYPASS_VERSION_CHECK = true to override.');
}
assert(typeof Zotero.DB.queryAsync === 'function', 'Zotero.DB.queryAsync unavailable');
assert(typeof Zotero.Items.getAsync === 'function', 'Zotero.Items.getAsync unavailable');
assert(typeof IOUtils !== 'undefined' && typeof IOUtils.read === 'function',
    'IOUtils.read unavailable');
var userLibraryID = Zotero.Libraries.userLibraryID;

// 4. Q1 + Q7: library-wide annotation census, pure SQL (no item objects).
// itemAnnotations holds one row per annotation, keyed to its parent
// ATTACHMENT item. Types are integers; the map is reported rather than
// assumed so a build difference shows up as an unfamiliar number.
var annotationCensus = [];
var annotationTotal = 0;
try {
    var censusRows = await Zotero.DB.queryAsync(
        'SELECT ia.type AS type, COUNT(*) AS n ' +
        'FROM itemAnnotations ia ' +
        'JOIN items i ON ia.itemID = i.itemID ' +
        'LEFT JOIN deletedItems di ON di.itemID = ia.itemID ' +
        'WHERE i.libraryID = ? AND di.itemID IS NULL ' +
        'GROUP BY ia.type ORDER BY n DESC',
        [userLibraryID]);
    for (var censusRow of censusRows) {
        annotationCensus.push({ type: censusRow.type, count: censusRow.n });
        annotationTotal = annotationTotal + censusRow.n;
    }
} catch (censusError) {
    annotationCensus = [{ error: censusError.message }];
}
report(`annotation census: ${annotationTotal} total across ${annotationCensus.length} type(s)`);

// Q7: which attachment content types carry annotations (PDF only, or
// epub/html too)? This settles OQ4's scope question with data.
var annotationsByContentType = [];
try {
    var contentTypeRows = await Zotero.DB.queryAsync(
        'SELECT att.contentType AS contentType, ' +
        '       COUNT(DISTINCT ann.itemID) AS annotationCount, ' +
        '       COUNT(DISTINCT ann.parentItemID) AS attachmentCount ' +
        'FROM itemAnnotations ann ' +
        'JOIN itemAttachments att ON ann.parentItemID = att.itemID ' +
        'JOIN items i ON ann.itemID = i.itemID ' +
        'LEFT JOIN deletedItems di ON di.itemID = ann.itemID ' +
        'WHERE i.libraryID = ? AND di.itemID IS NULL ' +
        'GROUP BY att.contentType ORDER BY annotationCount DESC',
        [userLibraryID]);
    for (var contentTypeRow of contentTypeRows) {
        annotationsByContentType.push({
            contentType: contentTypeRow.contentType,
            annotations: contentTypeRow.annotationCount,
            attachments: contentTypeRow.attachmentCount
        });
    }
} catch (contentTypeError) {
    annotationsByContentType = [{ error: contentTypeError.message }];
}

// 5. Pick the most-annotated attachments as the sample.
var sampleRows = [];
try {
    sampleRows = await Zotero.DB.queryAsync(
        'SELECT ann.parentItemID AS attachmentItemID, COUNT(*) AS annotationCount ' +
        'FROM itemAnnotations ann ' +
        'JOIN items i ON ann.itemID = i.itemID ' +
        'LEFT JOIN deletedItems di ON di.itemID = ann.itemID ' +
        'WHERE i.libraryID = ? AND di.itemID IS NULL ' +
        'GROUP BY ann.parentItemID ORDER BY annotationCount DESC LIMIT ?',
        [userLibraryID, CONFIG.SAMPLE_ATTACHMENT_COUNT]);
} catch (sampleError) {
    report(`sample query failed: ${sampleError.message}`);
}
report(`sampling ${sampleRows.length} attachment(s)`);

// 6. Per-sample introspection: API shape, DB-vs-file storage, id embedding.
var samples = [];
var annotationShapeExample = null;
for (var sampleRow of sampleRows) {
    var sample = {
        attachmentItemID: sampleRow.attachmentItemID,
        annotationCountInDB: sampleRow.annotationCount,
        attachmentKey: null,
        parentItemKey: null,
        parentTitlePreview: null,
        citationKey: null,
        contentType: null,
        filePath: null,
        fileExists: null,
        fileBytesRead: 0,
        // Q2 evidence
        pdfHasAnnotsMarker: null,
        pdfHasHighlightMarker: null,
        pdfHasPopupMarker: null,
        // Q3 evidence
        pdfContainsAttachmentKey: null,
        pdfContainsParentKey: null,
        pdfContainsZoteroMarker: null,
        annotationApiCount: null,
        annotationsDetailed: [],
        error: null
    };
    try {
        var attachmentItem = await Zotero.Items.getAsync(sampleRow.attachmentItemID);
        sample.attachmentKey = attachmentItem.key;
        sample.contentType = attachmentItem.attachmentContentType;

        var parentItem = null;
        if (attachmentItem.parentItemID) {
            parentItem = await Zotero.Items.getAsync(attachmentItem.parentItemID);
            sample.parentItemKey = parentItem.key;
            try {
                sample.parentTitlePreview = String(parentItem.getField('title') || '').slice(0, 60);
            } catch (titleError) {
                sample.parentTitlePreview = null;
            }
        }

        // Q6: is a BBT citation key available as an external identifier?
        // Read via the extra field and the BBT API if present; never assume.
        if (parentItem !== null) {
            try {
                if (typeof Zotero.BetterBibTeX !== 'undefined' &&
                    Zotero.BetterBibTeX.KeyManager &&
                    typeof Zotero.BetterBibTeX.KeyManager.get === 'function') {
                    var keyRecord = Zotero.BetterBibTeX.KeyManager.get(parentItem.id);
                    sample.citationKey = (keyRecord && keyRecord.citationKey) ?
                        keyRecord.citationKey : null;
                }
            } catch (bbtError) {
                sample.citationKey = `<BBT lookup failed: ${bbtError.message}>`;
            }
        }

        // Q1: the annotation API surface, via the attachment.
        if (typeof attachmentItem.getAnnotations === 'function') {
            var annotations = attachmentItem.getAnnotations();
            sample.annotationApiCount = annotations.length;
            var detailLimit = Math.min(annotations.length, CONFIG.MAX_ANNOTATIONS_DETAILED);
            for (var detailIndex = 0; detailIndex < detailLimit; detailIndex++) {
                var annotation = annotations[detailIndex];
                var detail = {
                    key: annotation.key,
                    type: annotation.annotationType,
                    color: annotation.annotationColor,
                    pageLabel: annotation.annotationPageLabel,
                    sortIndex: annotation.annotationSortIndex,
                    hasPosition: typeof annotation.annotationPosition !== 'undefined' &&
                        annotation.annotationPosition !== null,
                    textPreview: String(annotation.annotationText || '')
                        .slice(0, CONFIG.ANNOTATION_TEXT_PREVIEW),
                    commentPreview: String(annotation.annotationComment || '')
                        .slice(0, CONFIG.ANNOTATION_TEXT_PREVIEW),
                    tagCount: (typeof annotation.getTags === 'function') ?
                        annotation.getTags().length : null,
                    dateModified: annotation.dateModified,
                    isExternal: (typeof annotation.annotationIsExternal !== 'undefined') ?
                        annotation.annotationIsExternal : null
                };
                sample.annotationsDetailed.push(detail);
                // Keep one full property listing so the handoff records the
                // real API shape rather than this script's guess at it.
                if (annotationShapeExample === null) {
                    var propertyNames = [];
                    for (var propertyName in annotation) {
                        if (propertyName.indexOf('annotation') === 0) {
                            propertyNames.push(propertyName);
                        }
                    }
                    annotationShapeExample = {
                        annotationPropertiesFound: propertyNames.sort(),
                        sampleKey: annotation.key
                    };
                }
            }
        }

        // Q2 + Q3: inspect the actual file bytes. This is the only part of
        // the repo that reads file CONTENT (see header warning).
        var filePath = attachmentItem.getFilePath();
        sample.filePath = filePath;
        if (filePath) {
            var fileExists = await IOUtils.exists(filePath);
            sample.fileExists = fileExists;
            if (fileExists) {
                var fileInfo = await IOUtils.stat(filePath);
                var fileSize = fileInfo.size;
                var headBytes = await IOUtils.read(filePath,
                    { maxBytes: Math.min(CONFIG.PDF_HEAD_BYTES, fileSize) });
                // Latin1 keeps byte values intact for marker searching;
                // UTF-8 decoding would corrupt binary PDF content.
                var decoder = new TextDecoder('latin1');
                var headText = decoder.decode(headBytes);
                var tailText = '';
                if (fileSize > CONFIG.PDF_HEAD_BYTES) {
                    // IOUtils.read has no offset parameter, so reading the
                    // tail means reading up to the end and slicing. Bounded
                    // by PDF_HEAD + PDF_TAIL to avoid pulling huge files.
                    var tailReadSize = Math.min(fileSize,
                        CONFIG.PDF_HEAD_BYTES + CONFIG.PDF_TAIL_BYTES);
                    var tailBytes = await IOUtils.read(filePath, { maxBytes: tailReadSize });
                    tailText = decoder.decode(
                        tailBytes.slice(Math.max(0, tailBytes.length - CONFIG.PDF_TAIL_BYTES)));
                }
                var combinedText = headText + tailText;
                sample.fileBytesRead = headBytes.length +
                    (tailText.length > 0 ? CONFIG.PDF_TAIL_BYTES : 0);

                sample.pdfHasAnnotsMarker = combinedText.indexOf('/Annots') !== -1;
                sample.pdfHasHighlightMarker = combinedText.indexOf('/Highlight') !== -1;
                sample.pdfHasPopupMarker = combinedText.indexOf('/Popup') !== -1;
                sample.pdfContainsAttachmentKey = sample.attachmentKey !== null &&
                    combinedText.indexOf(sample.attachmentKey) !== -1;
                sample.pdfContainsParentKey = sample.parentItemKey !== null &&
                    combinedText.indexOf(sample.parentItemKey) !== -1;
                sample.pdfContainsZoteroMarker =
                    combinedText.toLowerCase().indexOf('zotero') !== -1;
            }
        }
    } catch (sampleProcessError) {
        sample.error = sampleProcessError.message;
    }
    samples.push(sample);
}

// 7. Q4: which write/export pathways EXIST on this build. Existence probe
// only -- nothing here is invoked, because invoking an export or import
// pathway would write files or annotations, which this spike must not do.
var apiProbe = {};
for (var apiPath of CONFIG.CANDIDATE_EXPORT_APIS) {
    var segments = apiPath.split('.');
    var cursor = globalThis;
    var exists = true;
    for (var segment of segments) {
        if (cursor === undefined || cursor === null || typeof cursor[segment] === 'undefined') {
            exists = false;
            break;
        }
        cursor = cursor[segment];
    }
    apiProbe[apiPath] = exists ? (typeof cursor) : 'absent';
}

// 8. Q5: Better Notes / notes relationship to annotations. Counts only.
var noteStats = { totalNotes: 0, notesMentioningAnnotationKeys: 0, error: null };
try {
    var noteCountRows = await Zotero.DB.queryAsync(
        'SELECT COUNT(*) AS n FROM itemNotes inote ' +
        'JOIN items i ON inote.itemID = i.itemID ' +
        'LEFT JOIN deletedItems di ON di.itemID = inote.itemID ' +
        'WHERE i.libraryID = ? AND di.itemID IS NULL',
        [userLibraryID]);
    noteStats.totalNotes = noteCountRows[0].n;
    // Zotero's "add note from annotations" embeds citation markup that
    // references annotation keys; a LIKE probe is enough to tell whether
    // the notes workflow is already annotation-aware.
    var noteMentionRows = await Zotero.DB.queryAsync(
        'SELECT COUNT(*) AS n FROM itemNotes inote ' +
        'JOIN items i ON inote.itemID = i.itemID ' +
        'LEFT JOIN deletedItems di ON di.itemID = inote.itemID ' +
        'WHERE i.libraryID = ? AND di.itemID IS NULL ' +
        "  AND inote.note LIKE '%annotationKey%'",
        [userLibraryID]);
    noteStats.notesMentioningAnnotationKeys = noteMentionRows[0].n;
} catch (noteError) {
    noteStats.error = noteError.message;
}

} catch (e) {
    Zotero.debug(`[spike_s5] ERROR: ${e.message}\n${e.stack}`);
    throw e;
}

// 9. SUMMARY
timing.totalMs = Date.now() - timing.scriptStart;
report(`done in ${timing.totalMs} ms`);
return {
    zoteroVersion: Zotero.version,
    annotationTotal: annotationTotal,
    annotationCensusByType: annotationCensus,
    annotationsByAttachmentContentType: annotationsByContentType,
    annotationApiShape: annotationShapeExample,
    samples: samples,
    exportApiProbe: apiProbe,
    noteStats: noteStats,
    timing: timing,
    readingNotes: [
        'annotationCensusByType: integer types are reported raw; map them ' +
            'from the API shape rather than assuming 1=highlight etc.',
        'pdfHasAnnotsMarker false while annotationCountInDB > 0 means ' +
            'annotations live ONLY in the database (Zotero 7 default) and ' +
            'an external reader would see none -- the core Q2 answer.',
        'pdfContainsAttachmentKey / pdfContainsParentKey answer the ' +
            'id-embedding hypothesis that motivated thread 4. If both are ' +
            'false on every sample, exported PDFs do NOT carry the item id ' +
            'and that premise needs revisiting.',
        'exportApiProbe shows only what EXISTS; nothing was invoked. A ' +
            'present PDFWorker export function is the most likely internal ' +
            'write pathway, but confirming it needs a separate, gated test.'
    ]
};
