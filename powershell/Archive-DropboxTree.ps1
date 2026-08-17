<#
Archive-DropboxTree.ps1

Archives a Dropbox tree (mostly online-only placeholders) to an external drive,
one size-bounded batch at a time, pausing after each batch for a MANUAL Dropbox
"Make online-only" to reclaim C: space before the next batch.

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
  50 GB against ~72 GB free keeps a ~20 GB Windows working floor while roughly
  halving the click count versus 40 GB. Lower it if C: is tighter; do not raise it
  so high that a batch plus Windows overhead would drop C: below ~15-20 GB free.

RESUME: safe to stop between batches and re-run. Robocopy skips files already on
  the HDD, so completed batches fast-forward; a source already online-only is not
  re-hydrated. No state file -- the filesystem itself is the state.

HYDRATION-SAFETY INVARIANT (do not break):
  Only the COPY step (robocopy) may hydrate. All measurement/enumeration reads
  FileInfo.Length and attributes only, which are placeholder metadata and do not
  download. Never add a content read to the walk/measure paths.

USAGE:
  # Dry run -- walk the tree, print the batch plan, copy nothing:
  .\Archive-DropboxTree.ps1 -WindowsUser Luised94 -DestinationRoot "E:\"

  # Real archive -- copy each batch to the HDD, pausing for manual dehydrate:
  .\Archive-DropboxTree.ps1 -WindowsUser Luised94 -DestinationRoot "E:\" -Execute

  # Resume (same command) -- completed batches fast-forward:
  .\Archive-DropboxTree.ps1 -WindowsUser Luised94 -DestinationRoot "E:\" -Execute

  -WindowsUser        Windows account under C:\Users. Required. (On this machine
                      it has been seen as both 'Luised94' and 'liusm' -- pass the
                      one that matches C:\Users on the device you are running on.)
  -DropboxAccountName Dropbox account folder. Default "Luis Martinez".
  -DestinationRoot    Root of the external drive (e.g. "E:\"). Required for real
                      runs. The tree is copied under <DestinationRoot>\<account>.
  -BatchSizeLimitGB   Max GB per batch. Default 50. See balance note above.
  -Execute            Perform real hydration/copy and the dehydrate pauses. Without
                      it, the script only prints the plan (no copy, no hydration).
  -MaxRecursionDepth  Safety cap on how deep the batch walk descends into
                      over-limit folders. Default 8. If a folder is still over the
                      limit at this depth, it is emitted as one over-limit batch
                      with a warning rather than descending further.
  -Help               Print this help and exit.
#>

param(
    [string]$WindowsUser = $env:MC_WINDOWS_USER,
    [string]$DropboxAccountName = "Luis Martinez",
    [string]$DestinationRoot,
    [double]$BatchSizeLimitGB = 50,
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
# dehydrate pause to detect completion.
function Get-LocalFileCount {
    param([string]$FolderPath)
    $LocalCount = 0
    try {
        $Enumeration = [System.IO.Directory]::EnumerateFiles(
            $FolderPath, '*', [System.IO.SearchOption]::AllDirectories)
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
    if ($AccumulatedMembers.Count -gt 0) {
        $script:BatchList.Add([PSCustomObject]@{
            Members  = @($script:AccumulatedMembers.ToArray())
            SizeBytes= $script:AccumulatedBytes
            CopyMode = "recursive"
            Label    = $script:AccumulatedLabel
        })
        $script:AccumulatedMembers = [System.Collections.Generic.List[string]]::new()
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

# --- Stage 4: execute each batch (copy -> dehydrate pause) ---
Write-Host "========== EXECUTING ARCHIVE ==========" -ForegroundColor Green
Write-Host "[INFO]  You will be asked to 'Make online-only' after each batch." -ForegroundColor Cyan
Write-Host ""

foreach ($Batch in $BatchList) {
    Write-Host ("---------- Batch {0}/{1}: {2} ({3:N2} GB) ----------" -f `
        $Batch.BatchNumber, $BatchList.Count, $Batch.Label, ($Batch.SizeBytes/1GB)) -ForegroundColor Cyan

    # Resume fast-path: if every member is already fully online-only AND already
    # present on the destination, skip without hydrating. We check placeholder
    # status first (cheap, metadata) so a done batch is never re-hydrated.
    $AnyLocalFiles = $false
    foreach ($Member in $Batch.Members) {
        if ((Get-LocalFileCount -FolderPath $Member) -gt 0) { $AnyLocalFiles = $true; break }
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

        $RoboArgs = @($Member, $MemberDestination, "/COPY:DAT", "/FFT", "/R:2", "/W:5", "/NP", "/NFL", "/NDL")
        if ($Batch.CopyMode -eq "direct-files-only") { $RoboArgs += "/LEV:1" } else { $RoboArgs += "/E" }

        Write-Host ("[INFO]  Copying: {0}" -f $Member)
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

    $TotalInBatch = 0
    foreach ($Member in $Batch.Members) {
        $Enumeration = [System.IO.Directory]::EnumerateFiles($Member, '*', [System.IO.SearchOption]::AllDirectories)
        foreach ($FilePath in $Enumeration) { $TotalInBatch++ }
    }

    Write-Host ""
    Write-Host "  === MAKE ONLINE-ONLY ===" -ForegroundColor Cyan
    Write-Host "  This batch is copied to the HDD. Free the C: space it used:" -ForegroundColor Cyan
    foreach ($Member in $Batch.Members) {
        Write-Host ("    - right-click and 'Make online-only': {0}" -f $Member) -ForegroundColor Yellow
    }
    if ($Batch.Members.Count -gt 1) {
        Write-Host "  (These share a parent; you may dehydrate the parent folder once instead.)" -ForegroundColor DarkGray
    }
    Write-Host ""
    Read-Host "  Press ENTER after clicking 'Make online-only' to watch it complete"

    # Poll until all members are fully online-only.
    $PollStart = Get-Date
    $LastRemaining = -1
    while ($true) {
        Start-Sleep -Seconds 5
        $Remaining = 0
        foreach ($Member in $Batch.Members) { $Remaining += (Get-LocalFileCount -FolderPath $Member) }

        if ($Remaining -eq 0) {
            Write-Host ("  [INFO]  All {0} files online-only. Dehydration complete." -f $TotalInBatch) -ForegroundColor Green
            break
        }
        if ($Remaining -ne $LastRemaining) {
            Write-Host ("  [INFO]  Dehydrating... {0} of {1} files still local" -f $Remaining, $TotalInBatch)
            $LastRemaining = $Remaining
        }
        if (((Get-Date) - $PollStart).TotalSeconds -ge 900) {
            Write-Host ("  [WARN]  {0} files still local after 15 min." -f $Remaining) -ForegroundColor Yellow
            $Choice = Read-Host "  Type 'w' to keep waiting, 'c' to continue anyway, ENTER to re-check"
            if ($Choice -eq 'c') { break }
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
