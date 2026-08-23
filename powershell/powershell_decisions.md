# Archive-DropboxTree.ps1 - Decision Records

Durable rationale for choices that were debated and settled, so they are not
relitigated. Each entry: the context, what was considered, the probes/signals
that would change the decision, and the call.

---

## Copy-time feedback: rejected the live heartbeat, chose a pre-copy note

### Context
robocopy is invoked with `/NP /NFL /NDL` and piped to `Out-Null`, so it runs
completely silent. A recursive batch (e.g. `add_to_zotero`, 26 GB, thousands of
small files) copies for several minutes on an external HDD with no output. This
reads as a stall even though the copy is progressing normally. Question raised:
add a live progress "heartbeat" (percent / GB copied) during the copy?

### What was considered
Three options:
1. Heartbeat: run robocopy non-blocking (Start-Process -PassThru), poll the
   destination folder size every few seconds, print GB-copied and percent against
   the member's known size.
2. Native robocopy progress: remove `/NFL /NDL /NP`, let robocopy print its own
   per-file progress.
3. Pre-copy note only: keep robocopy silent, print one line before it starts
   saying the copy will take minutes and produce no output until done.

### Why the heartbeat was rejected (adversarial findings)
- Exit-code integrity (the failure that matters most): the current
  `robocopy | Out-Null; $LASTEXITCODE` form surfaces launch failures via the
  Stop-preference throw and reads robocopy's real exit code. The heartbeat needs
  `Start-Process -PassThru` and `.ExitCode`. If Start-Process fails to launch,
  `.ExitCode` can be `$null`, and `$null -ge 8` is `$false` in PowerShell -- a
  launch failure would be read as SUCCESS. The heartbeat introduces a new silent
  failure path in the one place (the copy) where a missed failure is worst.
- Output redirection: Start-Process cannot pipe to Out-Null; it needs
  -RedirectStandardOutput/-Error to temp files (and cannot send both to the same
  file). That is two temp files per member to create, clean up, and potentially
  leak on an interrupted run.
- Wrong numbers on resume: polling destination size counts data already there
  from prior runs, so percent is wrong from the first tick unless a pre-copy
  baseline size is measured -- another recursive HDD enumerate, more code.
- Self-defeating I/O: each heartbeat recursively enumerates the destination while
  robocopy writes to it. On an HDD the head-seek contention measurably slows the
  copy. The feature meant to reduce the "feels slow" feeling makes it slower.
- Lumpy signal: many-small-file batches (zotero) grow in fits, so percent jumps
  (0,0,0,18,40) rather than climbing smoothly.

### Scoring
| Option | Liveness | Risk to copy correctness | Code | Log noise | Slows copy |
|---|---|---|---|---|---|
| Heartbeat | High (real GB/%) | Medium-high (null-exit hole, temp files, resume baseline) | ~25-30 lines | Low | Yes, slightly |
| Native | Medium (alive, names) | None | 0 | Very high | No |
| Pre-copy note | Low (one line then silence) | None | ~3 lines | None | No |

### Decision
Pre-copy note. The heartbeat's only benefit is a live percent during a 3-5 minute
copy, but the run pauses for manual dehydration after every batch, so the operator
is present and not relying on mid-copy progress. The costs (new silent-failure
path in the copy, self-inflicted slowdown, resume-baseline complexity, most code
in the riskiest location) outweigh that benefit. The note reframes silence as
expected, which addresses ~80% of the actual problem (silence read as stall) at
near-zero risk. The copy call itself was left byte-for-byte unchanged.

### Signals that would REOPEN this
- The script is run unattended / batched so no operator is present during copies,
  making mid-copy liveness actually valuable.
- A copy is observed to genuinely hang (not just be slow) and needs live
  distinction between "progressing" and "stuck".
- robocopy is replaced by a copier that streams a clean machine-readable progress
  line, removing the log-noise vs liveness tradeoff.
If reopened, the heartbeat MUST: guard `.ExitCode -eq $null` as failure; measure a
pre-copy destination baseline and subtract it; use an interval large enough that
dest-size polling does not contend with the copy (>= 10s); and be tested for the
launch-failure case explicitly.

---

## Per-batch dehydration: direct-files-only batches count and dehydrate only loose files

### Context
Two bugs, same root cause: measurements over a `direct-files-only` batch member
enumerated the whole subtree (AllDirectories) when robocopy only copied the loose
files directly in the folder (/LEV:1). Consequences: (1) the C: guard measured the
entire 711 GB tree for a near-empty batch and refused it immediately; (2) the
dehydrate poll counted the whole tree, never reached zero, and hung until the
15-min timeout; (3) the instruction told the operator to "Make online-only" on the
folder itself -- which would dehydrate the entire tree, including data other
batches had not yet archived.

### Decision
All local-file counting is mode-aware via a `-DirectFilesOnly` switch on
Get-LocalFileCount (TopDirectoryOnly vs AllDirectories). The C: guard sums only
direct files for direct-files mode. The pause names the exact loose files to select
and explicitly warns NOT to dehydrate the folder or subfolders; it does not offer a
one-click folder dehydrate for this mode. The poll completes when those loose files
dehydrate.

### Signals that would REOPEN this
- Dropbox exposes a reliable scriptable dehydrate, removing the manual click and
  its footgun entirely.
- A direct-files batch is found with so many loose files that naming them all is
  unusable; then reconsider skipping the pause for tiny direct-files batches
  (keyed on CopyMode, not a size threshold).

---

## Performance: deferred robocopy /MT threading, pending timing data

### Context
Copies feel slow, especially many-small-file batches (zotero). Question: hydrate a
whole batch first then robocopy, or request all files from Dropbox "in one go"?

### Findings
- There is NO separate hydration step to reorder. The only content read that
  triggers Dropbox download is robocopy itself, file by file. "Hydrate then copy"
  is already collapsed into robocopy's walk.
- Dropbox exposes no batch-hydrate API here. The only hydrate trigger is content
  access, one file at a time. "Request all in one go" is not possible.
- A separate pre-hydration pass would have to trigger content reads itself, which
  violates the hydration-safety invariant and has no reliable scriptable trigger
  (same reason there is no scriptable dehydrate). It also reintroduces C: pressure
  reasoning. Rejected.
- The real lever is robocopy multithreading: the script currently does NOT pass
  /MT, so robocopy is single-threaded and serializes fetch-then-write per file.
  /MT (e.g. /MT:16) would keep many files in flight, overlapping Dropbox fetch
  latency with HDD writes -- likely most of the parallelism benefit, as one flag,
  no new logic, no invariant violation.

### Decision
DEFERRED, not implemented. Do NOT add /MT blind. First gather per-batch timing
(this commit's CSV: SizeGB, FileCount, CopySeconds, CopyMBps by CopyMode) to learn
the bottleneck. If small-file batches show much lower MB/s than large-file batches,
the copy is fetch-latency-bound and /MT should help; test /MT:8 vs 16 vs 32. If
MB/s is roughly flat across batch types, the copy is HDD-write-bound and /MT will
not help and may thrash the write head -- do not add it.

### Signals that would IMPLEMENT /MT
- CSV shows small-file (high FileCount / low SizeGB) batches at materially lower
  CopyMBps than large-file batches -> fetch-bound -> add /MT, retest MB/s.
### Signals that would keep it OFF
- CopyMBps roughly constant regardless of FileCount -> write-bound -> /MT off.
When testing /MT: it interleaves console output and is incompatible with some
logging flags; on a spinning HDD cap threads modestly (8-32, not 128) to avoid
seek thrashing.

---

## Timing CSV: known limitation, label quoting

The timing log wraps Label in double quotes but does not fully CSV-escape it. A
folder name containing a comma or a double quote would break that row. Labels come
from real folder leaf names, so this is possible but low-impact: the log is
diagnostic, not part of the archive's integrity, and a broken row loses only one
batch's timing. Full CSV escaping was judged not worth the code for a diagnostic
artifact. Revisit only if a real folder name breaks parsing and the timing data
matters enough to need every row.

---

## Dehydration no-progress detector (stuck at a tiny remainder)

### Context
Observed: a batch flipped 3946 -> 1 files online-only in seconds, then sat at "1 of
3946 still local" until the 15-minute timeout. The disk was idle; the loop was
correctly re-counting a number that would never reach zero.

### Cause
Dropbox will not dehydrate a file it considers not fully uploaded, or one that is
locked/open (indexer, antivirus, an open handle). Its recall bit never flips, so
the poll's still-local count sticks at that file forever. Waiting out the full
timeout for it is pointless.

### Decision
Added a no-progress detector: if the still-local count has not decreased for
NoProgressPollsBeforePrompt polls (6 x 5s = ~30s) AND the remainder is at or below
CloseEnoughFileCount (5), prompt immediately instead of waiting the full timeout.
The hard timeout is KEPT for the flat-at-a-large-remainder case (Dropbox not
dehydrating at all), so that genuinely-wrong situation is still noticed, not
silently skipped. Prompt (not auto-continue) per the user's preference that a skip
stay a deliberate choice; choosing 'wait' resets both the flat counter and the
timeout window for a fresh budget.

### Tuning signals
- If the ~30s wait still feels long and a stuck remainder of 1-5 is always benign,
  lower NoProgressPollsBeforePrompt. If it ever prompts on a batch that was still
  legitimately progressing (count decreasing slowly), raise it.
- CloseEnoughFileCount is the "a few files won't dehydrate is fine" threshold; keep
  it small so a large stuck remainder still waits for the real timeout.

---

## Batch-attention notification (non-blocking tray balloon)

### Context
The run pauses for a manual "Make online-only" after every batch. The user wants to
work in another window and be notified when a batch needs attention, without the
notification gating the run.

### Decision
A single reusable System.Windows.Forms.NotifyIcon (created once before the loop,
disposed once after) shows an auto-dismissing tray balloon plus a console beep at
the "Make online-only" step. It does NOT gate the run -- the console Read-Host
remains the real continue gate. Everything is best-effort and wrapped: if the
assembly cannot load the icon stays $null and the balloon block no-ops; if Focus
Assist / Do Not Disturb suppresses the balloon, the beep still fires.

### Rejected alternative
A blocking MessageBox.Show was rejected: it would gate continuation, the opposite
of "show up, stay a few seconds, leave" and of letting the user work while waiting.

### Known limitation
If the run is stopped by closing the window (invited at "SAFE TO STOP") or exits via
a guard/copy-failure exit, the after-loop Dispose does not run and the tray icon
lingers until hovered (Windows clears orphaned tray icons on hover / shell
restart). Guaranteeing disposal would need a try/finally around all of Stage 4, a
larger structural change than this cosmetic aid warrants. Revisit only if lingering
icons become a real annoyance.
