# Decisions ledger

Closed decisions for the citation-key-collision experiment. Each entry retires an
item from the plan's open-decisions ledger. Format: the decision, the one-line
rationale, and which slice it binds. This file is durable and experiment-specific;
permanent cross-slice coding rules live in the plan's Working-style constraints
section, not here. Ephemeral per-thread state lives in the carry-forward notes.

## Resolved in Slice 0 (environment prologue)

- Repo working directory: `~/personal_repos/my_config/zotero/experiments/citation-key-collision`.
  Rationale: the human's existing config repo; recorded in environment_manifest.primary.json. Binds: all slices.
- Zotero data directory: `C:\Users\Luised94\Zotero` (default location, resolved via
  `$env:USERPROFILE` on-device, never hardcoded). Rationale: default confirmed
  present; device-independent resolution supports the two-device design. Binds: Slice 1, Slice 5.
- Copy mechanism: PowerShell-from-WSL cold copy. Rationale: the cross-boundary call
  was probed working in Slice 0 (powershell.exe reachable, returns output);
  manual-copy fallback not needed. Binds: Slice 1, Slice 5.

## Resolved in Slice 1 (extraction)

- Corpus format: JSONL. Rationale: author lists are variable-length and titles carry
  commas/newlines that break naive CSV; one object per line stays diffable. Binds: Slice 1+.
- Snapshot discipline: frozen. Rationale: copy zotero.sqlite once and freeze it;
  reproducibility requires a fixed source so the corpus checksum is meaningful and
  every later gate reconciles against one snapshot identity. Binds: all slices.
  Frozen identity: size 2981036032 bytes, mtime 1787259998 (UTC epoch).
- Corpus not committed to git. Rationale: the ~2.98 GB DB copy and ~53 MB corpus are
  regenerable artifacts; integrity is guaranteed by a recomputable sha256 in a
  sidecar manifest, not by versioning the bytes. Binds: Slice 1+.
- Integrity mechanism: deterministic extractor + sidecar manifest. Rationale: the
  extractor is a pure function of the frozen snapshot (rows ORDER BY itemID,
  creators ORDER BY orderIndex, JSON sort_keys, ensure_ascii), so re-running yields
  byte-identical output; the sidecar records full sha256 + row count + frozen
  identity for the next slice's gate to recompute. Binds: Slice 2+ gates.
- Multiple-library handling: halt, via in-script toggle HALT_ON_MULTIPLE_LIBRARIES.
  Rationale: a second library violates a stated assumption and must be surfaced, not
  guessed around; toggle flips to single-library extraction without argument parsing.
  Binds: Slice 1. Observed: 1 library (libraryID 1), so the halt did not fire.
- Deduplication: deferred. Rationale: exact-duplicate records are counted and
  reported as a funnel finding, never silently collapsed; type/trash filters only.
  Binds: Slice 1. Observed: 0 exact duplicates.
- Live-DB script re-validation (read-only): folded into Slice 5 as a labeled
  sub-step. Rationale: it is a read-only capstone that reuses the Slice 1 extraction
  verbatim; Slice 5 is the synthesis/wrap slice; it does not cross the write-back
  scope boundary and does not weaken the frozen-snapshot guarantee (the frozen copy
  stays the source of truth; the live run is a separate, labeled comparison). Binds: Slice 5.

## Facts established in Slice 1 that bind later slices

- BBT citation keys live in Zotero's NATIVE citation-key field, not in
  better-bibtex.sqlite (which is absent on this install). Consequence: Slice 2's
  parity ground truth is the native `citationKey` field (or a BBT export), not the
  BBT sqlite. Sample observed: `Shankar1995basic`, `Emblen1966peter`. Binds: Slice 2.
- WAL was checkpointed on Zotero exit (no -wal file at copy time), so the
  single-file cold copy is consistent without needing sidecar replay. Binds: Slice 5
  (the live re-copy should re-check this rather than assume it).

## Deferred / still open (see the plan's open-decisions ledger)

BBT skipword/fold-list copying (Slice 2), query models and from-memory model
(Slice 3), disproof margin and pinned-item re-keying (Slice 4), whether to open a
follow-on optimization task (Slice 5+). These remain the human's to resolve at the
slice that needs them.
