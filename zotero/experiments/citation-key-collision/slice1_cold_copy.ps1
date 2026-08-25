# Slice 1 cold-copy guard. Runs on the Windows side (invoked from WSL via -File).
#
# WHY A GUARD, NOT A WARNING: copying zotero.sqlite while Zotero is alive can yield
# an inconsistent read that no downstream check would catch. So this HARD-FAILS
# (nonzero exit, explicit message) if any Zotero process exists. It never warns
# and proceeds. (Agreed: process guard is hard-fail.)
#
# WHY WAL-AWARE: Zotero 9 uses SQLite WAL mode. A cold copy of zotero.sqlite ALONE
# while a -wal file holds committed-but-not-checkpointed transactions gives a DB
# missing its most recent commits. So we copy the -wal and -shm sidecars too, and
# report whether -wal was non-empty (a large -wal after a clean shutdown is a
# signal Zotero did not close cleanly). (Adversarial findings 1 and 2.)
#
# WHY COPY INTO WSL, NOT READ IN PLACE: reading across /mnt/c has mount
# locking/consistency quirks; the extractor reads the copy, never the live file.
# This script writes the copy to a Windows-visible path that maps into the WSL
# working dir; the caller passes that path in.
#
# Invocation powershell.exe -NoProfile -ExecutionPolicy Bypass -File "$(wslpath -w .../slice1_cold_copy.ps1)" -DestinationDirectoryWindowsPath "$(wslpath -w ~/zotero-experiments)"

param(
    # Windows path of the destination directory for the cold copy. The caller
    # (WSL) converts its working dir with wslpath -w and passes it here.
    [Parameter(Mandatory = $true)]
    [string]$DestinationDirectoryWindowsPath
)

$ErrorActionPreference = "Stop"

# Process guard first. Match is name-based but we enumerate ALL processes whose
# name starts with "zotero" (covers zotero, zotero.exe as reported by .NET, and
# any helper), because a single exact name can miss a variant and let a dirty DB
# through. (Adversarial finding 1: name-blindness.)
$ZoteroProcesses = @(Get-Process -ErrorAction SilentlyContinue | Where-Object { $_.ProcessName -like "zotero*" })
if ($ZoteroProcesses.Count -gt 0) {
    $names = ($ZoteroProcesses | ForEach-Object { $_.ProcessName }) -join ", "
    Write-Error "HALT: $($ZoteroProcesses.Count) Zotero process(es) running ($names). Close Zotero fully before copying."
    exit 1
}
Write-Output "process_guard=clear (no zotero* process running)"

$ZoteroDataDirectory = Join-Path $env:USERPROFILE "Zotero"
$SqlitePath = Join-Path $ZoteroDataDirectory "zotero.sqlite"
$WalPath = Join-Path $ZoteroDataDirectory "zotero.sqlite-wal"
$ShmPath = Join-Path $ZoteroDataDirectory "zotero.sqlite-shm"

if (-not (Test-Path -LiteralPath $SqlitePath)) {
    Write-Error "HALT: zotero.sqlite not found at $SqlitePath"
    exit 1
}
if (-not (Test-Path -LiteralPath $DestinationDirectoryWindowsPath)) {
    Write-Error "HALT: destination directory does not exist: $DestinationDirectoryWindowsPath"
    exit 1
}

# Report the LIVE identity we are about to freeze from, for the record. The frozen
# identity proper is the copied file's, captured AFTER the copy below.
$LiveSqliteItem = Get-Item -LiteralPath $SqlitePath
$LiveMtimeEpoch = [DateTimeOffset]::new($LiveSqliteItem.LastWriteTimeUtc).ToUnixTimeSeconds()
Write-Output "source_live_sqlite_size_bytes=$($LiveSqliteItem.Length)"
Write-Output "source_live_sqlite_mtime_epoch_utc=$LiveMtimeEpoch"

# WAL sidecar reporting BEFORE copy. A non-empty -wal means uncommitted-to-main
# transactions exist in the log; copying it alongside the main file preserves them.
if (Test-Path -LiteralPath $WalPath) {
    $WalItem = Get-Item -LiteralPath $WalPath
    Write-Output "source_wal_present=true source_wal_size_bytes=$($WalItem.Length)"
    if ($WalItem.Length -gt 0) {
        Write-Output "NOTE: -wal is non-empty; Zotero may not have checkpointed on exit. Copy includes -wal so the read is consistent."
    }
} else {
    Write-Output "source_wal_present=false"
}

# Copy main DB and any WAL/SHM sidecars. Copy-Item is a byte copy; with Zotero
# closed and the process guard clear, this is a cold, consistent snapshot.
$DestinationSqlitePath = Join-Path $DestinationDirectoryWindowsPath "zotero.sqlite"
Copy-Item -LiteralPath $SqlitePath -Destination $DestinationSqlitePath -Force
Write-Output "copied_main=$DestinationSqlitePath"

if (Test-Path -LiteralPath $WalPath) {
    Copy-Item -LiteralPath $WalPath -Destination (Join-Path $DestinationDirectoryWindowsPath "zotero.sqlite-wal") -Force
    Write-Output "copied_wal=$(Join-Path $DestinationDirectoryWindowsPath 'zotero.sqlite-wal')"
}
if (Test-Path -LiteralPath $ShmPath) {
    Copy-Item -LiteralPath $ShmPath -Destination (Join-Path $DestinationDirectoryWindowsPath "zotero.sqlite-shm") -Force
    Write-Output "copied_shm=$(Join-Path $DestinationDirectoryWindowsPath 'zotero.sqlite-shm')"
}

# FROZEN SNAPSHOT IDENTITY: size + mtime of the COPIED main file, captured now.
# This is the value every later slice reconciles against -- NOT the live value,
# which drifts. (Adversarial finding 7.)
$CopiedItem = Get-Item -LiteralPath $DestinationSqlitePath
$FrozenMtimeEpoch = [DateTimeOffset]::new($CopiedItem.LastWriteTimeUtc).ToUnixTimeSeconds()
Write-Output "frozen_snapshot_size_bytes=$($CopiedItem.Length)"
Write-Output "frozen_snapshot_mtime_epoch_utc=$FrozenMtimeEpoch"

# Note (do not read/copy) the better-bibtex.sqlite existence for Slice 2. BBT may
# have folded keys into Zotero's native citation-key field, leaving this vestigial;
# Slice 2 decides the authoritative key source. We only record what is visible here.
$BetterBibtexPath = Join-Path $ZoteroDataDirectory "better-bibtex.sqlite"
if (Test-Path -LiteralPath $BetterBibtexPath) {
    $BbtItem = Get-Item -LiteralPath $BetterBibtexPath
    $BbtMtimeEpoch = [DateTimeOffset]::new($BbtItem.LastWriteTimeUtc).ToUnixTimeSeconds()
    Write-Output "better_bibtex_sqlite_present=true better_bibtex_size_bytes=$($BbtItem.Length) better_bibtex_mtime_epoch_utc=$BbtMtimeEpoch"
} else {
    Write-Output "better_bibtex_sqlite_present=false"
}

Write-Output "cold_copy=OK"
