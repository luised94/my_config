# Thread 4 Handoff: Annotation Export

Status: EXPLORATORY (no design commitments before spike S5)
Reads: MAINTENANCE_PLAN.md (S5), CONVENTIONS.md (A2-A8, B3, B4)

## Objective

Export Zotero annotations, and connect/write annotations into the PDF
files themselves. Motivating observation from the owner: exported PDFs
appear to carry the Zotero item id, which suggests a linkage that can
be exploited for round-tripping or external processing.

## Why exploratory

The annotation data model, the export pathways, and the id-embedding
behavior are all unverified assumptions. This thread starts with spike
S5 and only then scopes deliverables. Do not draft implementation
before Verified facts below are populated.

## Spike S5 (interactive; paste results back)

On a handful of annotated PDFs (highlights, notes, ink if present):

- What do the annotation APIs expose? (attachment.getAnnotations(),
  annotation item fields: type, text, comment, color, position, tags,
  dateModified, key.)
- Zotero's "export PDF with annotations" pathway: what tool does it use
  internally, and does the produced PDF embed the Zotero item key or
  any identifier? Inspect the raw PDF for evidence.
- Are annotations stored only in the database (default for Zotero 7
  PDF reader) vs embedded in the file? Implications for backup and for
  external readers.
- What write pathways exist for embedding annotations into a PDF file
  (Zotero internal export function callable from console JS? external
  tool needed?).
- How does Better Notes interact with annotations (templates already
  pull item fields; do they pull annotations?).
- Do citation keys (BBT) offer a stabler external identifier than item
  keys for filenames/links?

## Candidate shapes (to evaluate after S5, not commitments)

- C1: console export script producing per-item annotation files
  (markdown or JSON) named by citation key, written to a configured
  folder; batched with full scale treatment if run library-wide.
- C2: "burn annotations into PDF" pathway -- either invoking Zotero's
  own export-with-annotations from script, or emitting a work list for
  an external PS1/tool step (consistent with the detection/destruction
  separation: script reports, separate tool writes files).
- C3: Better Notes template additions that render annotations into
  notes (may already partially exist; check templates).

## Open questions

- OQ1: primary purpose -- backup of annotations, external reading of
  annotated PDFs, or feeding a notes workflow? Ranking drives the shape.
- OQ2: identifier convention: item key vs citation key (ties to B3).
- OQ3: incremental export (only changed annotations since last run)?
  Reuse the state-file pattern from bbt_export.js if so.
- OQ4: scope -- PDFs only, or epub/html annotations too?

## Acceptance criteria (provisional; refine after S5)

- Verified facts section populated with version-stamped findings.
- Chosen shape documented here with rationale before implementation.
- Any library-wide run obeys CONVENTIONS A5 scale patterns and A4
  safety defaults (report/dry-run first).

## Verified facts (populated by spike)

(empty -- fill with S5 findings, stamped with Zotero/BBT/Better Notes
versions)
