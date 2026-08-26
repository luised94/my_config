# Slice 1 extractor. Reads a COLD COPY of zotero.sqlite (never the live file),
# extracts RAW bibliographic fields (no transforms -- year-parsing and folding are
# Slice 2), filters to real items in the single library, and writes a
# deterministic JSONL corpus plus a sidecar integrity manifest.
#
# DETERMINISM (why it matters): the corpus is not committed to git; its integrity
# across threads rests on a recomputable sha256. That is only meaningful if the
# extractor is a pure function of the frozen snapshot. So: rows are emitted in
# ORDER BY itemID, each item's creator sublist in ORDER BY orderIndex, and every
# JSON object is serialized with sort_keys=True and no wall-clock field. Re-running
# against the same frozen copy yields byte-identical output. (Integrity plan.)
#
# Dependencies: stdlib only (sqlite3, json, unicodedata, hashlib, collections,
# argparse, os, sys). Zero external. Budget untouched.

import sqlite3
import json
import unicodedata
import hashlib
import collections
import argparse
import os
import sys

# ----------------------------------------------------------------------------
# In-script toggles (edited in place; no argument parsing for one-off switches,
# per the working style). argparse is used ONLY for the two real path inputs.
# ----------------------------------------------------------------------------

# If more than one library is found, halt rather than silently extracting one.
# The plan states a single personal library; a second library violates a stated
# assumption and must be surfaced, not guessed around. Flip to False to instead
# extract PERSONAL_LIBRARY_ID_WHEN_MULTIPLE below.
HALT_ON_MULTIPLE_LIBRARIES = True

# Only consulted when HALT_ON_MULTIPLE_LIBRARIES is False: which library to keep.
PERSONAL_LIBRARY_ID_WHEN_MULTIPLE = 1

# Item types that are NOT real bibliographic items. Excluded and counted in the
# funnel. These names match Zotero's itemTypes.typeName.
NON_BIBLIOGRAPHIC_ITEM_TYPE_NAMES = ("attachment", "note", "annotation")

# The probe itemIDs for the hand-check gate (Stage D). Populate with the real
# itemIDs of the deliberately-chosen sample (multi-author, edited volume,
# institutional author, no-date, non-ASCII author, distinctive-title book) once
# they are known from Zotero. When non-empty, the extractor prints these records
# in full and exits WITHOUT writing the corpus, so the human can eyeball them
# against the Zotero UI before trusting a bulk run. Empty list => bulk mode.
PROBE_ITEM_IDS = []


def fold_to_ascii(text):
    # NFKD decomposition + strip combining marks. This is a MEASUREMENT helper for
    # the non-ASCII author fraction only; it is NOT the deployed fold (that is
    # Slice 2, kept in BBT parity). Kept here so the headline non-ASCII metric can
    # be reported without importing Slice 2 logic.
    if text is None:
        return None
    decomposed = unicodedata.normalize("NFKD", text)
    return "".join(
        character for character in decomposed if not unicodedata.combining(character)
    )


def main():
    argument_parser = argparse.ArgumentParser(
        description="Extract the frozen Zotero corpus to JSONL (Slice 1)."
    )
    argument_parser.add_argument(
        "--cold-copy-path",
        required=True,
        help="Path to the COLD COPY of zotero.sqlite in the WSL working dir.",
    )
    argument_parser.add_argument(
        "--corpus-output-path",
        required=True,
        help="Path to write the JSONL corpus (regenerable; not committed).",
    )
    argument_parser.add_argument(
        "--frozen-snapshot-size-bytes",
        required=True,
        type=int,
        help="Frozen snapshot size from the cold-copy step, recorded in the sidecar.",
    )
    argument_parser.add_argument(
        "--frozen-snapshot-mtime-epoch-utc",
        required=True,
        type=int,
        help="Frozen snapshot mtime from the cold-copy step, recorded in the sidecar.",
    )
    arguments = argument_parser.parse_args()

    if not os.path.exists(arguments.cold_copy_path):
        print("HALT: cold copy not found at", arguments.cold_copy_path)
        sys.exit(1)

    # Read-only connection to the COPY. immutable=1 tells SQLite the file will not
    # change, which both speeds the read and refuses accidental writes; the copy is
    # the immutable source of truth for the whole experiment.
    connection = sqlite3.connect(
        "file:%s?immutable=1" % arguments.cold_copy_path, uri=True
    )
    connection.row_factory = sqlite3.Row
    cursor = connection.cursor()

    # ------------------------------------------------------------------
    # Library check (verify, don't trust). Count distinct libraries that
    # actually hold items, not just rows in the libraries table.
    # ------------------------------------------------------------------
    library_id_rows = cursor.execute(
        "SELECT DISTINCT libraryID FROM items ORDER BY libraryID"
    ).fetchall()
    distinct_library_ids = [row["libraryID"] for row in library_id_rows]
    print("distinct_library_ids=%s" % distinct_library_ids)
    if len(distinct_library_ids) > 1:
        if HALT_ON_MULTIPLE_LIBRARIES:
            print(
                "HALT: %d libraries found (%s); plan assumes one. "
                "Flip HALT_ON_MULTIPLE_LIBRARIES to extract a single library."
                % (len(distinct_library_ids), distinct_library_ids)
            )
            sys.exit(1)
        library_filter_id = PERSONAL_LIBRARY_ID_WHEN_MULTIPLE
        print(
            "NOTE: multiple libraries; extracting libraryID=%d only."
            % library_filter_id
        )
    else:
        library_filter_id = distinct_library_ids[0] if distinct_library_ids else None

    # ------------------------------------------------------------------
    # Funnel stage counts. Each filter reported with a number so a lost stage
    # is visible. (Plan: report the funnel.)
    # ------------------------------------------------------------------
    raw_item_count = cursor.execute(
        "SELECT COUNT(*) AS n FROM items WHERE libraryID = ?", (library_filter_id,)
    ).fetchone()["n"]

    # Field id lookups by name, so the extraction query is readable and does not
    # hardcode numeric field ids (they vary across Zotero installs).
    field_id_by_name = {}
    for field_row in cursor.execute("SELECT fieldID, fieldName FROM fields").fetchall():
        field_id_by_name[field_row["fieldName"]] = field_row["fieldID"]

    # Fields we pull as raw values, keyed by the corpus field name we emit. Context
    # fields (venue, publisher, DOI, ISBN, volume, edition, language, pages,
    # numPages, shortTitle) are pulled NOW -- this is the one slice that reads
    # zotero.sqlite, so a second pass is avoided. citationKey (native field) is
    # pulled to let Slice 2 decide the authoritative key source (BBT may have
    # folded keys into it).
    corpus_field_names = [
        "title",
        "date",
        "shortTitle",
        "publicationTitle",
        "publisher",
        "DOI",
        "ISBN",
        "volume",
        "edition",
        "language",
        "pages",
        "numPages",
        "citationKey",
    ]

    # Build the set of itemIDs that survive the type and trash filters.
    surviving_item_rows = cursor.execute(
        """
        SELECT items.itemID AS itemID,
               itemTypes.typeName AS itemType,
               items.dateAdded AS dateAdded,
               items.key AS zoteroKey
        FROM items
        JOIN itemTypes ON items.itemTypeID = itemTypes.itemTypeID
        WHERE items.libraryID = ?
          AND itemTypes.typeName NOT IN (%s)
          AND items.itemID NOT IN (SELECT itemID FROM deletedItems)
        ORDER BY items.itemID
    """
        % ",".join("?" for _ in NON_BIBLIOGRAPHIC_ITEM_TYPE_NAMES),
        (library_filter_id,) + NON_BIBLIOGRAPHIC_ITEM_TYPE_NAMES,
    ).fetchall()

    after_type_and_trash_count = len(surviving_item_rows)

    # Count how many were removed by each filter, separately, for the funnel.
    non_biblio_count = cursor.execute(
        """
        SELECT COUNT(*) AS n FROM items
        JOIN itemTypes ON items.itemTypeID = itemTypes.itemTypeID
        WHERE items.libraryID = ?
          AND itemTypes.typeName IN (%s)
    """
        % ",".join("?" for _ in NON_BIBLIOGRAPHIC_ITEM_TYPE_NAMES),
        (library_filter_id,) + NON_BIBLIOGRAPHIC_ITEM_TYPE_NAMES,
    ).fetchone()["n"]

    trashed_count = cursor.execute(
        """
        SELECT COUNT(*) AS n FROM items
        WHERE items.libraryID = ?
          AND items.itemID IN (SELECT itemID FROM deletedItems)
    """,
        (library_filter_id,),
    ).fetchone()["n"]

    # ------------------------------------------------------------------
    # Pull all creators for surviving items in one query, ordered so we can
    # group deterministically. ORDER BY itemID, orderIndex is the whole point:
    # first author = first row per item AFTER this sort, never assumed.
    # ------------------------------------------------------------------
    surviving_item_id_list = [row["itemID"] for row in surviving_item_rows]

    creators_by_item = collections.defaultdict(list)
    if surviving_item_id_list:
        # Chunk the IN-list to stay under SQLite's variable limit on large corpora.
        CHUNK_SIZE = 500
        for chunk_start in range(0, len(surviving_item_id_list), CHUNK_SIZE):
            chunk_ids = surviving_item_id_list[chunk_start : chunk_start + CHUNK_SIZE]
            creator_rows = cursor.execute(
                """
                SELECT itemCreators.itemID AS itemID,
                       creators.lastName AS lastName,
                       creators.firstName AS firstName,
                       creators.fieldMode AS fieldMode,
                       creatorTypes.creatorType AS creatorType,
                       itemCreators.orderIndex AS orderIndex
                FROM itemCreators
                JOIN creators ON itemCreators.creatorID = creators.creatorID
                JOIN creatorTypes ON itemCreators.creatorTypeID = creatorTypes.creatorTypeID
                WHERE itemCreators.itemID IN (%s)
                ORDER BY itemCreators.itemID, itemCreators.orderIndex
            """
                % ",".join("?" for _ in chunk_ids),
                chunk_ids,
            ).fetchall()
            for creator_row in creator_rows:
                creators_by_item[creator_row["itemID"]].append(
                    {
                        "lastName": creator_row["lastName"],
                        # firstName preserved as-is: NULL stays null, not "".
                        # Single-field institutional creators (fieldMode=1) have NULL
                        # firstName; conflating them with empty-string hides the
                        # institutional case Slice 2 must render specially.
                        "firstName": creator_row["firstName"],
                        "fieldMode": creator_row["fieldMode"],
                        "creatorType": creator_row["creatorType"],
                        "orderIndex": creator_row["orderIndex"],
                    }
                )

    # ------------------------------------------------------------------
    # Pull the raw field values for surviving items, one query per field, chunked.
    # value_by_item_and_field[(itemID, fieldName)] = raw string.
    # ------------------------------------------------------------------
    value_by_item_and_field = {}
    if surviving_item_id_list:
        for corpus_field_name in corpus_field_names:
            field_id = field_id_by_name.get(corpus_field_name)
            if field_id is None:
                # Field not present in this install's schema at all; every item
                # will emit null for it. Recorded, not fatal.
                continue
            for chunk_start in range(0, len(surviving_item_id_list), CHUNK_SIZE):
                chunk_ids = surviving_item_id_list[
                    chunk_start : chunk_start + CHUNK_SIZE
                ]
                data_rows = cursor.execute(
                    """
                    SELECT itemData.itemID AS itemID, itemDataValues.value AS value
                    FROM itemData
                    JOIN itemDataValues ON itemData.valueID = itemDataValues.valueID
                    WHERE itemData.fieldID = ?
                      AND itemData.itemID IN (%s)
                """
                    % ",".join("?" for _ in chunk_ids),
                    (field_id,) + tuple(chunk_ids),
                ).fetchall()
                for data_row in data_rows:
                    value_by_item_and_field[(data_row["itemID"], corpus_field_name)] = (
                        data_row["value"]
                    )

    # ------------------------------------------------------------------
    # Assemble records. Headline sanity metrics accumulated as we go.
    # ------------------------------------------------------------------
    empty_author_component_count = 0
    empty_title_component_count = 0
    non_ascii_author_count = 0
    exact_duplicate_finding_count = 0  # dedup deferred; we only COUNT exact dups.
    seen_record_fingerprints = set()

    assembled_records = []
    for item_row in surviving_item_rows:
        item_id = item_row["itemID"]
        item_creators = creators_by_item.get(item_id, [])

        # First AUTHOR specifically (not first creator): editors must not count as
        # the author component. The regime detector in Slice 4 needs author-vs-
        # editor kept distinct, so we surface both the full ordered creator list
        # (all roles) and a convenience first-author lastName for the empty-author
        # metric only.
        first_author_last_name = None
        for creator in item_creators:  # already ordered by orderIndex
            if creator["creatorType"] == "author":
                first_author_last_name = creator["lastName"]
                break
        if not first_author_last_name:
            empty_author_component_count += 1

        title_value = value_by_item_and_field.get((item_id, "title"))
        if not title_value:
            empty_title_component_count += 1

        # Non-ASCII author: any author whose lastName changes under ASCII fold.
        for creator in item_creators:
            if creator["creatorType"] != "author":
                continue
            last_name = creator["lastName"]
            if last_name is not None and fold_to_ascii(last_name) != last_name:
                non_ascii_author_count += 1
                break

        record = {
            "itemID": item_id,
            "itemType": item_row["itemType"],
            "zoteroKey": item_row["zoteroKey"],
            "dateAdded": item_row["dateAdded"],
            "creators": item_creators,
        }
        for corpus_field_name in corpus_field_names:
            record[corpus_field_name] = value_by_item_and_field.get(
                (item_id, corpus_field_name)
            )

        # Exact-duplicate detection (COUNT only; dedup deferred). Fingerprint on
        # the bibliographic content, not itemID, so genuine dup content is visible.
        fingerprint = json.dumps(
            {k: record[k] for k in record if k != "itemID"},
            sort_keys=True,
            ensure_ascii=True,
        )
        if fingerprint in seen_record_fingerprints:
            exact_duplicate_finding_count += 1
        else:
            seen_record_fingerprints.add(fingerprint)

        assembled_records.append(record)

    connection.close()

    # ------------------------------------------------------------------
    # Probe mode (Stage D gate): print the probe records and STOP. No corpus is
    # written until the human confirms the sample matches the Zotero UI.
    # ------------------------------------------------------------------
    if PROBE_ITEM_IDS:
        # Report the fate of EVERY probe id, not just the ones that printed. A
        # silent miss (probe id filtered out as attachment/note/trashed, or a
        # typo'd id that does not exist) previously looked identical to a clean
        # run, defeating the hand-check gate: you would think you validated N
        # items and actually saw fewer. Now each id is accounted for explicitly.
        assembled_by_item_id = {
            record["itemID"]: record for record in assembled_records
        }
        printed_item_ids = []
        missing_item_ids = []
        for probe_item_id in PROBE_ITEM_IDS:
            if probe_item_id in assembled_by_item_id:
                printed_item_ids.append(probe_item_id)
            else:
                missing_item_ids.append(probe_item_id)

        print(
            "== PROBE MODE: %d requested, %d found, %d MISSING; corpus NOT written =="
            % (len(PROBE_ITEM_IDS), len(printed_item_ids), len(missing_item_ids))
        )
        if missing_item_ids:
            # A miss is not necessarily an error: an id may be an attachment/note/
            # trashed row deliberately filtered out. But it MUST be surfaced so the
            # human can tell "correctly filtered" from "typo'd id" from "extraction
            # dropped a real item". The human decides; the gate does not guess.
            print(
                "MISSING probe itemIDs (filtered out, or do not exist): %s"
                % missing_item_ids
            )
        for probe_item_id in printed_item_ids:
            print(
                json.dumps(
                    assembled_by_item_id[probe_item_id],
                    sort_keys=True,
                    ensure_ascii=False,
                    indent=2,
                )
            )
        print("== end probe. Clear PROBE_ITEM_IDS to run the bulk extraction. ==")
        return

    # ------------------------------------------------------------------
    # Write the deterministic JSONL corpus. sort_keys=True + ORDER BY itemID rows
    # + ORDER BY orderIndex creators => byte-reproducible. ensure_ascii=True so the
    # on-disk bytes (and thus the sha256) are stable regardless of locale.
    # ------------------------------------------------------------------
    hasher = hashlib.sha256()
    corpus_row_count = 0
    with open(
        arguments.corpus_output_path, "w", encoding="utf-8", newline="\n"
    ) as corpus_file:
        for record in assembled_records:
            line = json.dumps(record, sort_keys=True, ensure_ascii=True)
            corpus_file.write(line)
            corpus_file.write("\n")
            hasher.update(line.encode("ascii"))
            hasher.update(b"\n")
            corpus_row_count += 1

    corpus_sha256_full = hasher.hexdigest()
    corpus_size_bytes = os.path.getsize(arguments.corpus_output_path)

    # ------------------------------------------------------------------
    # Sidecar integrity manifest. The next slice's gate recomputes the corpus
    # sha256 and compares to this file (integrity plan option 1). It also records
    # the frozen snapshot identity the corpus derives from, so a silent
    # regeneration against a different snapshot is caught. No wall-clock field:
    # the manifest is a pure function of the corpus + snapshot identity.
    # ------------------------------------------------------------------
    corpus_manifest = {
        "corpus_schema": "citation-key-collision/corpus/v1",
        "corpus_path": os.path.abspath(arguments.corpus_output_path),
        "corpus_row_count": corpus_row_count,
        "corpus_size_bytes": corpus_size_bytes,
        "corpus_sha256_full": corpus_sha256_full,
        "corpus_sha256_first12": corpus_sha256_full[:12],
        "frozen_snapshot_size_bytes": arguments.frozen_snapshot_size_bytes,
        "frozen_snapshot_mtime_epoch_utc": arguments.frozen_snapshot_mtime_epoch_utc,
        "funnel_raw_items_in_library": raw_item_count,
        "funnel_non_bibliographic_removed": non_biblio_count,
        "funnel_trashed_removed": trashed_count,
        "funnel_after_type_and_trash": after_type_and_trash_count,
        "funnel_exact_duplicate_records_found": exact_duplicate_finding_count,
        "metric_empty_author_component_count": empty_author_component_count,
        "metric_empty_title_component_count": empty_title_component_count,
        "metric_non_ascii_author_count": non_ascii_author_count,
        "distinct_library_ids": distinct_library_ids,
        "library_extracted": library_filter_id,
    }
    corpus_manifest_path = arguments.corpus_output_path + ".manifest.json"
    with open(
        corpus_manifest_path, "w", encoding="utf-8", newline="\n"
    ) as manifest_file:
        json.dump(corpus_manifest, manifest_file, sort_keys=True, indent=2)
        manifest_file.write("\n")

    # ------------------------------------------------------------------
    # Print the funnel and headline numbers for the carry-forward.
    # ------------------------------------------------------------------
    print("== funnel ==")
    print("raw_items_in_library=%d" % raw_item_count)
    print("non_bibliographic_removed=%d" % non_biblio_count)
    print("trashed_removed=%d" % trashed_count)
    print("after_type_and_trash=%d" % after_type_and_trash_count)
    print(
        "exact_duplicate_records_found=%d (dedup deferred; count only)"
        % exact_duplicate_finding_count
    )
    print("== headline metrics ==")
    print("empty_author_component_count=%d" % empty_author_component_count)
    print("empty_title_component_count=%d" % empty_title_component_count)
    print("non_ascii_author_count=%d" % non_ascii_author_count)
    print("== corpus identity ==")
    print("corpus_row_count=%d" % corpus_row_count)
    print("corpus_size_bytes=%d" % corpus_size_bytes)
    print("corpus_sha256_first12=%s" % corpus_sha256_full[:12])
    print("corpus_path=%s" % os.path.abspath(arguments.corpus_output_path))
    print("corpus_manifest_path=%s" % corpus_manifest_path)


if __name__ == "__main__":
    main()
