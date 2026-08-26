# Read-only diagnostic for the empty-author-component tripwire. Answers ONE
# question: are the items with no author component legitimately editor-only (an
# edited volume has editors, not authors -- benign) or do some have NO creators
# at all / an extraction gap (a real problem)? Reads the frozen cold copy, writes
# nothing, runs a handful of queries. Not a deliverable; a one-off check.
#
# Scope guard: this does not re-extract, does not touch the corpus, does not
# change any strategy. It classifies the 2697 flagged items and stops.

import sqlite3
import collections
import os

# Same constant as the extractor: one frozen copy at one path (see the extractor's
# override heuristic). Edited in place, not passed as an argument.
COLD_COPY_PATH = os.path.expanduser("~/zotero-experiments/zotero.sqlite")

connection = sqlite3.connect("file:%s?immutable=1" % COLD_COPY_PATH, uri=True)
connection.row_factory = sqlite3.Row
cursor = connection.cursor()

# Same filter as the extractor: real bibliographic items in the single library,
# excluding attachment/note/annotation and trashed. Then, of those, the ones with
# NO author-role creator -- exactly the empty-author-component set.
NON_BIBLIOGRAPHIC_ITEM_TYPE_NAMES = ("attachment", "note", "annotation")

library_id_rows = cursor.execute(
    "SELECT DISTINCT libraryID FROM items ORDER BY libraryID"
).fetchall()
library_filter_id = library_id_rows[0]["libraryID"]

surviving_rows = cursor.execute(
    """
    SELECT items.itemID AS itemID, itemTypes.typeName AS itemType
    FROM items
    JOIN itemTypes ON items.itemTypeID = itemTypes.itemTypeID
    WHERE items.libraryID = ?
      AND itemTypes.typeName NOT IN (%s)
      AND items.itemID NOT IN (SELECT itemID FROM deletedItems)
"""
    % ",".join("?" for _ in NON_BIBLIOGRAPHIC_ITEM_TYPE_NAMES),
    (library_filter_id,) + NON_BIBLIOGRAPHIC_ITEM_TYPE_NAMES,
).fetchall()

surviving_item_type_by_id = {row["itemID"]: row["itemType"] for row in surviving_rows}
surviving_ids = set(surviving_item_type_by_id.keys())

# For every surviving item, gather its creator roles. Chunked IN-lists.
has_author = set()
has_editor = set()
has_any_creator = set()
surviving_id_list = sorted(surviving_ids)
CHUNK = 500
for start in range(0, len(surviving_id_list), CHUNK):
    chunk = surviving_id_list[start : start + CHUNK]
    rows = cursor.execute(
        """
        SELECT itemCreators.itemID AS itemID, creatorTypes.creatorType AS creatorType
        FROM itemCreators
        JOIN creatorTypes ON itemCreators.creatorTypeID = creatorTypes.creatorTypeID
        WHERE itemCreators.itemID IN (%s)
    """
        % ",".join("?" for _ in chunk),
        chunk,
    ).fetchall()
    for row in rows:
        has_any_creator.add(row["itemID"])
        if row["creatorType"] == "author":
            has_author.add(row["itemID"])
        elif row["creatorType"] == "editor":
            has_editor.add(row["itemID"])

connection.close()

# The empty-author set: surviving items with no author-role creator.
empty_author_ids = surviving_ids - has_author
print(
    "empty_author_total=%d (of %d surviving items)"
    % (len(empty_author_ids), len(surviving_ids))
)

# Classify each empty-author item into one of three buckets that map to a verdict.
editor_only_count = 0  # has an editor, no author -> benign edited volume
other_creator_no_author_count = (
    0  # has some creator (contributor etc.) but no author/editor
)
no_creator_at_all_count = 0  # has NO creator row at all -> the real concern
type_counter = collections.Counter()
no_creator_type_counter = collections.Counter()

for item_id in empty_author_ids:
    item_type = surviving_item_type_by_id[item_id]
    type_counter[item_type] += 1
    if item_id not in has_any_creator:
        no_creator_at_all_count += 1
        no_creator_type_counter[item_type] += 1
    elif item_id in has_editor:
        editor_only_count += 1
    else:
        other_creator_no_author_count += 1

print("")
print("=== verdict buckets ===")
print("editor_only (benign edited volumes): %d" % editor_only_count)
print("other_creator_but_no_author:         %d" % other_creator_no_author_count)
print("NO_creator_at_all (investigate):     %d" % no_creator_at_all_count)
print("")
print("=== empty-author items by itemType (all buckets) ===")
for item_type, count in type_counter.most_common():
    print("  %-20s %d" % (item_type, count))
print("")
print("=== the NO-creator-at-all items, by itemType (this is the tripwire) ===")
if no_creator_type_counter:
    for item_type, count in no_creator_type_counter.most_common():
        print("  %-20s %d" % (item_type, count))
else:
    print("  (none)")
