# Backup-ZoteroStorage.ps1
# Syncs Zotero storage from Dropbox to an external backup drive.
# Uses robocopy as copy engine; handles Dropbox cloud-only placeholders.
# Version: 0.1.0 (Commit 1 - skeleton + validation)
# Date: 2026-03-04
#
# Usage from WSL:
#   powershell.exe -NoProfile -ExecutionPolicy Bypass \
#     -File "$(wslpath -w ~/personal_repos/my_config/zotero/scripts/Backup-ZoteroStorage.ps1)" \
#     -WindowsUser "$MC_WINDOWS_USER"
#
# Test results (2026-03-04):
#   Test A (robocopy hydrates placeholders): PASSED - full content copied, not stub
#   Test B (exit code accessible): PASSED - Int32, code 1 on dry run
#   Test C (bracket filenames): PASSED - robocopy handles them natively

param(
    [string]$WindowsUser = $env:MC_WINDOWS_USER,
    [string]$DropboxUser = "Luis Martinez",
    [switch]$Help,
    [switch]$Execute,
    [switch]$Mirror,
    [switch]$SkipHydrate,
    [switch]$SingleThread = $true,
    [string]$LogPath = "$HOME\zotero_backup.log"
)

$ErrorActionPreference = "Stop"

# --- Help ---
if ($Help) {
    Write-Host @"
Backup-ZoteroStorage.ps1 - Sync Zotero storage from Dropbox to external drive

USAGE:
    .\Backup-ZoteroStorage.ps1 -WindowsUser <name> [OPTIONS]

PARAMETERS:
    -WindowsUser <name>  Windows username (default: env MC_WINDOWS_USER)
    -DropboxUser <name>  Dropbox account name (default: "Luis Martinez")
    -Help                Show this help and exit
    -Execute             Perform real copy (default is dry run)
    -Mirror              Enable /MIR - deletes extras from destination (requires -Execute)
    -SkipHydrate         Skip prehydration pass, rely on robocopy to hydrate
    -SingleThread        Use /MT:1 (default: true, safest for first run)
    -LogPath <path>      Robocopy log file (default: ~/zotero_backup.log)

EXAMPLES:
    # Dry run (see what would happen):
    .\Backup-ZoteroStorage.ps1 -WindowsUser Luised94

    # First real backup (safe copy, no deletions):
    .\Backup-ZoteroStorage.ps1 -WindowsUser Luised94 -Execute

    # Subsequent runs (mirror, delete extras):
    .\Backup-ZoteroStorage.ps1 -WindowsUser Luised94 -Execute -Mirror

    # Fast incremental (multithreaded, skip hydration):
    .\Backup-ZoteroStorage.ps1 -WindowsUser Luised94 -Execute -SkipHydrate -SingleThread:`$false
"@
    exit 0
}

# --- Step 1: Parameter Validation ---
if (-not $WindowsUser) {
    Write-Host "[ERROR] -WindowsUser is required (or set MC_WINDOWS_USER env var)" -ForegroundColor Red
    exit 1
}

if ($Mirror -and -not $Execute) {
    Write-Host "[ERROR] -Mirror requires -Execute (mirror mode deletes files from destination)" -ForegroundColor Red
    exit 1
}

# Derived paths (computed once, read-only)
$SourceDir = "C:\Users\$WindowsUser\MIT Dropbox\$DropboxUser\zotero-storage"
$FolderName = Split-Path $SourceDir -Leaf
$MarkerFile = "backup_drive.txt"
$SourceDrive = $SourceDir.Substring(0, 1)

Write-Host "[INFO]  User: $WindowsUser"
Write-Host "[INFO]  Source: $SourceDir"

# --- Step 2: Environment Validation ---
if (-not (Test-Path -LiteralPath $SourceDir)) {
    Write-Host "[ERROR] Source directory does not exist: $SourceDir" -ForegroundColor Red
    exit 1
}

if (-not (Get-Command robocopy -ErrorAction SilentlyContinue)) {
    Write-Host "[ERROR] robocopy not found in PATH" -ForegroundColor Red
    exit 1
}

Write-Host "[INFO]  Validation passed"
exit 0
