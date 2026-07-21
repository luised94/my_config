<#
=============================================================================
MOVE ORPHAN FILES
=============================================================================
Version: 1.0.0
Date:    2026-07
Purpose: Consume a reviewed orphans.txt from an audit_orphan_attachments.js
         run and quarantine each listed file -- Move-Item (rename) into a
         dated subfolder of a "zotero-orphans" directory that sits BESIDE
         "zotero-storage", preserving relative structure. This is the
         destroy half of the D2 detect/destroy split. It MOVES, never
         deletes, so restore is a reverse move; and it stays on the same
         volume, so the move is a metadata rename that never hydrates a
         Dropbox online-only placeholder (S2b, VERIFIED_ENVIRONMENT.md).

Design:  handoff/02_orphan_pipeline.md (D2, ID1-ID7). Input contract
         verified by spikes/Spike-S2c-OrphanListReadAndTriage.ps1:
         orphans.txt is UTF-8 with BOM, CRLF, ~9% non-ASCII paths that
         resolve correctly under -LiteralPath (mojibake in the console is
         display-only). run_summary.json is UTF-8 without BOM.

Interface (ID1): -RunFolder points at one orphan_audit run directory. The
         base path and run stamp are read from that run's run_summary.json;
         the file list is read from orphans.txt in the same folder. No
         Windows username is ever passed or reconstructed -- the audit
         output is the single source of truth (ID: username automation).

Safety:  Dry-run by DEFAULT. Nothing moves without -Execute. The dry-run
         Test-Paths every source and reports any that do not resolve; it
         refuses to certify a run while unresolved sources remain, so the
         dry-run is itself the full-scale encoding proof. Per-file checks:
         containment (source must be inside the base), same-volume, and
         no-overwrite (an existing destination is skipped, never clobbered).
         Stale entries (source vanished since the audit) are counted and
         skipped with a warning; the run aborts only on the consecutive
         move-failure pattern (ID4). Every action is recorded to a manifest
         in the run folder for reversibility.

Host:    Windows PowerShell 5.1 ONLY (ID3, verified 5.1.x on both machines).
         Hard version gate; -BypassVersionCheck to override. Default
         encoding and Move-Item semantics are unverified on PS 7.

Usage (dry-run, from WSL):
  powershell.exe -NoProfile -ExecutionPolicy Bypass `
    -File "$(wslpath -w .../powershell/Move-OrphanFiles.ps1)" `
    -RunFolder "C:\Users\<you>\Zotero\orphan_audit\<stamp>"
Then review the dry-run manifest, optionally trim orphans.txt, and re-run
with -Execute to perform the moves.
=============================================================================
#>

# 1. PARAMETERS
param(
    [Parameter(Mandatory = $true)]
    [string]$RunFolder,
    [switch]$Execute,
    [string]$QuarantineName = "zotero-orphans",
    [int]$MaxConsecutiveFailures = 20,
    [switch]$BypassVersionCheck
)

$ErrorActionPreference = "Stop"
$mode = if ($Execute) { "execute" } else { "dryrun" }
$invocationStamp = Get-Date -Format "yyyy-MM-dd_HHmmss"

# 2. VERSION GATE (ID3)
$ver = $PSVersionTable.PSVersion
if (-not $BypassVersionCheck -and ($ver.Major -ne 5 -or $ver.Minor -ne 1)) {
    Write-Host "[ERROR] Move-OrphanFiles targets Windows PowerShell 5.1 (ID3)." -ForegroundColor Red
    Write-Host "[ERROR] Detected PowerShell $ver. Default encoding and Move-Item" -ForegroundColor Red
    Write-Host "[ERROR] semantics are unverified elsewhere (incl. PS 7). Re-verify" -ForegroundColor Red
    Write-Host "[ERROR] before trusting a move. Use -BypassVersionCheck to override." -ForegroundColor Red
    exit 1
}
Write-Host "[INFO]  PowerShell $ver ; mode: $mode"

# 3. HELPERS

# Comparison key ONLY (never used as a move target): unify separators, NFC,
# lowercase -- parallel to the auditor's normalizeKey so containment matches
# the same way the audit classified paths.
function Get-CompareKey {
    param([string]$Path)
    return $Path.Replace("/", "\").Normalize([System.Text.NormalizationForm]::FormC).ToLowerInvariant()
}

# Write lines as UTF-8 WITH BOM and CRLF (our verified read contract, ID2),
# so a future restore script reads the manifest exactly as it reads
# orphans.txt. WriteAllLines uses Environment.NewLine (CRLF on Windows).
function Write-Utf8BomLines {
    param([string]$Path, [string[]]$Lines)
    $enc = New-Object System.Text.UTF8Encoding($true)
    [System.IO.File]::WriteAllLines($Path, $Lines, $enc)
}

# 4. PRE-FLIGHT
if (-not (Test-Path -LiteralPath $RunFolder -PathType Container)) {
    Write-Host "[ERROR] Run folder not found: $RunFolder" -ForegroundColor Red
    exit 1
}
$summaryPath = Join-Path $RunFolder "run_summary.json"
$orphansPath = Join-Path $RunFolder "orphans.txt"
if (-not (Test-Path -LiteralPath $summaryPath)) {
    Write-Host "[ERROR] run_summary.json not found in run folder: $summaryPath" -ForegroundColor Red
    exit 1
}
if (-not (Test-Path -LiteralPath $orphansPath)) {
    Write-Host "[ERROR] orphans.txt not found in run folder: $orphansPath" -ForegroundColor Red
    exit 1
}

# run_summary.json is UTF-8 WITHOUT BOM (ID2).
$summary = Get-Content -LiteralPath $summaryPath -Raw -Encoding UTF8 | ConvertFrom-Json
$basePath = [string]$summary.basePath
$runStamp = [string]$summary.runStamp
if ([string]::IsNullOrWhiteSpace($basePath)) {
    Write-Host "[ERROR] basePath missing from run_summary.json." -ForegroundColor Red
    exit 1
}
if ($basePath.EndsWith("\") -or $basePath.EndsWith("/")) {
    $basePath = $basePath.Substring(0, $basePath.Length - 1)
}
if ([string]::IsNullOrWhiteSpace($runStamp)) {
    $runStamp = Split-Path -Leaf $RunFolder
}
if (-not (Test-Path -LiteralPath $basePath -PathType Container)) {
    Write-Host "[ERROR] Base path from run_summary.json does not exist here: $basePath" -ForegroundColor Red
    Write-Host "[ERROR] Are you on the machine that produced this audit?" -ForegroundColor Red
    exit 1
}
Write-Host "[INFO]  Base path : $basePath"

# Quarantine root: sibling of the base (outside it, so nothing re-adopts a
# moved file), same volume (metadata move, no hydration).
$baseParent = Split-Path -Parent $basePath
$quarantineBase = Join-Path $baseParent $QuarantineName
$quarantineRun = Join-Path $quarantineBase $runStamp
Write-Host "[INFO]  Quarantine: $quarantineRun"

$baseVolume = [System.IO.Path]::GetPathRoot($basePath)
$quarVolume = [System.IO.Path]::GetPathRoot($quarantineBase)
if ($baseVolume.ToLowerInvariant() -ne $quarVolume.ToLowerInvariant()) {
    Write-Host "[ERROR] Quarantine volume ($quarVolume) differs from base volume ($baseVolume)." -ForegroundColor Red
    Write-Host "[ERROR] A cross-volume move copies bytes and would hydrate placeholders. Aborting." -ForegroundColor Red
    exit 1
}
# Defensive: the quarantine must not live inside the base.
$baseKey = Get-CompareKey $basePath
$quarKey = Get-CompareKey $quarantineBase
if ($quarKey.StartsWith($baseKey + "\")) {
    Write-Host "[ERROR] Quarantine root is inside the base path. Refusing (would re-orphan)." -ForegroundColor Red
    exit 1
}

# orphans.txt is UTF-8 WITH BOM (ID2); the BOM is stripped by -Encoding UTF8.
$orphans = @(Get-Content -LiteralPath $orphansPath -Encoding UTF8 |
             Where-Object { $_.Trim().Length -gt 0 })
$auditOrphanCount = [int]$summary.counts.orphans
Write-Host "[INFO]  Orphan lines now: $($orphans.Count) (audit recorded: $auditOrphanCount)"
if ($orphans.Count -ne $auditOrphanCount) {
    Write-Host "[INFO]  Count differs from the audit -- expected if you trimmed orphans.txt during review." -ForegroundColor Yellow
}

if ($Execute) {
    Write-Host ""
    Write-Host "[EXECUTE] Files WILL be moved into the quarantine. This modifies your library on disk." -ForegroundColor Yellow
    Write-Host "[EXECUTE] (Reversible: every move is recorded to the manifest; restore is a reverse move.)" -ForegroundColor Yellow
    Write-Host ""
    if (-not (Test-Path -LiteralPath $quarantineRun)) {
        New-Item -ItemType Directory -Path $quarantineRun -Force | Out-Null
    } else {
        Write-Host "[WARN]  Quarantine run folder already exists; existing destinations will be skipped, not overwritten." -ForegroundColor Yellow
    }
}

# 5. MAIN LOOP
$manifest = New-Object System.Collections.ArrayList
[void]$manifest.Add("source`tdestination`tstatus")

$moved = 0
$wouldMove = 0
$skipMissing = 0
$skipCollision = 0
$skipContainment = 0
$failed = 0
$consecutiveFailures = 0
$aborted = $false
$failureSample = New-Object System.Collections.ArrayList
$processed = 0

foreach ($source in $orphans) {
    $processed++

    # Containment: the source must be inside the base (case-insensitive raw
    # prefix; the compare key confirms after separator/NFC folding).
    $srcKey = Get-CompareKey $source
    $inside = ($source.Length -gt ($basePath.Length + 1)) -and `
              ($srcKey.StartsWith($baseKey + "\"))
    if (-not $inside) {
        $skipContainment++
        [void]$manifest.Add("$source`t`tSKIP_CONTAINMENT")
        Write-Host "[WARN]  Not inside base, skipped: $source" -ForegroundColor Yellow
        continue
    }

    $relative = $source.Substring($basePath.Length + 1)
    $dest = Join-Path $quarantineRun $relative

    # Stale entry (ID4): source vanished since the audit. Count and skip;
    # this is NOT a move failure and does not trip the abort counter.
    if (-not (Test-Path -LiteralPath $source)) {
        $skipMissing++
        [void]$manifest.Add("$source`t$dest`tSKIP_MISSING")
        Write-Host "[WARN]  Source no longer exists, skipped: $source" -ForegroundColor Yellow
        continue
    }

    # No-overwrite: never clobber an existing destination.
    if (Test-Path -LiteralPath $dest) {
        $skipCollision++
        [void]$manifest.Add("$source`t$dest`tSKIP_COLLISION")
        Write-Host "[WARN]  Destination exists, skipped: $dest" -ForegroundColor Yellow
        continue
    }

    if (-not $Execute) {
        $wouldMove++
        [void]$manifest.Add("$source`t$dest`tWOULD_MOVE")
        continue
    }

    # Execute: ensure the destination's parent exists, then move (rename).
    try {
        $destParent = Split-Path -Parent $dest
        if (-not (Test-Path -LiteralPath $destParent)) {
            New-Item -ItemType Directory -Path $destParent -Force | Out-Null
        }
        Move-Item -LiteralPath $source -Destination $dest -ErrorAction Stop
        $moved++
        $consecutiveFailures = 0
        [void]$manifest.Add("$source`t$dest`tMOVED")
    } catch {
        $failed++
        $consecutiveFailures++
        [void]$manifest.Add("$source`t$dest`tFAILED: $($_.Exception.Message)")
        if ($failureSample.Count -lt 25) {
            [void]$failureSample.Add("$source :: $($_.Exception.Message)")
        }
        Write-Host "[ERROR] Move failed ($consecutiveFailures in a row): $source" -ForegroundColor Red
        Write-Host "        $($_.Exception.Message)" -ForegroundColor Red
        if ($consecutiveFailures -ge $MaxConsecutiveFailures) {
            $aborted = $true
            Write-Host "[ABORT] $MaxConsecutiveFailures consecutive move failures -- stopping (ID4)." -ForegroundColor Red
            break
        }
    }
}

# 6. WRITE MANIFEST (to the run folder, per decision)
$manifestName = "move_manifest_${mode}_${invocationStamp}.tsv"
$manifestPath = Join-Path $RunFolder $manifestName
Write-Utf8BomLines -Path $manifestPath -Lines $manifest.ToArray()
Write-Host ""
Write-Host "[INFO]  Manifest: $manifestPath"

# 7. SUMMARY
$accounted = $moved + $wouldMove + $skipMissing + $skipCollision + $skipContainment + $failed
Write-Host ""
Write-Host "[SUMMARY] mode=$mode aborted=$aborted"
Write-Host "  processed        : $processed / $($orphans.Count)"
Write-Host "  moved            : $moved"
Write-Host "  would_move       : $wouldMove"
Write-Host "  skip_missing     : $skipMissing"
Write-Host "  skip_collision   : $skipCollision"
Write-Host "  skip_containment : $skipContainment"
Write-Host "  failed           : $failed"
Write-Host "  accounted        : $accounted (should equal processed)"
if ($accounted -ne $processed) {
    Write-Host "[WARN]  Accounting does not close -- inspect the manifest." -ForegroundColor Yellow
}
if ($failureSample.Count -gt 0) {
    Write-Host "  failure sample:"
    $failureSample | ForEach-Object { Write-Host "    $_" -ForegroundColor Red }
}

if (-not $Execute) {
    $unresolved = $skipMissing + $skipContainment
    Write-Host ""
    if ($unresolved -eq 0) {
        Write-Host "[DRY-RUN] All $wouldMove sources resolve and are contained. Re-run with -Execute to move." -ForegroundColor Green
    } else {
        Write-Host "[DRY-RUN] $unresolved source(s) did not resolve or were out of base." -ForegroundColor Yellow
        Write-Host "[DRY-RUN] Investigate before -Execute (missing sources are usually harmless stale entries)." -ForegroundColor Yellow
    }
} else {
    if ($aborted) {
        Write-Host ""
        Write-Host "[DONE]  Aborted after $moved move(s). Fix the cause and re-run; already-moved files are skipped as collisions." -ForegroundColor Yellow
    } else {
        Write-Host ""
        Write-Host "[DONE]  Moved $moved file(s) to $quarantineRun" -ForegroundColor Green
        Write-Host "[DONE]  To restore: reverse the MOVED rows in the manifest." -ForegroundColor Green
    }
}
