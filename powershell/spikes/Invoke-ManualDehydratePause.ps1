<#
Invoke-ManualDehydratePause.ps1

The between-batch manual dehydrate step. Programmatic dehydrate does not work on
this machine (Dropbox ignores the attribute bits -- proven by probe), so after a
batch is copied to the HDD you set its source folder online-only BY HAND via
Dropbox's right-click "Make online-only". This step removes every other bit of
friction and, crucially, WAITS FOR DEHYDRATION TO ACTUALLY FINISH by watching the
files' placeholder flags -- so you don't have to guess when Dropbox is done.

HOW IT KNOWS DEHYDRATION IS DONE (better than measuring free space):
  Each file carries FILE_ATTRIBUTE_RECALL_ON_DATA_ACCESS (0x400000) when it is a
  cloud placeholder (online-only) and clears it when local. When you click "Make
  online-only", Dropbox flips the folder's files back to placeholder one by one.
  This step polls the folder and counts how many files are still local. When that
  count reaches zero, dehydration is complete and it continues automatically. No
  free-space math, no guessing -- it observes the real state.
  (This also fixes the misleading "0.00 GB reclaimed" seen when the free-space
  method sampled a folder that was already dehydrated.)

USAGE:
  .\Invoke-ManualDehydratePause.ps1 -FolderToDehydrate "C:\Users\liusm\MIT Dropbox\Luis Martinez\add_to_zotero"
  .\Invoke-ManualDehydratePause.ps1 -FolderToDehydrate "<folder>" -PollTimeoutSeconds 600
  .\Invoke-ManualDehydratePause.ps1 -Help

  -FolderToDehydrate    The source folder to set online-only by hand. Required.
  -PollIntervalSeconds  Seconds between placeholder re-scans. Default 5.
  -PollTimeoutSeconds   Give up waiting after this long and let you decide.
                        Default 900 (15 min). Large batches of many small files
                        can take a while to dehydrate.
  -Help                 Print this help and exit.
#>

param(
    [Parameter(Mandatory = $true)]
    [string]$FolderToDehydrate,

    [int]$PollIntervalSeconds = 5,
    [int]$PollTimeoutSeconds = 900,
    [switch]$Help
)

$ErrorActionPreference = "Stop"

if ($Help) {
    Write-Host @"
Invoke-ManualDehydratePause.ps1 - manual 'Make online-only' pause that waits for completion

USAGE:
    .\Invoke-ManualDehydratePause.ps1 -FolderToDehydrate <folder> [-PollTimeoutSeconds <n>]

WHAT IT DOES:
    Opens Explorer at the folder, tells you to right-click -> Make online-only,
    then WATCHES the files flip to online-only and continues automatically when
    all of them have. Used between archive batches because Dropbox has no
    scriptable dehydrate.
"@
    exit 0
}

$RECALL_ON_DATA_ACCESS = 0x00400000

$FolderToDehydrate = $FolderToDehydrate.TrimEnd('\')
if (-not (Test-Path -LiteralPath $FolderToDehydrate)) {
    Write-Host "[ERROR] Folder not found: $FolderToDehydrate" -ForegroundColor Red
    exit 1
}

# Count how many files in the folder are still LOCAL (placeholder flag clear).
# This is the poll primitive; called repeatedly below. It is a helper because it
# has multiple real call sites (initial count, and each poll iteration).
function Get-LocalFileCount {
    param([string]$FolderPath)
    $LocalCount = 0
    $Enumeration = [System.IO.Directory]::EnumerateFiles(
        $FolderPath, '*', [System.IO.SearchOption]::AllDirectories)
    foreach ($FilePath in $Enumeration) {
        try {
            $Attrs = [System.IO.File]::GetAttributes($FilePath)
            if (([int]$Attrs -band $RECALL_ON_DATA_ACCESS) -eq 0) { $LocalCount++ }
        } catch { }
    }
    return $LocalCount
}

$TotalFileCount = 0
$Enumeration = [System.IO.Directory]::EnumerateFiles(
    $FolderToDehydrate, '*', [System.IO.SearchOption]::AllDirectories)
foreach ($FilePath in $Enumeration) { $TotalFileCount++ }

$LocalNowCount = Get-LocalFileCount -FolderPath $FolderToDehydrate

# Open Explorer at the folder so you can right-click it immediately.
Start-Process explorer.exe -ArgumentList "`"$FolderToDehydrate`""

Write-Host ""
Write-Host "==================== MANUAL DEHYDRATE STEP ====================" -ForegroundColor Cyan
Write-Host "This batch is copied to the HDD. Now set its source folder online-only:" -ForegroundColor Cyan
Write-Host ""
Write-Host "  Folder: $FolderToDehydrate" -ForegroundColor Yellow
Write-Host ("  Files:  {0} total, {1} currently local (need to become online-only)" -f $TotalFileCount, $LocalNowCount) -ForegroundColor White
Write-Host ""
Write-Host "  In the Explorer window that opened, go UP one level, RIGHT-CLICK the" -ForegroundColor White
Write-Host "  folder above, and choose 'Make online-only'." -ForegroundColor White
Write-Host ""

if ($LocalNowCount -eq 0) {
    Write-Host "[INFO]  This folder is already fully online-only. Nothing to do; continuing." -ForegroundColor Green
    exit 0
}

Write-Host "Click 'Make online-only' now. This step will watch the files flip and" -ForegroundColor Cyan
Write-Host "continue automatically once they are all online-only." -ForegroundColor Cyan
Write-Host ""
Read-Host "Press ENTER once you have clicked 'Make online-only' to start watching"

# --- Poll until all files are online-only, or timeout ---
$PollStart = Get-Date
$LastLocalCount = $LocalNowCount
while ($true) {
    Start-Sleep -Seconds $PollIntervalSeconds
    $LocalRemaining = Get-LocalFileCount -FolderPath $FolderToDehydrate
    $ElapsedSeconds = ((Get-Date) - $PollStart).TotalSeconds

    if ($LocalRemaining -eq 0) {
        Write-Host ("[INFO]  All {0} files are now online-only. Dehydration complete." -f $TotalFileCount) -ForegroundColor Green
        break
    }

    # Progress only when the number actually changes, to avoid spam.
    if ($LocalRemaining -ne $LastLocalCount) {
        Write-Host ("[INFO]  Dehydrating... {0} of {1} files still local" -f $LocalRemaining, $TotalFileCount)
        $LastLocalCount = $LocalRemaining
    }

    if ($ElapsedSeconds -ge $PollTimeoutSeconds) {
        Write-Host ""
        Write-Host ("[WARN]  Still {0} files local after {1:N0}s." -f $LocalRemaining, $ElapsedSeconds) -ForegroundColor Yellow
        Write-Host "[HINT]  Dropbox may still be working, or 'Make online-only' was not applied" -ForegroundColor DarkYellow
        Write-Host "        to the whole folder. Check the folder icon and re-click if needed." -ForegroundColor DarkYellow
        $Choice = Read-Host "Type 'w' to keep waiting, 'c' to continue anyway, or ENTER to re-check now"
        if ($Choice -eq 'c') {
            Write-Host "[WARN]  Continuing with files still local -- C: space not fully reclaimed." -ForegroundColor Yellow
            break
        }
        # Reset the timeout window for another round of waiting.
        $PollStart = Get-Date
    }
}

Write-Host ""
Write-Host "[INFO]  === SAFE TO STOP HERE === This batch is copied AND dehydrated." -ForegroundColor Green
Write-Host "[INFO]  If you need to walk away, do it now. Re-running the archive resumes" -ForegroundColor Green
Write-Host "        cleanly from the next batch." -ForegroundColor Green
