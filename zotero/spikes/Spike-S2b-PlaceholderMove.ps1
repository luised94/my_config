# STATUS: COMPLETED SPIKE (thread 2). Run once on Windows, 2026-07.
# Not maintained. Kept for reference and re-runnability. Findings are
# recorded in handoff/02_orphan_pipeline.md "Verified facts". Result: PASS
# (Move-Item within the Dropbox root preserves the online-only placeholder;
# no hydration, no corruption). Re-run only to re-confirm on a new Windows
# or Dropbox client version.
# =============================================================================
# SPIKE S2b: DROPBOX PLACEHOLDER MOVE / HYDRATION TEST
# =============================================================================
# Version: 1.0
# Purpose: Verify, on ONE user-chosen online-only file, that Move-Item within
#          the same Dropbox root (same NTFS volume) is a rename that preserves
#          the online-only placeholder state (no hydration, no corruption).
#          Optionally tests dehydration via attrib.exe +U (Cloud Filter
#          "free up space"). Results feed handoff/02 Verified facts and the
#          Move-OrphanFiles.ps1 design.
# Usage:   Pick a file you KNOW is online-only (cloud icon in Explorer).
#          Dry run (prints plan and current attributes only):
#            .\Spike-S2b-PlaceholderMove.ps1 -TestFile "C:\...\some.pdf"
#          Execute (move to temp dir, inspect, move back, inspect):
#            .\Spike-S2b-PlaceholderMove.ps1 -TestFile "C:\...\some.pdf" -Execute
#          Add -TestDehydrate to also try attrib +U on the file afterwards.
# Safety:  Operates on exactly one explicitly named file. Dry run by default.
#          Move destination defaults to a sibling folder next to the file so
#          the move stays on the same volume and inside the Dropbox root.
#          Never reads file contents.
# =============================================================================

param(
    [Parameter(Mandatory = $true)]
    [string]$TestFile,

    # Default: sibling folder next to the file's parent directory.
    [string]$TempDir = "",

    [switch]$Execute,

    [switch]$TestDehydrate
)

$ErrorActionPreference = "Stop"

# Cloud Filter / placeholder attribute bits (winnt.h)
$FILE_ATTRIBUTE_OFFLINE               = 0x00001000
$FILE_ATTRIBUTE_PINNED                = 0x00080000
$FILE_ATTRIBUTE_UNPINNED              = 0x00100000
$FILE_ATTRIBUTE_RECALL_ON_OPEN        = 0x00040000
$FILE_ATTRIBUTE_RECALL_ON_DATA_ACCESS = 0x00400000

function Get-AttributeReport {
    param([string]$Path)
    $item = Get-Item -LiteralPath $Path -Force
    $raw = [int]$item.Attributes
    $report = [ordered]@{
        Path               = $Path
        RawAttributes      = ("0x{0:X8}" -f $raw)
        AttributesText     = $item.Attributes.ToString()
        Length             = $item.Length
        Offline            = (($raw -band $FILE_ATTRIBUTE_OFFLINE) -ne 0)
        Pinned             = (($raw -band $FILE_ATTRIBUTE_PINNED) -ne 0)
        Unpinned           = (($raw -band $FILE_ATTRIBUTE_UNPINNED) -ne 0)
        RecallOnOpen       = (($raw -band $FILE_ATTRIBUTE_RECALL_ON_OPEN) -ne 0)
        RecallOnDataAccess = (($raw -band $FILE_ATTRIBUTE_RECALL_ON_DATA_ACCESS) -ne 0)
        LastWriteTimeUtc   = $item.LastWriteTimeUtc.ToString("o")
    }
    # RecallOnDataAccess set => file is a dehydrated (online-only) placeholder.
    $report.IsPlaceholder = $report.RecallOnDataAccess -or $report.RecallOnOpen
    return [pscustomobject]$report
}

function Write-Report {
    param([string]$Label, [object]$Report)
    Write-Host ""
    Write-Host ("--- {0} ---" -f $Label)
    $Report | Format-List | Out-String | Write-Host
}

# --- Validation ---
if (-not (Test-Path -LiteralPath $TestFile -PathType Leaf)) {
    throw "TestFile not found: $TestFile"
}
$fileItem = Get-Item -LiteralPath $TestFile -Force
$parentDir = $fileItem.Directory.FullName
if ($TempDir -eq "") {
    $TempDir = Join-Path $parentDir "spike_s2b_move_test"
}
$sourceRoot = [System.IO.Path]::GetPathRoot($fileItem.FullName)
$destRoot = [System.IO.Path]::GetPathRoot([System.IO.Path]::GetFullPath($TempDir))
if ($sourceRoot -ne $destRoot) {
    throw "TempDir is on a different volume ($destRoot vs $sourceRoot); a cross-volume move would hydrate. Aborting."
}

$before = Get-AttributeReport -Path $fileItem.FullName
Write-Report -Label "BEFORE (original location)" -Report $before

if (-not $before.IsPlaceholder) {
    Write-Host "WARNING: this file does not look online-only (no RecallOnDataAccess/RecallOnOpen bit)."
    Write-Host "The move test still runs, but pick an online-only file for a meaningful result."
}

# --- Plan ---
$destPath = Join-Path $TempDir $fileItem.Name
Write-Host ""
Write-Host "PLAN:"
Write-Host ("  1. Create temp dir (if needed): {0}" -f $TempDir)
Write-Host ("  2. Move-Item: {0} -> {1}" -f $fileItem.FullName, $destPath)
Write-Host "  3. Read attributes at destination (expect placeholder bits unchanged)"
Write-Host ("  4. Move-Item back: {0} -> {1}" -f $destPath, $fileItem.FullName)
Write-Host "  5. Read attributes at original location"
if ($TestDehydrate) {
    Write-Host "  6. attrib.exe +U -P on the file (request dehydration), wait 5 s, re-read attributes"
}

if (-not $Execute) {
    Write-Host ""
    Write-Host "DRY RUN (default). Re-run with -Execute to perform the test."
    return
}

# --- Execute ---
if (-not (Test-Path -LiteralPath $TempDir)) {
    New-Item -ItemType Directory -Path $TempDir | Out-Null
}

Move-Item -LiteralPath $fileItem.FullName -Destination $destPath
$atDest = Get-AttributeReport -Path $destPath
Write-Report -Label "AFTER MOVE (temp location)" -Report $atDest

Move-Item -LiteralPath $destPath -Destination $fileItem.FullName
$afterBack = Get-AttributeReport -Path $fileItem.FullName
Write-Report -Label "AFTER MOVE BACK (original location)" -Report $afterBack

$movePreserved = ($before.IsPlaceholder -eq $atDest.IsPlaceholder) -and
                 ($before.IsPlaceholder -eq $afterBack.IsPlaceholder)
if ($movePreserved) {
    Write-Host "RESULT: PASS - placeholder state preserved through move and move-back (no hydration)."
} else {
    Write-Host "RESULT: FAIL - placeholder state changed. Do NOT assume Move-Item is hydration-safe."
}

# Clean up empty temp dir
if ((Get-ChildItem -LiteralPath $TempDir -Force | Measure-Object).Count -eq 0) {
    Remove-Item -LiteralPath $TempDir
}

# --- Optional dehydration test ---
if ($TestDehydrate) {
    Write-Host ""
    Write-Host "Requesting dehydration via: attrib.exe +U -P `"$($fileItem.FullName)`""
    & attrib.exe +U -P "$($fileItem.FullName)"
    Start-Sleep -Seconds 5
    $afterDehydrate = Get-AttributeReport -Path $fileItem.FullName
    Write-Report -Label "AFTER DEHYDRATION REQUEST" -Report $afterDehydrate
    if ($afterDehydrate.IsPlaceholder) {
        Write-Host "RESULT: attrib +U appears effective; the mover could dehydrate quarantined files."
    } else {
        Write-Host "RESULT: file not dehydrated (Dropbox may not honor attrib +U, or sync lag; check Explorer badge later)."
    }
}

Write-Host ""
Write-Host "Paste all output above into handoff/02 Verified facts, stamped with Dropbox client version and Windows version."
