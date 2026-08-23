<#
Archive-DropboxTree.ps1

Archives a Dropbox tree (mostly online-only placeholders) to an external drive,
one size-bounded batch at a time, pausing after each batch for a MANUAL Dropbox
"Make online-only" to reclaim C: space before the next batch.

USAGE:
  # Dot-source / run from PowerShell (adjust the path to where the file lives):
  #   . "\\wsl.localhost\Ubuntu-22.04\home\luis\personal_repos\my_config\powershell\Archive-DropboxTree.ps1"

  # Dry run -- walk the tree, print the batch plan, copy nothing:
  .\Archive-DropboxTree.ps1 -WindowsUser Luised94 -DestinationRoot "E:\"

  # Real archive -- copy each batch to the HDD, pausing for manual dehydrate:
  .\Archive-DropboxTree.ps1 -WindowsUser Luised94 -DestinationRoot "E:\" -Execute

  # Resume (same command) -- completed batches fast-forward:
  .\Archive-DropboxTree.ps1 -WindowsUser Luised94 -DestinationRoot "E:\" -Execute

PARAMETERS:
  -WindowsUser        Windows account under C:\Users. Required. (On this machine
                      it has been seen as both 'Luised94' and 'liusm' -- pass the
                      one that matches C:\Users on the device you are running on.)
  -DropboxAccountName Dropbox account folder. Default "Luis Martinez".
  -DestinationRoot    Root of the external drive (e.g. "E:\"). Required for real
                      runs. The tree is copied under <DestinationRoot>\<account>.
  -BatchSizeLimitGB   Max GB per batch. Default 50. See balance note below.
  -CFreeFloorGB       Minimum C: free space (GB) that must remain after a member is
                      hydrated. Default 15. Before each copy, a member whose size
                      would drive C: below this floor is refused and the run stops
                      with a hint, rather than filling C: mid-copy. See note below.
  -Execute            Perform real hydration/copy and the dehydrate pauses. Without
                      it, the script only prints the plan (no copy, no hydration).
  -MaxRecursionDepth  Safety cap on how deep the batch walk descends into
                      over-limit folders. Default 8. If a folder is still over the
                      limit at this depth, it is emitted as one over-limit batch
                      with a warning rather than descending further.
  -Help               Print this help and exit.

WHY IT WORKS THIS WAY (the constraints we verified by testing, not assumption):
  - C: has far less free space (~72 GB) than the archive (~680 GB), so the whole
    tree cannot be hydrated at once. Files are copied in batches sized to fit C:.
  - Hydrated files DO NOT re-dehydrate on their own (verified: 0% reclaimed after
    90s), so each batch's source must be dehydrated between batches or C: fills.
  - Dropbox has NO scriptable dehydrate; the attribute approach does nothing
    (verified: 'attrib +U -P' reclaimed 0 GB). The only reliable dehydrate is the
    right-click "Make online-only". So the archive pauses for that one click and
    then WATCHES the files flip to online-only via their placeholder flag before
    continuing -- no free-space guessing.

WHAT THE BATCH LIMIT BALANCES (why 50 GB is the default):
  Bigger batches  -> fewer manual dehydrate pauses (fewer clicks), but less C:
                     free-space slack and more hydrated data at risk if you stop
                     mid-batch.
  Smaller batches -> more clicks, but more slack and less exposure per batch.
  Pick a limit so that a batch plus Windows overhead never drops C: below the
  -CFreeFloorGB floor. The per-member guard enforces the floor at copy time even
  if the batch plan alone would not, but a limit chosen with the floor in mind
  means fewer refusals mid-run. Note a "direct files" batch is a single member
  that cannot be split by lowering -BatchSizeLimitGB; if one is large it must fit
  under the floor on its own or be split by hand.

RESUME: safe to stop between batches and re-run. Robocopy skips files already on
  the HDD, so completed batches fast-forward; a source already online-only is not
  re-hydrated. No state file -- the filesystem itself is the state.

HYDRATION-SAFETY INVARIANT (do not break):
  Only the COPY step (robocopy) may hydrate. All measurement/enumeration reads
  FileInfo.Length and attributes only, which are placeholder metadata and do not
  download. Never add a content read to the walk/measure paths.
#>

param(
    [string]$WindowsUser = $env:MC_WINDOWS_USER,
    [string]$DropboxAccountName = "Luis Martinez",
    [string]$DestinationRoot,
    [double]$BatchSizeLimitGB = 50,
    [double]$CFreeFloorGB = 15,
    [switch]$Execute,
    [int]$MaxRecursionDepth = 8,
    [switch]$Help
)

$ErrorActionPreference = "Stop"

if ($Help) {
    Write-Host @"
Archive-DropboxTree.ps1 - batch-archive a Dropbox tree to an external drive

USAGE:
    Dry run:  .\Archive-DropboxTree.ps1 -WindowsUser <name> -DestinationRoot "E:\"
    Real run: .\Archive-DropboxTree.ps1 -WindowsUser <name> -DestinationRoot "E:\" -Execute
    Resume:   (re-run the same real-run command; done batches fast-forward)

PARAMETERS:
    -WindowsUser <name>         Windows account under C:\Users. Required.
    -DropboxAccountName <name>  Dropbox account folder. Default "Luis Martinez".
    -DestinationRoot <path>     External drive root, e.g. "E:\". Required for -Execute.
    -BatchSizeLimitGB <n>       Max GB per batch. Default 50.
    -Execute                    Do the real copy + dehydrate pauses. Omit for dry run.
    -MaxRecursionDepth <n>      Cap on descent into over-limit folders. Default 8.
    -Help                       Show this help and exit.

Between batches you will right-click the just-copied folder and choose
'Make online-only'; the script watches the files flip and continues automatically.
Safe to stop between batches and re-run to resume.
"@
    exit 0
}

$RECALL_ON_DATA_ACCESS = 0x00400000
$BatchSizeLimitBytes = [Int64]($BatchSizeLimitGB * 1GB)

# Dehydration poll cadence. The loop re-counts still-local files every interval and
# gives up automatically after the timeout, at which point the user is asked whether
# to keep waiting or skip. Named here so the loop and its warning read one source.
$DehydrationPollIntervalSeconds = 5
$DehydrationPollTimeoutSeconds = 900

# --- Stage 1: validation ---
if (-not $WindowsUser) {
    Write-Host "[ERROR] -WindowsUser is required (or set MC_WINDOWS_USER)." -ForegroundColor Red
    Write-Host "[HINT]  List candidates: Get-ChildItem C:\Users -Directory | Select Name" -ForegroundColor DarkYellow
    exit 1
}

$ArchiveSourceRoot = "C:\Users\$WindowsUser\MIT Dropbox\$DropboxAccountName"
if (-not (Test-Path -LiteralPath $ArchiveSourceRoot)) {
    Write-Host "[ERROR] Source root not found: $ArchiveSourceRoot" -ForegroundColor Red
    Write-Host "[HINT]  Check -WindowsUser and -DropboxAccountName." -ForegroundColor DarkYellow
    exit 1
}

if ($Execute -and -not $DestinationRoot) {
    Write-Host "[ERROR] -DestinationRoot is required for a real run (e.g. -DestinationRoot 'E:\')." -ForegroundColor Red
    exit 1
}
if ($DestinationRoot) {
    if (-not (Test-Path -LiteralPath $DestinationRoot)) {
        Write-Host "[ERROR] Destination root not found: $DestinationRoot" -ForegroundColor Red
        Write-Host "[HINT]  Is the external drive connected and the letter correct?" -ForegroundColor DarkYellow
        exit 1
    }
    $DestinationTreeRoot = Join-Path $DestinationRoot $DropboxAccountName
}

if (-not (Get-Command robocopy -ErrorAction SilentlyContinue)) {
    Write-Host "[ERROR] robocopy not found in PATH." -ForegroundColor Red
    exit 1
}

Write-Host "[INFO]  Source:      $ArchiveSourceRoot"
if ($DestinationRoot) { Write-Host "[INFO]  Destination: $DestinationTreeRoot" }
Write-Host ("[INFO]  Batch limit: {0} GB" -f $BatchSizeLimitGB)
Write-Host ("[INFO]  Mode:        {0}" -f $(if ($Execute) {'EXECUTE (real copy + dehydrate)'} else {'DRY RUN (plan only)'}))

# On startup, note C: free so an unexpectedly low value (from an interrupted prior
# run leaving hydrated-but-not-dehydrated files) can be surfaced as a recovery hint.
$StartupFreeGB = [math]::Round((Get-Volume -DriveLetter C).SizeRemaining/1GB, 1)
Write-Host ("[INFO]  C: free:     {0} GB" -f $StartupFreeGB)
if ($StartupFreeGB -lt ($BatchSizeLimitGB + 15)) {
    Write-Host "[WARN]  C: free is low relative to the batch limit." -ForegroundColor Yellow
    Write-Host "[HINT]  If a previous run stopped mid-batch, right-click the last folder you" -ForegroundColor DarkYellow
    Write-Host "        were archiving and choose 'Make online-only' to reclaim space first." -ForegroundColor DarkYellow
}
Write-Host ""

# --- Measurement primitive (metadata-only; never hydrates) ---
# Returns the recursive byte total of a folder from placeholder metadata. This is
# the ONLY thing the walk uses to size folders; it must not read content.
function Get-FolderSizeBytes {
    param([string]$FolderPath)
    $Total = [Int64]0
    try {
        $Enumeration = [System.IO.Directory]::EnumerateFiles(
            $FolderPath, '*', [System.IO.SearchOption]::AllDirectories)
        foreach ($FilePath in $Enumeration) {
            $Total += [Int64]([System.IO.FileInfo]::new($FilePath)).Length
        }
    } catch {
        Write-Host "[WARN]  Could not fully measure $FolderPath : $($_.Exception.Message)" -ForegroundColor Yellow
    }
    return $Total
}

# Count files still local (placeholder flag clear) in a folder. Used by the
# resume fast-path and the dehydrate pause to detect completion.
#   -DirectFilesOnly: count ONLY the loose files directly in the folder, not the
#     subtree. Required for direct-files-only batches: robocopy copied only the
#     direct files (/LEV:1), so only those were hydrated and only those will
#     dehydrate. Counting the subtree here would count thousands of unrelated
#     files elsewhere in the tree that this batch never touched, so the count
#     would never reach zero and the pause would hang until the timeout.
function Get-LocalFileCount {
    param(
        [string]$FolderPath,
        [switch]$DirectFilesOnly
    )
    $LocalCount = 0
    $SearchDepth = if ($DirectFilesOnly) {
        [System.IO.SearchOption]::TopDirectoryOnly
    } else {
        [System.IO.SearchOption]::AllDirectories
    }
    try {
        $Enumeration = [System.IO.Directory]::EnumerateFiles($FolderPath, '*', $SearchDepth)
        foreach ($FilePath in $Enumeration) {
            $Attrs = [System.IO.File]::GetAttributes($FilePath)
            if (([int]$Attrs -band $RECALL_ON_DATA_ACCESS) -eq 0) { $LocalCount++ }
        }
    } catch { }
    return $LocalCount
}

# --- Stage 2: build the batch list by recursive descent ---
# A batch is a list of member folder paths whose combined size is <= the limit,
# plus a copy mode. The rules:
#   - A folder at/under the limit becomes one whole-folder batch (recursion stops;
#     this is what prevents descending into zotero-storage's 29k tiny leaves).
#   - A folder over the limit: its direct files become one batch, and its
#     immediate subfolders are accumulated into limit-sized groups, descending
#     into any single subfolder that is itself over the limit (bounded by
#     MaxRecursionDepth).
# The batch list lives only in memory; there is no plan file. Re-running rebuilds
# it, which is cheap and cannot drift from the real tree.
$BatchList = [System.Collections.Generic.List[PSCustomObject]]::new()

# Accumulator shared across the walk. AddBatch flushes the current accumulation.
$AccumulatedMembers = [System.Collections.Generic.List[string]]::new()
$AccumulatedBytes = [Int64]0
$AccumulatedLabel = ""

function Flush-AccumulatedBatch {
    if ($script:AccumulatedMembers.Count -gt 0) {
        $script:BatchList.Add([PSCustomObject]@{
            Members  = @($script:AccumulatedMembers.ToArray())
            SizeBytes= $script:AccumulatedBytes
            CopyMode = "recursive"
            Label    = $script:AccumulatedLabel
        })
        # Clear the existing List in place rather than rebinding to a new object.
        # Rebinding only updates the script-scope name; any code that had read the
        # old reference into a local would keep mutating the flushed list. Clearing
        # keeps the single shared instance authoritative regardless of how it is read.
        $script:AccumulatedMembers.Clear()
        $script:AccumulatedBytes = [Int64]0
        $script:AccumulatedLabel = ""
    }
}

# Recursive walk. Emits batches for one folder. Depth guards the recursion.
function Add-FolderBatches {
    param(
        [string]$FolderPath,
        [int]$Depth
    )

    $FolderBytes = Get-FolderSizeBytes -FolderPath $FolderPath
    $FolderName = Split-Path $FolderPath -Leaf

    if ($FolderBytes -le $script:BatchSizeLimitBytes) {
        # Fits whole -- flush any running accumulation from siblings first so we do
        # not merge across the accumulator boundary in a confusing way, then emit.
        # (We keep whole-folder batches distinct for clear resume/labeling.)
        $script:BatchList.Add([PSCustomObject]@{
            Members  = @($FolderPath)
            SizeBytes= $FolderBytes
            CopyMode = "recursive"
            Label    = "whole: $FolderName"
        })
        return
    }

    # Over the limit and at max depth: emit as one over-limit batch with a warning.
    if ($Depth -ge $script:MaxRecursionDepth) {
        Write-Host ("[WARN]  {0} is over the limit ({1:N1} GB) at max depth {2}; emitting as a single over-limit batch." -f `
            $FolderPath, ($FolderBytes/1GB), $Depth) -ForegroundColor Yellow
        Write-Host "[HINT]  If this batch is larger than C: free space, split this folder by hand or lower -BatchSizeLimitGB." -ForegroundColor DarkYellow
        $script:BatchList.Add([PSCustomObject]@{
            Members  = @($FolderPath)
            SizeBytes= $FolderBytes
            CopyMode = "recursive"
            Label    = "OVER-LIMIT: $FolderName"
        })
        return
    }

    # Over the limit: direct files (non-recursive) become their own batch.
    $DirectFiles = Get-ChildItem -LiteralPath $FolderPath -File -Force -ErrorAction SilentlyContinue
    if ($DirectFiles.Count -gt 0) {
        $DirectBytes = [Int64]0
        foreach ($DirectFile in $DirectFiles) { $DirectBytes += [Int64]$DirectFile.Length }
        $script:BatchList.Add([PSCustomObject]@{
            Members  = @($FolderPath)
            SizeBytes= $DirectBytes
            CopyMode = "direct-files-only"
            Label    = "direct files in $FolderName"
        })
    }

    # Immediate subfolders, ordinal-sorted for deterministic order across runs.
    $Subfolders = Get-ChildItem -LiteralPath $FolderPath -Directory -Force -ErrorAction SilentlyContinue |
        Sort-Object -Property Name -Culture ''

    foreach ($Subfolder in $Subfolders) {
        $SubBytes = Get-FolderSizeBytes -FolderPath $Subfolder.FullName

        if ($SubBytes -gt $script:BatchSizeLimitBytes) {
            # Descend: flush the current accumulation, then recurse into this one.
            Flush-AccumulatedBatch
            Add-FolderBatches -FolderPath $Subfolder.FullName -Depth ($Depth + 1)
            continue
        }

        # Would adding this subfolder overflow the accumulator? Flush first.
        if (($script:AccumulatedBytes + $SubBytes) -gt $script:BatchSizeLimitBytes -and $script:AccumulatedMembers.Count -gt 0) {
            Flush-AccumulatedBatch
        }
        if ($script:AccumulatedLabel -eq "") { $script:AccumulatedLabel = "group under $FolderName" }
        $script:AccumulatedMembers.Add($Subfolder.FullName)
        $script:AccumulatedBytes += $SubBytes
    }

    # Flush the tail accumulation for this folder before returning to the parent.
    Flush-AccumulatedBatch
}

Write-Host "[INFO]  Walking the tree to build batches (metadata only; no download)..."

# Top-level: loose root files first, then each top-level folder through the walk.
$RootLooseFiles = Get-ChildItem -LiteralPath $ArchiveSourceRoot -File -Force -ErrorAction SilentlyContinue
if ($RootLooseFiles.Count -gt 0) {
    $RootLooseBytes = [Int64]0
    foreach ($LooseFile in $RootLooseFiles) { $RootLooseBytes += [Int64]$LooseFile.Length }
    $BatchList.Add([PSCustomObject]@{
        Members  = @($ArchiveSourceRoot)
        SizeBytes= $RootLooseBytes
        CopyMode = "direct-files-only"
        Label    = "root loose files"
    })
}

$TopLevelFolders = Get-ChildItem -LiteralPath $ArchiveSourceRoot -Directory -Force |
    Sort-Object -Property Name -Culture ''
foreach ($TopFolder in $TopLevelFolders) {
    Add-FolderBatches -FolderPath $TopFolder.FullName -Depth 1
}

# Number the batches after the full list exists.
$BatchIndex = 0
foreach ($Batch in $BatchList) { $BatchIndex++; $Batch | Add-Member -NotePropertyName BatchNumber -NotePropertyValue $BatchIndex }

$TotalBytes = ($BatchList | Measure-Object -Property SizeBytes -Sum).Sum
Write-Host ("[INFO]  Plan: {0} batches, {1:N2} GB total." -f $BatchList.Count, ($TotalBytes/1GB))
Write-Host ""

# --- Stage 3: print the plan (compact; one line per batch) ---
Write-Host "========== BATCH PLAN ==========" -ForegroundColor Green
foreach ($Batch in $BatchList) {
    $MemberNote = if ($Batch.Members.Count -eq 1) { "" } else { " ($($Batch.Members.Count) folders)" }
    $OverFlag = if ($Batch.SizeBytes -gt $BatchSizeLimitBytes) { " [OVER LIMIT]" } else { "" }
    Write-Host ("  [{0,3}] {1,7:N2} GB  {2}{3}{4}" -f `
        $Batch.BatchNumber, ($Batch.SizeBytes/1GB), $Batch.Label, $MemberNote, $OverFlag)
}
Write-Host ""

if (-not $Execute) {
    Write-Host "[INFO]  Dry run complete. Nothing was hydrated or copied." -ForegroundColor DarkYellow
    Write-Host "[NEXT]  Re-run with -Execute -DestinationRoot 'E:\' to perform the archive." -ForegroundColor Cyan
    exit 0
}

# --- Stage 3.5: destination confirmation gate (Execute only) ---
# The wrong-drive error is the only way this script can cause data loss on the
# destination (700 GB to a stick or the wrong disk). Test-Path alone passes for
# any existing letter, so before copying anything we show what we are about to
# write into, prove there is room for the WHOLE archive, and require an explicit
# 'yes'. Room check: dest_free + bytes_already_in_archive_subtree >= plan_total.
# That is algebraically "remaining copy fits in dest free", and stays correct on
# resume because already-copied batches are counted in the present bytes, not
# demanded again from free space. Present bytes are measured on the archive
# subtree only, so unrelated files on the drive are not counted as ours (they
# already reduced dest_free, which is what we want).
Write-Host "========== CONFIRM DESTINATION ==========" -ForegroundColor Green
Write-Host ("[INFO]  Archive will be written under: {0}" -f $DestinationTreeRoot)

$DestinationTreeExists = Test-Path -LiteralPath $DestinationTreeRoot
$DestinationPresentBytes = [Int64]0
if ($DestinationTreeExists) {
    Write-Host "[INFO]  This archive folder already exists on the destination." -ForegroundColor Yellow
    Write-Host "[INFO]  Existing top-level entries under it (no files are deleted; same-named files are overwritten):"
    $DestinationTopLevel = Get-ChildItem -LiteralPath $DestinationTreeRoot -Force -ErrorAction SilentlyContinue |
        Sort-Object -Property Name -Culture ''
    if ($DestinationTopLevel.Count -eq 0) {
        Write-Host "          (empty)"
    } else {
        foreach ($Entry in $DestinationTopLevel) {
            $EntryKind = if ($Entry.PSIsContainer) { "DIR " } else { "file" }
            Write-Host ("          [{0}] {1}" -f $EntryKind, $Entry.Name)
        }
    }
    # Bytes already present in our archive subtree (metadata-only; HDD files, no
    # Dropbox hydration involved here). Counts toward room-for-whole-archive.
    $DestinationPresentBytes = Get-FolderSizeBytes -FolderPath $DestinationTreeRoot
    Write-Host ("[INFO]  Already present in archive subtree: {0:N2} GB" -f ($DestinationPresentBytes/1GB))
} else {
    Write-Host "[INFO]  This archive folder does not exist yet; it will be created."
}

# Destination free space. Guard against a non-drive-letter destination (e.g. UNC)
# where Get-Volume -DriveLetter cannot answer; warn and skip the space math there.
$DestinationDriveLetter = $null
if ($DestinationRoot -match '^([A-Za-z]):') { $DestinationDriveLetter = $Matches[1] }

if ($DestinationDriveLetter) {
    $DestinationFreeBytes = [Int64](Get-Volume -DriveLetter $DestinationDriveLetter).SizeRemaining
    Write-Host ("[INFO]  Destination free space: {0:N2} GB on {1}:" -f ($DestinationFreeBytes/1GB), $DestinationDriveLetter)
    Write-Host ("[INFO]  Plan total to archive:  {0:N2} GB" -f ($TotalBytes/1GB))

    $RoomForWholeArchiveBytes = $DestinationFreeBytes + $DestinationPresentBytes
    if ($RoomForWholeArchiveBytes -lt $TotalBytes) {
        $ShortfallGB = ($TotalBytes - $RoomForWholeArchiveBytes) / 1GB
        Write-Host ("[ERROR] Destination cannot hold the whole archive. Short by {0:N2} GB." -f $ShortfallGB) -ForegroundColor Red
        Write-Host ("        Room for archive = free {0:N2} GB + already-present {1:N2} GB = {2:N2} GB < plan {3:N2} GB." -f `
            ($DestinationFreeBytes/1GB), ($DestinationPresentBytes/1GB), ($RoomForWholeArchiveBytes/1GB), ($TotalBytes/1GB)) -ForegroundColor Red
        Write-Host "[HINT]  Free space on the destination or use a larger drive, then re-run." -ForegroundColor DarkYellow
        exit 1
    }
    Write-Host ("[INFO]  Room check OK: free + already-present = {0:N2} GB >= plan {1:N2} GB." -f `
        ($RoomForWholeArchiveBytes/1GB), ($TotalBytes/1GB)) -ForegroundColor Green
} else {
    Write-Host "[WARN]  Destination is not a drive letter; cannot check free space automatically." -ForegroundColor Yellow
    Write-Host ("[INFO]  Plan total to archive: {0:N2} GB -- ensure the destination has room." -f ($TotalBytes/1GB)) -ForegroundColor Yellow
}

Write-Host ""
$ConfirmDestination = Read-Host "Type 'yes' to archive to the destination above, anything else to abort"
if ($ConfirmDestination -ne 'yes') {
    Write-Host "[INFO]  Aborted before copying. Nothing was hydrated or copied." -ForegroundColor DarkYellow
    exit 0
}
Write-Host ""

# --- Stage 4: execute each batch (copy -> dehydrate pause) ---
Write-Host "========== EXECUTING ARCHIVE ==========" -ForegroundColor Green
Write-Host "[INFO]  You will be asked to 'Make online-only' after each batch." -ForegroundColor Cyan
Write-Host ""

# Running total of bytes confirmed copied, for the cross-batch progress line. A
# batch is added to this AFTER its copy succeeds (not when it starts), so a guard
# refusal or robocopy failure never overstates progress. On resume, batches that
# fast-forward (already online-only) are still counted here once robocopy confirms
# them, so the progress line reflects true bytes-on-destination, not just this run.
$CumulativeCopiedBytes = [Int64]0

foreach ($Batch in $BatchList) {
    $BatchStartTimestamp = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
    Write-Host ("---------- [{0}] Batch {1}/{2}: {3} ({4:N2} GB) ----------" -f `
        $BatchStartTimestamp, $Batch.BatchNumber, $BatchList.Count, $Batch.Label, ($Batch.SizeBytes/1GB)) -ForegroundColor Cyan
    Write-Host ("           Progress: {0:N2} of {1:N2} GB copied ({2:N1}%) before this batch" -f `
        ($CumulativeCopiedBytes/1GB), ($TotalBytes/1GB), (100.0 * $CumulativeCopiedBytes / $TotalBytes))

    # Foresight line: show C: free against what this batch could hydrate and the
    # floor, BEFORE any copy starts. The per-member guard below is authoritative and
    # enforced per member; this is only a heads-up so a coming refusal is not a
    # surprise mid-batch. Batch.SizeBytes is the whole-batch total, which bounds peak
    # C: use during the copy (all members stay hydrated until the dehydrate pause),
    # so if free minus it clears the floor the batch will sail; if not, expect the
    # guard to stop on whichever member crosses the floor first.
    $CFreeBeforeBatchGB = [math]::Round((Get-Volume -DriveLetter C).SizeRemaining/1GB, 1)
    $BatchWouldLeaveGB = [math]::Round($CFreeBeforeBatchGB - ($Batch.SizeBytes/1GB), 1)
    $FloorNote = if ($BatchWouldLeaveGB -lt $CFreeFloorGB) { " -- may trip the guard" } else { "" }
    Write-Host ("           C: free {0} GB; batch up to {1:N2} GB; floor {2} GB{3}" -f `
        $CFreeBeforeBatchGB, ($Batch.SizeBytes/1GB), $CFreeFloorGB, $FloorNote) `
        -ForegroundColor $(if ($FloorNote) {'Yellow'} else {'Gray'})

    # Resume fast-path: if every member is already fully online-only AND already
    # present on the destination, skip without hydrating. We check placeholder
    # status first (cheap, metadata) so a done batch is never re-hydrated. The
    # count must match the copy mode (see Get-LocalFileCount): a direct-files-only
    # batch only ever hydrated its loose files, so count only those here too.
    $BatchIsDirectFilesOnly = ($Batch.CopyMode -eq "direct-files-only")
    $AnyLocalFiles = $false
    foreach ($Member in $Batch.Members) {
        if ((Get-LocalFileCount -FolderPath $Member -DirectFilesOnly:$BatchIsDirectFilesOnly) -gt 0) { $AnyLocalFiles = $true; break }
    }
    # A batch already online-only was almost certainly copied in a prior run;
    # robocopy below will confirm-and-skip quickly, but if it is online-only we can
    # skip straight past to avoid even launching robocopy on a done batch.
    # (We still run robocopy when unsure, because online-only status alone does not
    #  prove the destination is complete.)

    # Copy each member with robocopy. /E recursive or /LEV:1 for direct-files-only.
    # /COPY:DAT and /FFT match the settings validated in the Zotero backup tests.
    # Never /MIR -- the archive must not delete from the destination.
    $BatchCopyFailed = $false
    foreach ($Member in $Batch.Members) {
        # Destination mirrors the source's path under the source root.
        $RelativePath = $Member.Substring($ArchiveSourceRoot.Length).TrimStart('\')
        $MemberDestination = if ($RelativePath) { Join-Path $DestinationTreeRoot $RelativePath } else { $DestinationTreeRoot }

        # Per-member C: free-space guard. Hydrating this member pulls its bytes onto
        # C: before robocopy writes them to the HDD; if that would drop C: below the
        # floor, refuse now rather than filling C: mid-copy (which can destabilize
        # Windows).
        #
        # MemberBytes must match WHAT ROBOCOPY WILL COPY, which depends on CopyMode:
        #   direct-files-only -> robocopy runs /LEV:1 and copies only the direct files
        #                        in this folder, so measure ONLY those (non-recursive).
        #                        Measuring the whole subtree here is wrong: it would
        #                        report the entire tree (e.g. the 711 GB root) for a
        #                        near-empty direct-files batch and refuse it, and the
        #                        recursive walk of tens of thousands of placeholders is
        #                        also needlessly slow.
        #   recursive         -> robocopy runs /E, so measure the whole subtree.
        # This mirrors exactly how the batch plan sized each mode (direct files summed
        # non-recursively; whole folders summed recursively).
        #
        # Either way MemberBytes is the FULL placeholder size: on resume a partially
        # online member reports full size but needs less hydration, so this guard is
        # deliberately conservative and may refuse a copy that would in fact fit --
        # the safe direction. A direct-files-only member cannot be split by lowering
        # -BatchSizeLimitGB, so if one trips the floor it must be split by hand or the
        # floor lowered with eyes open.
        if ($Batch.CopyMode -eq "direct-files-only") {
            $MemberBytes = [Int64]0
            $MemberDirectFiles = Get-ChildItem -LiteralPath $Member -File -Force -ErrorAction SilentlyContinue
            foreach ($MemberDirectFile in $MemberDirectFiles) { $MemberBytes += [Int64]$MemberDirectFile.Length }
        } else {
            $MemberBytes = Get-FolderSizeBytes -FolderPath $Member
        }
        $CFreeBytesNow = [Int64](Get-Volume -DriveLetter C).SizeRemaining
        $CFreeFloorBytes = [Int64]($CFreeFloorGB * 1GB)
        if (($CFreeBytesNow - $MemberBytes) -lt $CFreeFloorBytes) {
            Write-Host ("[ERROR] Copying this member would drop C: below the {0} GB floor." -f $CFreeFloorGB) -ForegroundColor Red
            Write-Host ("        Member:   {0}" -f $Member) -ForegroundColor Red
            Write-Host ("        Needs:    {0:N2} GB hydrated on C:" -f ($MemberBytes/1GB)) -ForegroundColor Red
            Write-Host ("        C: free:  {0:N2} GB (floor {1} GB)" -f ($CFreeBytesNow/1GB), $CFreeFloorGB) -ForegroundColor Red
            Write-Host "[HINT]  Make an earlier batch's folder 'online-only' to reclaim C: space, then re-run to resume." -ForegroundColor DarkYellow
            Write-Host "[HINT]  Or, if this is a large single 'direct files' member, lower -CFreeFloorGB with eyes open, or split it by hand." -ForegroundColor DarkYellow
            $BatchCopyFailed = $true
            break
        }

        $RoboArgs = @($Member, $MemberDestination, "/COPY:DAT", "/FFT", "/R:2", "/W:5", "/NP", "/NFL", "/NDL")
        if ($Batch.CopyMode -eq "direct-files-only") { $RoboArgs += "/LEV:1" } else { $RoboArgs += "/E" }

        # Count files to copy, matching the copy mode, only to make the note below
        # accurate. robocopy runs silent (/NFL /NDL /NP + Out-Null), so without this
        # a multi-minute HDD copy looks like a stall. We deliberately do NOT add a
        # live progress heartbeat: see DECISIONS.md "copy-time feedback" -- it slows
        # the copy (dest-size polling contends for HDD head) and adds a silent
        # exit-code failure path via Start-Process, not worth it when the run pauses
        # for manual dehydration after every batch anyway.
        if ($Batch.CopyMode -eq "direct-files-only") {
            $FilesToCopyCount = (Get-ChildItem -LiteralPath $Member -File -Force -ErrorAction SilentlyContinue).Count
        } else {
            $FilesToCopyCount = 0
            foreach ($FilePath in [System.IO.Directory]::EnumerateFiles($Member, '*', [System.IO.SearchOption]::AllDirectories)) { $FilesToCopyCount++ }
        }
        Write-Host ("[INFO]  Copying: {0}" -f $Member)
        Write-Host ("[INFO]  {0:N2} GB across {1} files. This can take several minutes on an external HDD;" -f ($MemberBytes/1GB), $FilesToCopyCount)
        Write-Host "        robocopy runs silent -- no output until this member finishes. Not a stall."
        robocopy @RoboArgs | Out-Null
        $RoboExit = $LASTEXITCODE
        if ($RoboExit -ge 8) {
            Write-Host ("[ERROR] Robocopy failed (exit {0}) on {1}" -f $RoboExit, $Member) -ForegroundColor Red
            Write-Host "[HINT]  Fix the issue (space? path?) and re-run; done files will be skipped." -ForegroundColor DarkYellow
            $BatchCopyFailed = $true
            break
        }
    }
    if ($BatchCopyFailed) {
        Write-Host "[ERROR] Stopping so you can resolve the copy failure. Re-run to resume." -ForegroundColor Red
        exit 1
    }

    # Copy for this batch succeeded (or fast-forwarded on resume). Count it now, so
    # the progress line on the next batch reflects true bytes confirmed on the
    # destination. Placed before the fast-forward continue below so already-online
    # batches are counted too, not just freshly hydrated ones.
    $CumulativeCopiedBytes += [Int64]$Batch.SizeBytes

    # If nothing was local (batch was already online-only from a prior run), the
    # copy above just confirmed the destination; skip the dehydrate pause.
    if (-not $AnyLocalFiles) {
        Write-Host "[INFO]  Batch was already online-only (prior run); no dehydrate needed." -ForegroundColor Green
        Write-Host ""
        continue
    }

    # --- Dehydrate pause: open Explorer, wait for the click, poll to completion ---
    $PauseFolder = $Batch.Members[0]
    Start-Process explorer.exe -ArgumentList "`"$PauseFolder`""

    # Count files that were actually hydrated by this batch, matching the copy mode.
    # For direct-files-only this is just the loose files in each member folder; using
    # the recursive count would report the whole tree and never reach zero.
    $TotalInBatch = 0
    foreach ($Member in $Batch.Members) {
        if ($BatchIsDirectFilesOnly) {
            $TotalInBatch += (Get-ChildItem -LiteralPath $Member -File -Force -ErrorAction SilentlyContinue).Count
        } else {
            foreach ($FilePath in [System.IO.Directory]::EnumerateFiles($Member, '*', [System.IO.SearchOption]::AllDirectories)) { $TotalInBatch++ }
        }
    }

    Write-Host ""
    Write-Host "  === MAKE ONLINE-ONLY ===" -ForegroundColor Cyan
    Write-Host "  This batch is copied to the HDD. Free the C: space it used:" -ForegroundColor Cyan
    if ($BatchIsDirectFilesOnly) {
        # Direct-files batch: the member folder also holds SUBFOLDERS that this batch
        # did NOT copy and that other batches will handle. Dehydrating the folder
        # would make the whole tree online-only, including data not yet archived. So
        # name the exact loose files to select instead, and warn off the folder.
        foreach ($Member in $Batch.Members) {
            $LooseFiles = Get-ChildItem -LiteralPath $Member -File -Force -ErrorAction SilentlyContinue |
                Sort-Object -Property Name -Culture ''
            Write-Host ("    In folder: {0}" -f $Member) -ForegroundColor Yellow
            Write-Host ("    Select ONLY these {0} loose file(s), right-click, 'Make online-only':" -f $LooseFiles.Count) -ForegroundColor Yellow
            foreach ($LooseFile in $LooseFiles) {
                Write-Host ("      - {0}" -f $LooseFile.Name) -ForegroundColor Yellow
            }
        }
        Write-Host "  DO NOT 'Make online-only' on the folder itself or any subfolder --" -ForegroundColor Red
        Write-Host "  that would dehydrate data other batches have not archived yet." -ForegroundColor Red
        Write-Host "  (Tip: sort the folder by Type so the loose files group together.)" -ForegroundColor DarkGray
    } else {
        foreach ($Member in $Batch.Members) {
            Write-Host ("    - right-click and 'Make online-only': {0}" -f $Member) -ForegroundColor Yellow
        }
        if ($Batch.Members.Count -gt 1) {
            Write-Host "  (These share a parent; you may dehydrate the parent folder once instead.)" -ForegroundColor DarkGray
        }
    }
    Write-Host ""
    Read-Host "  Press ENTER after clicking 'Make online-only' to watch it complete"

    # Poll until all members are fully online-only. Count matches the copy mode, so
    # a direct-files batch completes when its loose files dehydrate, not when the
    # (untouched) rest of the tree does.
    $PollStart = Get-Date
    $LastRemaining = -1
    while ($true) {
        Start-Sleep -Seconds $DehydrationPollIntervalSeconds
        $Remaining = 0
        foreach ($Member in $Batch.Members) { $Remaining += (Get-LocalFileCount -FolderPath $Member -DirectFilesOnly:$BatchIsDirectFilesOnly) }

        if ($Remaining -eq 0) {
            Write-Host ("  [INFO]  All {0} files online-only. Dehydration complete." -f $TotalInBatch) -ForegroundColor Green
            break
        }
        if ($Remaining -ne $LastRemaining) {
            Write-Host ("  [INFO]  Dehydrating... {0} of {1} files still local" -f $Remaining, $TotalInBatch)
            $LastRemaining = $Remaining
        }
        if (((Get-Date) - $PollStart).TotalSeconds -ge $DehydrationPollTimeoutSeconds) {
            $TimeoutMinutes = [math]::Round($DehydrationPollTimeoutSeconds / 60.0, 0)
            Write-Host ("  [WARN]  {0} of {1} files still local after {2} min." -f $Remaining, $TotalInBatch, $TimeoutMinutes) -ForegroundColor Yellow
            # Skipping here proceeds with C: NOT fully reclaimed: those still-local
            # files keep occupying C:. The next batch's per-member guard will refuse
            # if that leftover pushes C: below the floor, so a skip is bounded, not
            # catastrophic -- but it is a real decision, so require the whole word
            # 'skip' rather than a single keystroke that is easy to hit by reflex.
            Write-Host ("  [WARN]  Continuing now leaves {0} files hydrated on C:. C: free right now: {1} GB." -f `
                $Remaining, ([math]::Round((Get-Volume -DriveLetter C).SizeRemaining/1GB, 1))) -ForegroundColor Yellow
            $DehydrationTimeoutChoice = Read-Host "  Type 'wait' to keep waiting, 'skip' to continue anyway, ENTER to re-check"
            if ($DehydrationTimeoutChoice -eq 'skip') {
                Write-Host ("  [WARN]  Skipping with {0} files still local, by request." -f $Remaining) -ForegroundColor Yellow
                break
            }
            $PollStart = Get-Date
        }
    }

    $FreeNowGB = [math]::Round((Get-Volume -DriveLetter C).SizeRemaining/1GB, 1)
    Write-Host ("  [INFO]  === SAFE TO STOP HERE === Batch {0} done. C: free: {1} GB." -f $Batch.BatchNumber, $FreeNowGB) -ForegroundColor Green
    Write-Host "  [INFO]  To stop, just close this window. Re-run to resume from the next batch." -ForegroundColor Green
    Write-Host ""
}

Write-Host "========== ARCHIVE COMPLETE ==========" -ForegroundColor Green
Write-Host ("[INFO]  All {0} batches copied to {1}." -f $BatchList.Count, $DestinationTreeRoot)
Write-Host "[NEXT]  Verify the destination, then make your SECOND copy (to the other HDD)" -ForegroundColor Cyan
Write-Host "        by robocopying the destination tree HDD-to-HDD -- no Dropbox involved," -ForegroundColor Cyan
Write-Host "        so no hydration and no batching needed for the second copy." -ForegroundColor Cyan
