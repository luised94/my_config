# Backup-ZoteroStorage.ps1
# Syncs Zotero storage from Dropbox to an external backup drive.
# Uses robocopy as copy engine; handles Dropbox cloud-only placeholders.
# Version: 1.0.0
# Date: 2026-03-05
#
# Invocation from WSL:
#   powershell.exe -NoProfile -ExecutionPolicy Bypass \
#     -File "$(wslpath -w ~/personal_repos/my_config/zotero/powershell/Backup-ZoteroStorage.ps1)" \
#     -WindowsUser "$MC_WINDOWS_USER"
#
# Quick alias (add to .bashrc):
#   alias zbk='powershell.exe -NoProfile -ExecutionPolicy Bypass -File "$(wslpath -w ~/personal_repos/my_config/zotero/powershell/Backup-ZoteroStorage.ps1)"'
#
# Recommended usage:
#   zbk -WindowsUser "$MC_WINDOWS_USER" -SkipHydrate              # dry run
#   zbk -WindowsUser "$MC_WINDOWS_USER" -Execute                  # first backup (copy only)
#   zbk -WindowsUser "$MC_WINDOWS_USER" -Execute -Mirror          # mirror (deletes extras)
#   zbk -WindowsUser "$MC_WINDOWS_USER" -Execute -SingleThread:$false  # fast incremental
#
# Debug - single file placeholder check:
#   [System.IO.File]::GetAttributes("C:\path\to\file") -band 0x00400000
#
# Debug - single directory robocopy test:
#   robocopy "C:\Users\$env:MC_WINDOWS_USER\MIT Dropbox\Luis Martinez\zotero-storage\SomeDir" "$env:TEMP\robocopy_test" /COPY:DAT /FFT /R:2 /W:5
#
# Test results (2026-03-04):
#   Test A (robocopy hydrates placeholders): PASSED - full content copied, not stub
#   Test B (exit code accessible): PASSED - Int32, code 1 on dry run
#   Test C (bracket filenames): PASSED - robocopy handles them natively
#
# Destructive operations:
#   - Hydration (Step 4): downloads cloud files to local disk, consumes C: space
#   - Robocopy /E (Step 8): writes files to backup drive, never deletes
#   - Robocopy /MIR (Step 8): writes files AND deletes extras from backup drive

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

SAFETY:
    Default is dry run. No files copied or deleted without -Execute.
    -Mirror deletes files from destination - requires -Execute.
    Hydration downloads cloud files to local disk - consumes C: space.

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

# --- Step 3: Source Enumeration + Metrics (read-only) ---
Write-Host "[INFO]  Enumerating source files..."
$SourceFiles = Get-ChildItem -Path $SourceDir -Recurse -File
$SourceMetrics = $SourceFiles | Measure-Object -Property Length -Sum
$SourceFileCount = $SourceMetrics.Count
$SourceTotalBytes = $SourceMetrics.Sum

Write-Host "[INFO]  Source: $SourceFileCount files, $([math]::Round($SourceTotalBytes / 1GB, 2)) GB"

# --- Step 4: Prehydration (state-changing - downloads cloud files to local disk) ---
if ($SkipHydrate) {
    Write-Host "[INFO]  Skipping hydration (-SkipHydrate)"
} else {
    Write-Host "[INFO]  Hydrating placeholder files..."
    $HydrateAttempted = 0
    $HydrateSuccess = 0
    $HydrateFail = 0

    foreach ($file in $SourceFiles) {
        $attrs = [System.IO.File]::GetAttributes($file.FullName)
        if ($attrs -band 0x00400000) {
            $HydrateAttempted++
            try {
                Get-Content -LiteralPath $file.FullName -TotalCount 1 -ErrorAction Stop | Out-Null
                $HydrateSuccess++
            } catch {
                $HydrateFail++
                Write-Host "[WARN]  Hydration failed: $($file.FullName)" -ForegroundColor Yellow
            }
        }
    }

    if ($HydrateAttempted -eq 0) {
        Write-Host "[INFO]  Hydration: no placeholders found (all files local)"
    } else {
        Write-Host "[INFO]  Hydration: $HydrateAttempted attempted, $HydrateSuccess ok, $HydrateFail failed"
    }
}

# --- Step 5: Placeholder Validation (read-only, always runs, hard gate) ---
Write-Host "[INFO]  Validating no placeholders remain..."
$PlaceholderCount = 0
$PlaceholderExamples = @()

foreach ($file in $SourceFiles) {
    $attrs = [System.IO.File]::GetAttributes($file.FullName)
    if ($attrs -band 0x00400000) {
        $PlaceholderCount++
        if ($PlaceholderExamples.Count -lt 10) {
            $PlaceholderExamples += $file.FullName
        }
    }
}

if ($PlaceholderCount -gt 0) {
    Write-Host "[ERROR] $PlaceholderCount placeholders remain after hydration" -ForegroundColor Red
    foreach ($example in $PlaceholderExamples) {
        Write-Host "[ERROR]   $example" -ForegroundColor Red
    }
    if ($PlaceholderCount -gt 10) {
        Write-Host "[ERROR]   ... and $($PlaceholderCount - 10) more" -ForegroundColor Red
    }
    exit 1
}

Write-Host "[INFO]  Validation passed: 0 placeholders"

# --- Step 6: Drive Detection (read-only + write test) ---
Write-Host "[INFO]  Searching for backup drive (marker: $MarkerFile)..."
$DriveLetter = ""

Get-Volume | Where-Object {
    $_.DriveLetter -and (Test-Path "$($_.DriveLetter):\$MarkerFile")
} | ForEach-Object {
    $DriveLetter = $_.DriveLetter
}

if (-not $DriveLetter) {
    Write-Host "[ERROR] No backup drive found with marker file: $MarkerFile" -ForegroundColor Red
    Write-Host "[ERROR] Ensure the drive is connected and $MarkerFile exists at its root" -ForegroundColor Red
    exit 1
}

$DestDir = "$($DriveLetter):\$FolderName"
Write-Host "[INFO]  Backup drive: $($DriveLetter):\"
Write-Host "[INFO]  Destination: $DestDir"

# Write test - confirm drive is writable (state-changing, self-cleaning)
$TestFile = "$($DriveLetter):\zotero_backup_write_test_$(Get-Date -Format 'yyyyMMddHHmmss').tmp"
try {
    New-Item -Path $TestFile -ItemType File -Force | Out-Null
    Remove-Item -Path $TestFile -Force
} catch {
    Write-Host "[ERROR] Backup drive is not writable: $($DriveLetter):\" -ForegroundColor Red
    exit 1
}

# --- Step 7: Disk Space Check (read-only) ---
$SourceVolume = Get-Volume -DriveLetter $SourceDrive
$DestVolume = Get-Volume -DriveLetter $DriveLetter
$SourceFreeBytes = $SourceVolume.SizeRemaining
$DestFreeBytes = $DestVolume.SizeRemaining

Write-Host "[INFO]  Source drive ($($SourceDrive):): $([math]::Round($SourceFreeBytes / 1GB, 2)) GB free"
Write-Host "[INFO]  Backup drive ($($DriveLetter):): $([math]::Round($DestFreeBytes / 1GB, 2)) GB free"

# Source drive: warn if low (hydration could fail on cold machine)
if ($SourceFreeBytes -lt ($SourceTotalBytes * 0.1)) {
    Write-Host "[WARN]  Source drive has less than 10% of source data size free" -ForegroundColor Yellow
    Write-Host "[WARN]  Hydration on a cold machine may fill this drive" -ForegroundColor Yellow
}

# Backup drive: hard gate for first run, warn for incremental
$DestExists = Test-Path -LiteralPath $DestDir
if (-not $DestExists -and $DestFreeBytes -lt $SourceTotalBytes) {
    Write-Host "[ERROR] First backup requires ~$([math]::Round($SourceTotalBytes / 1GB, 2)) GB but drive has $([math]::Round($DestFreeBytes / 1GB, 2)) GB free" -ForegroundColor Red
    exit 1
} elseif ($DestExists -and $DestFreeBytes -lt ($SourceTotalBytes * 0.1)) {
    Write-Host "[WARN]  Backup drive has less than 10% headroom for incremental sync" -ForegroundColor Yellow
}

Write-Host "[INFO]  Disk space ok"

# --- Step 8: Robocopy (read-only in dry run, state-changing/destructive with -Execute) ---
$RobocopyArgs = @($SourceDir, $DestDir, "/COPY:DAT", "/FFT", "/R:2", "/W:5", "/NP")

if ($Execute -and $Mirror) {
    $RobocopyArgs += "/MIR"
    $Mode = "mirror"
    Write-Host "[WARN]  MIRROR MODE: files not in source will be DELETED from destination" -ForegroundColor Yellow
} else {
    $RobocopyArgs += "/E"
    $Mode = "copy"
}

if (-not $Execute) {
    $RobocopyArgs += "/L"
    $Mode = "dry-run"
    Write-Host "[INFO]  DRY RUN - no files will be copied or deleted"
}

if ($SingleThread) {
    $RobocopyArgs += "/MT:1"
} else {
    $RobocopyArgs += "/MT:8"
}

# Log with append and tee to console
$RobocopyArgs += "/LOG+:$LogPath"
$RobocopyArgs += "/TEE"

# Write run delimiter to log for grep/awk parsing
$RunTimestamp = Get-Date -Format "yyyy-MM-ddTHH:mm:ss"
$Delimiter = "========== RUN: $RunTimestamp | USER: $WindowsUser | MODE: $Mode =========="
Add-Content -Path $LogPath -Value "`n$Delimiter"

Write-Host "[INFO]  Mode: $Mode | Threads: $(if ($SingleThread) {'1'} else {'8'}) | Log: $LogPath"
Write-Host "[INFO]  Running robocopy..."

robocopy @RobocopyArgs
$RobocopyExitCode = $LASTEXITCODE

# --- Step 9: Robocopy Result ---
$ExitMessage = switch ($RobocopyExitCode) {
    0       { "No changes - already in sync" }
    1       { "Files copied successfully" }
    2       { "Extra files detected in destination" }
    3       { "Files copied + extras detected" }
    { $_ -ge 4 -and $_ -le 7 } { "Completed with warnings (code $_)" }
    default { "Robocopy FAILED (code $_)" }
}

if ($RobocopyExitCode -lt 8) {
    Write-Host "[INFO]  Robocopy: $ExitMessage"
} else {
    Write-Host "[ERROR] Robocopy: $ExitMessage" -ForegroundColor Red
}

Write-Host "[INFO]  Log: $LogPath"

if ($RobocopyExitCode -ge 8) {
    exit 1
}

# --- Step 10: Post-Copy Reconciliation (read-only, skip if dry run) ---
if (-not $Execute) {
    Write-Host "[INFO]  Skipping reconciliation (dry run)"
    exit 0
}

Write-Host "[INFO]  Reconciling source and destination..."
$DestFiles = Get-ChildItem -Path $DestDir -Recurse -File
$DestMetrics = $DestFiles | Measure-Object -Property Length -Sum
$DestFileCount = $DestMetrics.Count
$DestTotalBytes = $DestMetrics.Sum

Write-Host "[INFO]  Destination: $DestFileCount files, $([math]::Round($DestTotalBytes / 1GB, 2)) GB"

$CountDelta = $SourceFileCount - $DestFileCount
$SizeDelta = $SourceTotalBytes - $DestTotalBytes

if ($CountDelta -eq 0) {
    Write-Host "[INFO]  Reconciliation passed: counts match ($SourceFileCount files)"
} elseif ($CountDelta -gt 0) {
    Write-Host "[WARN]  Source has $CountDelta more files than destination" -ForegroundColor Yellow
    if (-not $Mirror) {
        Write-Host "[WARN]  Files may have failed to copy - check log for errors" -ForegroundColor Yellow
    }
} else {
    # Destination has more files than source (extras from previous syncs)
    $ExtraCount = [math]::Abs($CountDelta)
    Write-Host "[INFO]  Destination has $ExtraCount extra files (not in source)"
    if (-not $Mirror) {
        Write-Host "[INFO]  Use -Execute -Mirror to remove extras from destination"
    }
}

Write-Host "[INFO]  Complete: $DestDir"
exit 0
