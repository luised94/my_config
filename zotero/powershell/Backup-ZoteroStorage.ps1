# Backup-ZoteroStorage.ps1
# Syncs Zotero storage from Dropbox to an external backup drive.
# Uses robocopy as copy engine; handles Dropbox cloud-only placeholders.
# Version: 2.0.0
# Date: 2026-03-10
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
#   zbk -WindowsUser "$MC_WINDOWS_USER"                           # dry run (delta report only)
#   zbk -WindowsUser "$MC_WINDOWS_USER" -Execute                  # selective hydrate + copy
#   zbk -WindowsUser "$MC_WINDOWS_USER" -Execute -Mirror          # mirror (deletes extras)
#   zbk -WindowsUser "$MC_WINDOWS_USER" -Execute -SkipHydrate     # skip hydration (robocopy hydrates inline)
#   zbk -WindowsUser "$MC_WINDOWS_USER" -Execute -SingleThread:$false  # multithreaded copy
#
# Debug - single file placeholder check:
#   [System.IO.File]::GetAttributes("C:\path\to\file") -band 0x00400000
#
# Debug - single directory robocopy test:
#   robocopy "C:\Users\$env:USERNAME\MIT Dropbox\Luis Martinez\zotero-storage\SomeDir" "$env:TEMP\robocopy_test" /COPY:DAT /FFT /R:2 /W:5
#
# Test results (2026-03-04):
#   Test A (robocopy hydrates placeholders): PASSED - full content copied, not stub
#   Test B (exit code accessible): PASSED - Int32, code 1 on dry run
#   Test C (bracket filenames): PASSED - robocopy handles them natively
#
# Test results (2026-03-10):
#   Test D (Get-ChildItem -LiteralPath unicode paths): PASSED - non-ASCII filenames parsed correctly
#   Test E (selective hydration 302 files): PASSED - 0 errors, all delta files hydrated
#   Test F (robocopy exit 3 on copy+extras): PASSED - correctly interpreted as success
#
# Destructive operations:
#   - Hydration (Step 5): downloads cloud files to local disk, consumes C: space
#   - Robocopy /E (Step 7): writes files to backup drive, never deletes
#   - Robocopy /MIR (Step 7): writes files AND deletes extras from backup drive

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
    -Execute             Perform real hydration and copy (default is dry run)
    -Mirror              Enable /MIR - deletes extras from destination (requires -Execute)
    -SkipHydrate         Skip selective hydration; robocopy hydrates files inline
    -SingleThread        Use /MT:1 (default: true, safest for first run)
    -LogPath <path>      Robocopy log file (default: ~/zotero_backup.log)
SAFETY:
    Default is dry run. No files hydrated, copied, or deleted without -Execute.
    -Mirror deletes files from destination - requires -Execute.
    Hydration downloads delta files to local disk - consumes C: space.
EXAMPLES:
    # Dry run (see delta - what would be hydrated and copied):
    .\Backup-ZoteroStorage.ps1 -WindowsUser Luised94
    # Real backup - selective hydrate + copy:
    .\Backup-ZoteroStorage.ps1 -WindowsUser Luised94 -Execute
    # Mirror run - sync and delete extras:
    .\Backup-ZoteroStorage.ps1 -WindowsUser Luised94 -Execute -Mirror
    # Skip hydration (spacious machine, robocopy hydrates inline):
    .\Backup-ZoteroStorage.ps1 -WindowsUser Luised94 -Execute -SkipHydrate
    # Fast multithreaded copy:
    .\Backup-ZoteroStorage.ps1 -WindowsUser Luised94 -Execute -SingleThread:`$false
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
$SourceDir   = "C:\Users\$WindowsUser\MIT Dropbox\$DropboxUser\zotero-storage"
$FolderName  = Split-Path $SourceDir -Leaf
$MarkerFile  = "backup_drive.txt"
$SourceDrive = $SourceDir.Substring(0, 1)

Write-Host "[INFO]  User:   $WindowsUser"
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
Write-Host "[INFO]  Environment validation passed"

# --- Step 3: Drive Detection ---
# Must occur before delta detection -- $DestDir is required by Get-Delta.
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
Write-Host "[INFO]  Destination:  $DestDir"

# Write test -- confirm drive is writable (state-changing, self-cleaning)
$TestFile = "$($DriveLetter):\zotero_backup_write_test_$(Get-Date -Format 'yyyyMMddHHmmss').tmp"
try {
    New-Item -Path $TestFile -ItemType File -Force | Out-Null
    Remove-Item -Path $TestFile -Force
} catch {
    Write-Host "[ERROR] Backup drive is not writable: $($DriveLetter):\" -ForegroundColor Red
    exit 1
}
Write-Host "[INFO]  Drive writable"

# --- Step 4: Delta Detection ---
# Enumerates source and destination natively via Get-ChildItem (-LiteralPath throughout
# to handle Unicode and bracket characters in filenames). Compares by size and timestamp
# with a 2-second tolerance (matches robocopy /FFT behavior). Files where source is older
# than destination are skipped, matching robocopy default behavior.
Write-Host "[INFO]  Enumerating source..."
$SrcFiles = Get-ChildItem -LiteralPath $SourceDir -Recurse -File -ErrorAction SilentlyContinue

$SourceFileCount  = $SrcFiles.Count
$SourceTotalBytes = ($SrcFiles | Measure-Object -Property Length -Sum).Sum
Write-Host "[INFO]  Source: $SourceFileCount files, $([math]::Round($SourceTotalBytes / 1GB, 2)) GB"

Write-Host "[INFO]  Enumerating destination..."
$DestFilesExisting = @()
$DestExists = Test-Path -LiteralPath $DestDir
if ($DestExists) {
    $DestFilesExisting = Get-ChildItem -LiteralPath $DestDir -Recurse -File -ErrorAction SilentlyContinue
}

# Index destination files by relative path for O(1) lookup
$DestIndex = @{}
foreach ($F in $DestFilesExisting) {
    $Rel = $F.FullName.Substring($DestDir.Length).TrimStart('\')
    $DestIndex[$Rel] = $F
}

Write-Host "[INFO]  Comparing source and destination..."
$Delta = [System.Collections.Generic.List[PSCustomObject]]::new()
foreach ($F in $SrcFiles) {
    $Rel      = $F.FullName.Substring($SourceDir.Length).TrimStart('\')
    $DestFile = $DestIndex[$Rel]

    if ($null -eq $DestFile) {
        $Status = 'New File'
    } elseif ($F.Length -ne $DestFile.Length) {
        $Status = 'Changed'
    } elseif (($F.LastWriteTimeUtc - $DestFile.LastWriteTimeUtc).TotalSeconds -gt 2) {
        $Status = 'Newer'
    } else {
        continue
    }

    $Delta.Add([PSCustomObject]@{
        Status = $Status
        Bytes  = $F.Length
        Path   = $F.FullName
    })
}

$DeltaFileCount  = $Delta.Count
$DeltaTotalBytes = ($Delta | Measure-Object -Property Bytes -Sum).Sum

Write-Host "[INFO]  Delta: $DeltaFileCount files, $([math]::Round($DeltaTotalBytes / 1GB, 2)) GB"
$Delta | Group-Object Status | ForEach-Object {
    $GB = [math]::Round(($_.Group | Measure-Object -Property Bytes -Sum).Sum / 1GB, 2)
    Write-Host ("[INFO]    {0,-10} {1,6} files   {2,8} GB" -f $_.Name, $_.Count, $GB)
}

if ($DeltaFileCount -eq 0) {
    Write-Host "[INFO]  Source and destination are in sync -- nothing to do"
    exit 0
}

# --- Step 5: Disk Space Check ---
$SourceVolume  = Get-Volume -DriveLetter $SourceDrive
$DestVolume    = Get-Volume -DriveLetter $DriveLetter
$SourceFreeBytes = $SourceVolume.SizeRemaining
$DestFreeBytes   = $DestVolume.SizeRemaining

Write-Host "[INFO]  Source drive ($($SourceDrive):): $([math]::Round($SourceFreeBytes / 1GB, 2)) GB free"
Write-Host "[INFO]  Backup drive ($($DriveLetter):): $([math]::Round($DestFreeBytes / 1GB, 2)) GB free"

# Source drive: warn if free space is less than 120% of delta size.
# (Delta files will be hydrated to C: before copy.)
if ($SourceFreeBytes -lt ($DeltaTotalBytes * 1.2)) {
    Write-Host "[WARN]  Source drive may not have enough space to hydrate delta ($([math]::Round($DeltaTotalBytes / 1GB, 2)) GB)" -ForegroundColor Yellow
}

# Backup drive: hard gate on first run; warn on incremental.
if (-not $DestExists -and $DestFreeBytes -lt $SourceTotalBytes) {
    Write-Host "[ERROR] First backup requires ~$([math]::Round($SourceTotalBytes / 1GB, 2)) GB but drive has $([math]::Round($DestFreeBytes / 1GB, 2)) GB free" -ForegroundColor Red
    exit 1
} elseif ($DestExists -and $DestFreeBytes -lt ($DeltaTotalBytes * 1.1)) {
    Write-Host "[WARN]  Backup drive has less than 10% headroom for delta ($([math]::Round($DeltaTotalBytes / 1GB, 2)) GB)" -ForegroundColor Yellow
}
Write-Host "[INFO]  Disk space ok"

# --- Step 6: Selective Hydration ---
# Hydrates only the delta files (New File, Newer, Changed) -- not the full corpus.
# Skipped entirely in dry run mode (-Execute not set) since hydration is state-changing.
# Skipped if -SkipHydrate is set (robocopy will hydrate files inline during copy).
if (-not $Execute) {
    Write-Host "[INFO]  Skipping hydration (dry run -- use -Execute to hydrate and copy)"
} elseif ($SkipHydrate) {
    Write-Host "[INFO]  Skipping hydration (-SkipHydrate -- robocopy will hydrate inline)"
} else {
    Write-Host "[INFO]  Hydrating $DeltaFileCount delta files..."
    $HydrateAttempted = 0
    $HydrateFail      = 0
    $HydrateErrors    = [System.Collections.Generic.List[string]]::new()

    foreach ($File in $Delta) {
        $HydrateAttempted++
        try {
            Get-Content -LiteralPath $File.Path -TotalCount 1 -ErrorAction Stop | Out-Null
        } catch {
            $HydrateFail++
            $HydrateErrors.Add($File.Path)
            Write-Host "[WARN]  Hydration failed: $($File.Path)" -ForegroundColor Yellow
        }
        if ($HydrateAttempted % 50 -eq 0) {
            Write-Host "[INFO]  $HydrateAttempted / $DeltaFileCount hydrated..."
        }
    }
    Write-Host "[INFO]  Hydration: $HydrateAttempted attempted, $($HydrateAttempted - $HydrateFail) ok, $HydrateFail failed"

    if ($HydrateFail -gt 0) {
        Write-Host "[ERROR] $HydrateFail delta files failed hydration -- aborting" -ForegroundColor Red
        foreach ($Path in $HydrateErrors) { Write-Host "[ERROR]   $Path" -ForegroundColor Red }
        exit 1
    }

    # --- Step 6a: Hydration Validation ---
    # Confirms every delta file is now local (RECALL_ON_DATA_ACCESS clear).
    # Scoped to delta files only -- non-delta files remain as placeholders intentionally.
    Write-Host "[INFO]  Validating delta files are local..."
    $StillPlaceholder = [System.Collections.Generic.List[string]]::new()
    foreach ($File in $Delta) {
        try {
            $Attrs = [System.IO.File]::GetAttributes($File.Path)
            if ($Attrs -band 0x00400000) {
                $StillPlaceholder.Add($File.Path)
            }
        } catch {
            Write-Host "[WARN]  Could not read attributes: $($File.Path)" -ForegroundColor Yellow
        }
    }
    if ($StillPlaceholder.Count -gt 0) {
        Write-Host "[ERROR] $($StillPlaceholder.Count) delta files still show as placeholders after hydration" -ForegroundColor Red
        foreach ($Path in $StillPlaceholder | Select-Object -First 10) {
            Write-Host "[ERROR]   $Path" -ForegroundColor Red
        }
        if ($StillPlaceholder.Count -gt 10) {
            Write-Host "[ERROR]   ... and $($StillPlaceholder.Count - 10) more" -ForegroundColor Red
        }
        exit 1
    }
    Write-Host "[INFO]  Hydration validation passed: all delta files are local"
}

# --- Step 7: Robocopy ---
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
    Write-Host "[INFO]  DRY RUN - no files will be hydrated, copied, or deleted"
}

if ($SingleThread) {
    $RobocopyArgs += "/MT:1"
} else {
    $RobocopyArgs += "/MT:8"
}

$RobocopyArgs += "/LOG+:$LogPath"
$RobocopyArgs += "/TEE"

$RunTimestamp = Get-Date -Format "yyyy-MM-ddTHH:mm:ss"
$Delimiter    = "========== RUN: $RunTimestamp | USER: $WindowsUser | MODE: $Mode =========="
Add-Content -Path $LogPath -Value "`n$Delimiter"

Write-Host "[INFO]  Mode: $Mode | Threads: $(if ($SingleThread) {'1'} else {'8'}) | Log: $LogPath"
Write-Host "[INFO]  Running robocopy..."
robocopy @RobocopyArgs
$RobocopyExitCode = $LASTEXITCODE

# --- Step 8: Robocopy Result ---
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

if ($RobocopyExitCode -ge 8) { exit 1 }

# --- Step 9: Post-Copy Reconciliation ---
# Skipped in dry run -- no files were copied.
if (-not $Execute) {
    Write-Host "[INFO]  Skipping reconciliation (dry run)"
    exit 0
}

Write-Host "[INFO]  Reconciling source and destination..."
$DestFilesPost  = Get-ChildItem -LiteralPath $DestDir -Recurse -File -ErrorAction SilentlyContinue
$DestFileCount  = $DestFilesPost.Count
$DestTotalBytes = ($DestFilesPost | Measure-Object -Property Length -Sum).Sum

Write-Host "[INFO]  Source:      $SourceFileCount files, $([math]::Round($SourceTotalBytes / 1GB, 2)) GB"
Write-Host "[INFO]  Destination: $DestFileCount files, $([math]::Round($DestTotalBytes / 1GB, 2)) GB"

if ($DestFileCount -lt $SourceFileCount) {
    $Missing = $SourceFileCount - $DestFileCount
    Write-Host "[WARN]  Destination has $Missing fewer files than source -- some files may have failed to copy" -ForegroundColor Yellow
    Write-Host "[WARN]  Check log for errors: $LogPath" -ForegroundColor Yellow
} elseif ($DestFileCount -eq $SourceFileCount) {
    Write-Host "[INFO]  Reconciliation passed: counts match ($SourceFileCount files)"
} else {
    $Extras = $DestFileCount - $SourceFileCount
    Write-Host "[INFO]  Destination has $Extras extra files not in source"
    if (-not $Mirror) {
        Write-Host "[INFO]  Use -Execute -Mirror to remove extras from destination"
    }
}

Write-Host "[INFO]  Complete: $DestDir"
exit 0
