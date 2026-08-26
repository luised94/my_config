CARRY-FORWARD v1
status: complete
thread-covered-slices: 1
next-slice: 2
snapshot-identity: zotero.sqlite frozen copy size 2981036032 bytes, mtime 1787259998 (UTC epoch); frozen (not moving)
artifacts-written:
  - path: /home/luis/zotero-experiments/corpus.jsonl
    kind: corpus
    rows-or-bytes: 61454 rows (53137445 bytes)
    checksum: 9495a84d99e0
  - path: /home/luis/zotero-experiments/corpus.jsonl.manifest.json
    kind: manifest
    rows-or-bytes: sidecar (full sha256 + funnel + metrics + frozen identity)
    checksum: n/a (regenerable sidecar; the corpus checksum above is the gate anchor)
values:
  corpus-row-count: 61454
  funnel-raw-items-in-library: 189504
  funnel-non-bibliographic-removed: 128049
  funnel-trashed-removed: 1
  funnel-after-type-and-trash: 61454
  funnel-exact-duplicates-found: 0
  empty-author-component-count: 2697
  empty-author-rate: 0.0439
  empty-title-component-count: 14
  empty-title-rate: 0.00023
  non-ascii-author-count: 4397
  non-ascii-author-rate: 0.0715
  distinct-library-ids: 1
  bbt-keys-location: native citationKey field (better-bibtex.sqlite absent)
surprises:
  68% of raw rows (128049 of 189504) are attachment/note/annotation, not bibliographic -- explains the 2.98 GB DB size; file size is a useless sanity anchor, use row counts
  empty-author 4.4% is benign: diagnostic split it into 2506 editor-only volumes + 190 other-creator + only 1 NO-creator-at-all (a webpage, legitimately creatorless); the 151 videoRecordings are director-keyed (editor/contributor role, correct)
  better-bibtex.sqlite absent -- confirms the human's hunch that BBT folded keys into Zotero's native citation-key field; Slice 2 parity target is the native field / a BBT export, NOT the BBT sqlite
  only 1 trashed item in a 60k library (plausible if trash is emptied regularly; not chased)
assumptions-next-slice-rests-on:
  corpus.jsonl and its sidecar exist at the recorded paths with the recorded checksum/row-count (Slice 2 gate recomputes and compares before trusting contents)
  raw date strings are preserved unparsed (e.g. "1995-00-00 1995", "1966-00-00 1966") -- Slice 2's year parser is built against these, not against clean years
  the frozen snapshot (2981036032 / 1787259998) is the source of truth; no re-copy between slices unless Slice 5's live re-validation
  native citationKey field holds BBT keys; sample: Shankar1995basic, Emblen1966peter
open-decisions-still-owed:
  copy BBT skipword/fold lists verbatim for parity -> Slice 2
  produce one BBT export of the corpus items as parity ground truth -> Slice 2
  (further open items unchanged; see the plan's open-decisions ledger and DECISIONS.md)
halt-reason:
  none
