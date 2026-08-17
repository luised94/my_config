<#
Plan-DropboxArchiveBatches.ps1

Builds the batch plan for archiving a Dropbox tree to an external drive and
writes it to a JSON plan file, WITHOUT hydrating, copying, or changing any
Dropbox state. This is the planning half of the archive workflow. Run it first;
review the summary; then run the archive script, which consumes the JSON plan.

WHY BATCHES EXIST:
  C: has far less free space than the full archive size. Online-only files must
  be hydrated to local disk before copying, and hydration consumes C: space. So
  the archive runs in batches small enough that each batch's hydrated files fit
  in C: headroom, and each batch is dehydrated to reclaim space before the next.

HOW BATCHES ARE FORMED (size accumulator, not per-folder):
  - A top-level folder at or under the batch limit becomes one batch.
  - A top-level folder OVER the limit is walked by its immediate subfolders; the
    subfolders are accumulated into groups, and a group is flushed as one batch
    when it reaches the limit. This is what keeps a Zotero-style folder of tens
    of thousands of tiny subfolders from becoming tens of thousands of batches:
    they group into a handful of ~limit-sized batches instead.
  - A single subfolder larger than the limit is emitted as its own batch with a
    warning; we do not split within a subfolder (no current folder needs it).
  The archive script copies a batch by looping robocopy over the batch's members.

HYDRATION-SAFETY INVARIANT (do not break):
  This planner only enumerates directory entries and reads FileInfo.Length, both
  served from cloud-placeholder metadata; neither downloads content. Do not add
  any content read here. Hydration belongs only in the archive script.

USAGE:
  .\Plan-DropboxArchiveBatches.ps1 -WindowsUser Luised94
  .\Plan-DropboxArchiveBatches.ps1 -WindowsUser Luised94 -BatchSizeLimitGB 40
  .\Plan-DropboxArchiveBatches.ps1 -WindowsUser Luised94 -PlanFilePath C:\temp\archive_plan.json
  .\Plan-DropboxArchiveBatches.ps1 -Help

  -WindowsUser          Windows account name under C:\Users. Required.
  -DropboxAccountName   Dropbox account folder. Default "Luis Martinez".
  -BatchSizeLimitGB     Target max GB per batch. Default 40, chosen to sit under a
                        ~72 GB C: free budget with working slack. Lower if C: is
                        tighter; raise only if C: has more headroom.
  -PlanFilePath         Where to write the JSON plan. Default
                        "$HOME\dropbox_archive_plan.json".
  -Help                 Print this help and exit.

NEXT STEP AFTER THIS SCRIPT:
  Review the printed per-folder summary and the total batch count. If any batch
  is flagged OVER LIMIT, lower -BatchSizeLimitGB and re-run. When the plan looks
  right, run the archive script pointed at the JSON plan file. Do NOT re-run this
  planner once archiving has started: it renumbers batches and breaks resume.
#>

param(
    [string]$WindowsUser = $env:MC_WINDOWS_USER,
    [string]$DropboxAccountName = "Luis Martinez",
    [double]$BatchSizeLimitGB = 40,
    [string]$PlanFilePath = "$HOME\dropbox_archive_plan.json",
    [switch]$Help
)

$ErrorActionPreference = "Stop"

if ($Help) {
    Write-Host @"
Plan-DropboxArchiveBatches.ps1 - build the archive batch plan (no hydration, no copy)

USAGE:
    .\Plan-DropboxArchiveBatches.ps1 -WindowsUser <name> [-BatchSizeLimitGB <n>] [-PlanFilePath <path>]

PARAMETERS:
    -WindowsUser <name>          Windows account name under C:\Users. Required.
    -DropboxAccountName <name>   Dropbox account folder. Default "Luis Martinez".
    -BatchSizeLimitGB <number>   Max GB per batch. Default 40.
    -PlanFilePath <path>         Output JSON plan path. Default ~/dropbox_archive_plan.json.
    -Help                        Show this help and exit.

WHAT IT DOES:
    Reads folder sizes from cloud-placeholder metadata only (no download), groups
    the tree into batches with a size accumulator, prints a per-folder summary,
    and writes the full batch plan as JSON for the archive script to consume.
    Safe to run repeatedly; changes nothing except the plan file.

NEXT STEP:
    Review the summary. If a batch is OVER LIMIT, lower -BatchSizeLimitGB and
    re-run. Then run the archive script against the JSON plan. Do not re-run this
    planner after archiving has started (it renumbers batches, breaking resume).
"@
    exit 0
}

# --- Stage 1: parameter validation (side effects at the edge) ---
if (-not $WindowsUser) {
    Write-Host "[ERROR] -WindowsUser is required (or set MC_WINDOWS_USER)." -ForegroundColor Red
    Write-Host "[HINT]  Example: .\Plan-DropboxArchiveBatches.ps1 -WindowsUser Luised94" -ForegroundColor DarkYellow
    exit 1
}

$ArchiveSourceRoot = "C:\Users\$WindowsUser\MIT Dropbox\$DropboxAccountName"
$BatchSizeLimitBytes = [Int64]($BatchSizeLimitGB * 1GB)

if (-not (Test-Path -LiteralPath $ArchiveSourceRoot)) {
    Write-Host "[ERROR] Source root not found: $ArchiveSourceRoot" -ForegroundColor Red
    Write-Host "[HINT]  Check -WindowsUser and -DropboxAccountName. List candidates with:" -ForegroundColor DarkYellow
    Write-Host "        Get-ChildItem 'C:\Users\$WindowsUser' -Directory | Select-Object Name" -ForegroundColor DarkYellow
    exit 1
}

Write-Host "[INFO]  Source root:      $ArchiveSourceRoot"
Write-Host "[INFO]  Batch size limit: $BatchSizeLimitGB GB"
Write-Host "[INFO]  Plan file:        $PlanFilePath"
Write-Host "[INFO]  Reading sizes from placeholder metadata (no download)..."
Write-Host ""

# --- Stage 2: measure top-level folders (metadata-only) ---
# MeasuredTopLevelFolderBytes maps a top-level folder path to its recursive byte
# total. All reads are FileInfo.Length on enumerated entries; nothing hydrates.
$MeasuredTopLevelFolderBytes = @{}
$TopLevelFolderList = Get-ChildItem -LiteralPath $ArchiveSourceRoot -Directory -Force

# Loose files sitting directly in the source root get their own batch so they are
# never silently skipped.
$RootLooseFileList = Get-ChildItem -LiteralPath $ArchiveSourceRoot -File -Force
$RootLooseFileBytes = [Int64]0
foreach ($LooseFile in $RootLooseFileList) { $RootLooseFileBytes += [Int64]$LooseFile.Length }

foreach ($TopLevelFolder in $TopLevelFolderList) {
    $RecursiveByteTotal = [Int64]0
    try {
        $FileEnumeration = [System.IO.Directory]::EnumerateFiles(
            $TopLevelFolder.FullName, '*', [System.IO.SearchOption]::AllDirectories)
        foreach ($FilePath in $FileEnumeration) {
            $RecursiveByteTotal += [Int64]([System.IO.FileInfo]::new($FilePath)).Length
        }
    } catch {
        Write-Host "[WARN]  Could not fully measure $($TopLevelFolder.Name): $($_.Exception.Message)" -ForegroundColor Yellow
    }
    $MeasuredTopLevelFolderBytes[$TopLevelFolder.FullName] = $RecursiveByteTotal
    Write-Host ("[INFO]  Measured {0,-34} {1,8:N2} GB" -f $TopLevelFolder.Name, ($RecursiveByteTotal/1GB))
}

# --- Stage 3: build the batch plan with a size accumulator ---
# BatchPlan holds one object per batch. Each batch carries the list of member
# directory paths that the archive script will robocopy (one robocopy call per
# member), plus a copy mode telling the archive script whether to copy the member
# recursively or only its direct files (for the root-loose and folder-direct-files
# cases). Mutation of BatchPlan and the accumulator variables is the intended
# side effect of this stage.
$BatchPlan = [System.Collections.Generic.List[PSCustomObject]]::new()

# PerFolderSummary records, for each top-level folder, how many batches it
# produced, for the readable summary at the end.
$PerFolderSummary = [System.Collections.Generic.List[PSCustomObject]]::new()

$AnyBatchOverLimit = $false

# Root loose files first.
if ($RootLooseFileList.Count -gt 0) {
    $BatchPlan.Add([PSCustomObject]@{
        BatchNumber = 0            # renumbered after the full list is built
        SizeBytes   = $RootLooseFileBytes
        CopyMode    = "direct-files-only"
        Members     = @($ArchiveSourceRoot)
        Note        = "$($RootLooseFileList.Count) file(s) directly under the source root"
    })
}

foreach ($TopLevelFolder in ($TopLevelFolderList | Sort-Object -Property Name -Culture '')) {
    $TopLevelBytes = $MeasuredTopLevelFolderBytes[$TopLevelFolder.FullName]
    $BatchesFromThisFolder = 0

    if ($TopLevelBytes -le $BatchSizeLimitBytes) {
        # Fits whole.
        $BatchPlan.Add([PSCustomObject]@{
            BatchNumber = 0
            SizeBytes   = $TopLevelBytes
            CopyMode    = "recursive"
            Members     = @($TopLevelFolder.FullName)
            Note        = "whole folder $($TopLevelFolder.Name)"
        })
        $BatchesFromThisFolder = 1
        $PerFolderSummary.Add([PSCustomObject]@{
            Folder = $TopLevelFolder.Name; SizeGB = [math]::Round($TopLevelBytes/1GB,2); Batches = 1
        })
        continue
    }

    # Over the limit: accumulate immediate subfolders into limit-sized groups.
    # Direct files in this folder (not in any subfolder) become one direct-files batch.
    $DirectFileList = Get-ChildItem -LiteralPath $TopLevelFolder.FullName -File -Force
    if ($DirectFileList.Count -gt 0) {
        $DirectFileBytes = [Int64]0
        foreach ($DirectFile in $DirectFileList) { $DirectFileBytes += [Int64]$DirectFile.Length }
        $BatchPlan.Add([PSCustomObject]@{
            BatchNumber = 0
            SizeBytes   = $DirectFileBytes
            CopyMode    = "direct-files-only"
            Members     = @($TopLevelFolder.FullName)
            Note        = "$($DirectFileList.Count) file(s) directly in $($TopLevelFolder.Name)"
        })
        $BatchesFromThisFolder++
    }

    $ImmediateSubfolderList = Get-ChildItem -LiteralPath $TopLevelFolder.FullName -Directory -Force |
        Sort-Object -Property Name -Culture ''

    # Accumulator state. AccumulatedMemberList and AccumulatedBytes build up until
    # they reach the limit, then flush into one batch and reset.
    $AccumulatedMemberList = [System.Collections.Generic.List[string]]::new()
    $AccumulatedBytes = [Int64]0

    foreach ($Subfolder in $ImmediateSubfolderList) {
        $SubfolderBytes = [Int64]0
        try {
            $SubfolderEnumeration = [System.IO.Directory]::EnumerateFiles(
                $Subfolder.FullName, '*', [System.IO.SearchOption]::AllDirectories)
            foreach ($FilePath in $SubfolderEnumeration) {
                $SubfolderBytes += [Int64]([System.IO.FileInfo]::new($FilePath)).Length
            }
        } catch {
            Write-Host "[WARN]  Could not measure subfolder $($Subfolder.FullName): $($_.Exception.Message)" -ForegroundColor Yellow
        }

        if ($SubfolderBytes -gt $BatchSizeLimitBytes) {
            # A single subfolder bigger than the whole limit. Flush whatever is
            # accumulated, then emit this subfolder alone as an over-limit batch.
            if ($AccumulatedMemberList.Count -gt 0) {
                $BatchPlan.Add([PSCustomObject]@{
                    BatchNumber = 0
                    SizeBytes   = $AccumulatedBytes
                    CopyMode    = "recursive"
                    Members     = @($AccumulatedMemberList.ToArray())
                    Note        = "accumulated group under $($TopLevelFolder.Name)"
                })
                $BatchesFromThisFolder++
                $AccumulatedMemberList = [System.Collections.Generic.List[string]]::new()
                $AccumulatedBytes = [Int64]0
            }
            $AnyBatchOverLimit = $true
            Write-Host ("[WARN]  Subfolder over batch limit: {0} ({1:N2} GB)" -f $Subfolder.FullName, ($SubfolderBytes/1GB)) -ForegroundColor Yellow
            $BatchPlan.Add([PSCustomObject]@{
                BatchNumber = 0
                SizeBytes   = $SubfolderBytes
                CopyMode    = "recursive"
                Members     = @($Subfolder.FullName)
                Note        = "OVER LIMIT alone; will exceed C: budget if larger than free space. Split by hand or lower -BatchSizeLimitGB."
            })
            $BatchesFromThisFolder++
            continue
        }

        # Would adding this subfolder overflow the current group? If so, flush first.
        if (($AccumulatedBytes + $SubfolderBytes) -gt $BatchSizeLimitBytes -and $AccumulatedMemberList.Count -gt 0) {
            $BatchPlan.Add([PSCustomObject]@{
                BatchNumber = 0
                SizeBytes   = $AccumulatedBytes
                CopyMode    = "recursive"
                Members     = @($AccumulatedMemberList.ToArray())
                Note        = "accumulated group under $($TopLevelFolder.Name)"
            })
            $BatchesFromThisFolder++
            $AccumulatedMemberList = [System.Collections.Generic.List[string]]::new()
            $AccumulatedBytes = [Int64]0
        }

        $AccumulatedMemberList.Add($Subfolder.FullName)
        $AccumulatedBytes += $SubfolderBytes
    }

    # Flush the final partial group for this folder.
    if ($AccumulatedMemberList.Count -gt 0) {
        $BatchPlan.Add([PSCustomObject]@{
            BatchNumber = 0
            SizeBytes   = $AccumulatedBytes
            CopyMode    = "recursive"
            Members     = @($AccumulatedMemberList.ToArray())
            Note        = "accumulated group under $($TopLevelFolder.Name)"
        })
        $BatchesFromThisFolder++
    }

    $PerFolderSummary.Add([PSCustomObject]@{
        Folder = $TopLevelFolder.Name; SizeGB = [math]::Round($TopLevelBytes/1GB,2); Batches = $BatchesFromThisFolder
    })
}

# Assign final sequential batch numbers now that the full list exists.
$BatchNumberCounter = 0
foreach ($Batch in $BatchPlan) {
    $BatchNumberCounter++
    $Batch.BatchNumber = $BatchNumberCounter
}

# --- Stage 4: write the JSON plan file (the contract with the archive script) ---
$TotalArchiveBytes = ($BatchPlan | Measure-Object -Property SizeBytes -Sum).Sum
$PlanDocument = [PSCustomObject]@{
    SchemaVersion     = 1
    GeneratedUtc      = (Get-Date).ToUniversalTime().ToString("o")
    SourceRoot        = $ArchiveSourceRoot
    BatchSizeLimitGB  = $BatchSizeLimitGB
    TotalBytes        = $TotalArchiveBytes
    BatchCount        = $BatchPlan.Count
    Batches           = $BatchPlan
}
# -Depth 5 so the nested Members arrays serialize fully rather than as type names.
$PlanDocument | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath $PlanFilePath -Encoding UTF8

# --- Stage 5: readable summary (NOT the 29k-line dump) ---
Write-Host ""
Write-Host "========== ARCHIVE BATCH PLAN (SUMMARY) ==========" -ForegroundColor Green
Write-Host ("Source:        {0}" -f $ArchiveSourceRoot)
Write-Host ("Total size:    {0:N2} GB" -f ($TotalArchiveBytes/1GB))
Write-Host ("Total batches: {0}" -f $BatchPlan.Count)
Write-Host ("Batch limit:   {0} GB" -f $BatchSizeLimitGB)
Write-Host ("Plan file:     {0}" -f $PlanFilePath)
Write-Host ""
Write-Host "Per top-level folder:" -ForegroundColor Cyan
$PerFolderSummary |
    Sort-Object SizeGB -Descending |
    Format-Table @{N='Folder';E={$_.Folder}},
                 @{N='Size(GB)';E={$_.SizeGB}},
                 @{N='Batches';E={$_.Batches}} -AutoSize | Out-Host

if ($AnyBatchOverLimit) {
    Write-Host "[WARN]  One or more batches are OVER the size limit (see warnings above)." -ForegroundColor Yellow
    Write-Host "[HINT]  If an over-limit batch is larger than your C: free space, the archive" -ForegroundColor DarkYellow
    Write-Host "        will not be able to hydrate it. Lower -BatchSizeLimitGB and re-run, or" -ForegroundColor DarkYellow
    Write-Host "        split that folder by hand." -ForegroundColor DarkYellow
}

Write-Host ""
Write-Host "========== NEXT STEPS ==========" -ForegroundColor Cyan
Write-Host "1. Check your C: free space is comfortably above the batch limit:"
Write-Host "     Get-Volume -DriveLetter C | ForEach-Object { [math]::Round(`$_.SizeRemaining/1GB,1) }"
Write-Host "2. If the summary looks right, run the archive script against the plan file:"
Write-Host "     (archive script) -PlanFilePath `"$PlanFilePath`""
Write-Host "3. Do NOT re-run this planner once archiving has started -- it renumbers"
Write-Host "   batches and breaks resume. Re-plan only before the first archive batch."
Write-Host ""
Write-Host "[INFO]  Nothing was hydrated, copied, or changed except the plan file." -ForegroundColor DarkYellow
