# Verified environment facts

A running ledger of host-environment behavior VERIFIED by spikes, kept
separate from any one thread's handoff because these facts are reused
across threads and must outlive the thread that discovered them. Each
entry is stamped with the version it was tested against. When a fact is
re-confirmed on a newer version, update the stamp in the same change
(mirrors the CONFIG version-ceiling rule, A3).

Scope split: a thread's handoff "Verified facts" holds that thread's
specific MEASUREMENTS (this library's counts, sizes, histograms). This
file holds reusable API/behavior facts that any future script can rely
on. When a spike produces both, the reusable subset is promoted here and
the handoff points at this file.

## Zotero console (Run JavaScript)

Tested: Zotero 9.0.6 (thread 2 spikes S1/S2, 2026-07).

- The console does NOT await a Promise returned by the pasted script.
  An async IIFE therefore prints "undefined / completed successfully"
  immediately, discards the real return value, and turns any thrown error
  into a silent unhandled rejection (output just stops). Use the window's
  "Run as async function" checkbox with top-level await instead, and wrap
  the body in try/catch that logs and rethrows. (Derived rule: A10.2.)
- Zotero.DB.queryAsync rejects an inline LIKE literal ("Please enter a
  LIKE clause with bindings"); the pattern must be a bound parameter.
  (Derived rule: A10.7.)
- Services.vc.compare(a, b) is the version comparator used in pre-flight.

## Attachments and linkMode

Tested: Zotero 9.0.6 (S1, 2026-07).

- linkMode constants: IMPORTED_FILE=0, IMPORTED_URL=1, LINKED_FILE=2,
  LINKED_URL=3, EMBEDDED_IMAGE=4.
- Where each resolves: LINKED_FILE resolves under the linked-attachment
  base directory (baseAttachmentPath pref). IMPORTED_FILE, IMPORTED_URL,
  and EMBEDDED_IMAGE all resolve into the Zotero storage/ directory.
  LINKED_URL has no file (empty path).
- item.getFilePath(): returns the INTENDED absolute path for file-backed
  attachments whether or not the file exists on disk -- it does not stat.
  Returns false for LINKED_URL. Use it to learn where a file SHOULD be.
- item.getFilePathAsync(): returns the absolute path when the file
  EXISTS, false when it is missing. This is the disk-checking variant.
- item.fileExists(): boolean for file-backed attachments; THROWS on
  LINKED_URL ("cannot be called on link attachments"). Never call it on
  linkMode 3.
- Consequence for scale: existence for a whole library is cheaper to
  derive by walking the base directory once and doing a set difference
  against getFilePath() results than by calling getFilePathAsync() /
  fileExists() per item. (Used by audit_orphan_attachments.js.)
- Relative linked-file paths are stored as "attachments:Sub/Dir/File.ext"
  when saveRelativeAttachmentPath is true; absolute path is
  baseAttachmentPath + "\" + relative-part with "/" -> "\".

## Filesystem (IOUtils / PathUtils, Windows + Dropbox)

Tested: Zotero 9.0.6; Windows + Dropbox desktop (versions TODO: owner to
stamp). (S2, S2b, 2026-07.)

- IOUtils.getChildren(dir) returns a full array of child paths PER
  DIRECTORY (buffered, not streamed). Per-call memory is bounded by the
  largest directory's child count, so walk directory-by-directory and
  yield to the event loop by ENTRY count, not directory count.
- IOUtils.stat(path) reads metadata only; it does NOT read contents and
  does NOT hydrate a Dropbox online-only placeholder. Safe to stat the
  whole tree. (Spot-confirm badges after a large walk.)
- Throughput on a cold walk of a ~78k-file Dropbox tree: high early
  (~3.5-4.5k entries/s), settling to ~1.3k/s partway through (NTFS /
  cloud-filter metadata cost). Budget accordingly.
- Move-Item within the same NTFS volume (and inside the Dropbox root) is
  a rename: it preserves a Dropbox online-only placeholder exactly (raw
  attributes, RecallOnDataAccess bit, LastWriteTime, length all
  unchanged) -- no hydration, no corruption. A cross-volume Move-Item
  degrades to copy+delete and hydrates; robocopy /MOV copies-then-deletes
  even same-volume and hydrates. Use plain Move-Item and enforce
  same-volume containment for placeholder-safe moves.
- attrib +U (Cloud Filter "free up space") as a dehydration trigger:
  UNTESTED on a hydrated file (the S2b probe target was already
  dehydrated). Do not rely on it without a fresh spike.
