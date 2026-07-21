# STATUS: COMPLETED SPIKE PENDING (thread 2). Run once on the target machine.
# Report-only. Verifies the mover's INPUT CONTRACT and triages the orphan
# list before Move-OrphanFiles.ps1 exists. Findings go into
# handoff/02_orphan_pipeline.md. Re-run only to re-confirm on a new host.
# =============================================================================
# SPIKE S2c: ORPHAN LIST READ + TRIAGE (Windows PowerShell 5.1)
# =============================================================================
# Version: 1.0
# Purpose: Two things, both read-only:
#   (1) Contract test for the mover. Confirm Windows PowerShell 5.1 reads
#       orphans.txt correctly -- UTF-8 WITH BOM (ID2), CRLF, containing
#       non-ASCII paths (~9% of this library, S2) -- with the BOM stripped
#       and accented/CJK/Hebrew characters intact. If this fails, the mover's
#       read strategy must change before it is written.
#   (2) Triage. Bucket the orphans by filename pattern so the owner knows how
#       many are confidently-safe superseded copies vs how many want a manual
#       look, WITHOUT moving anything. Motivated by the full-run finding that
#       orphans are mostly old-naming-scheme leftovers and Dropbox conflict
#       copies (handoff/02, run 2026-07).
# Usage:   Windows PowerShell 5.1. From WSL:
#            powershell.exe -NoProfile -ExecutionPolicy Bypass \
#              -File "$(wslpath -w .../spikes/Spike-S2c-OrphanListReadAndTriage.ps1)" \
#              -RunFolder "C:\Users\<you>\Zotero\orphan_audit\<stamp>"
#          Or pass -OrphansPath directly to a orphans.txt.
# Safety:  READ-ONLY. Reads orphans.txt and, for a bounded spot-check sample,
#          calls Test-Path (metadata only; does NOT hydrate Dropbox
#          placeholders -- it never opens file contents). Moves/deletes
#          nothing. This is a spike, not the mover.
# Output:  Prints a summary and a per-bucket sample to the console.
# =============================================================================

param(
    [string]$RunFolder,
    [string]$OrphansPath,
    [int]$SpotCheckCount = 50,
    [int]$SamplePerBucket = 5,
    [switch]$BypassVersionCheck
)

$ErrorActionPreference = "Stop"

# --- Version guard (ID3): this contract is verified only on PS 5.1 ----------
$ver = $PSVersionTable.PSVersion
if (-not $BypassVersionCheck -and ($ver.Major -ne 5 -or $ver.Minor -ne 1)) {
    Write-Host "[ERROR] This spike verifies the Windows PowerShell 5.1 read contract." -ForegroundColor Red
    Write-Host "[ERROR] Detected PowerShell $ver. Default encoding and Get-Content" -ForegroundColor Red
    Write-Host "[ERROR] behavior differ on other majors (incl. PS 7). Re-verify there" -ForegroundColor Red
    Write-Host "[ERROR] before trusting the mover. Use -BypassVersionCheck to override." -ForegroundColor Red
    exit 1
}
Write-Host "[INFO]  PowerShell $ver"

# --- Resolve the orphans list -----------------------------------------------
if (-not $OrphansPath) {
    if (-not $RunFolder) {
        Write-Host "[ERROR] Provide -RunFolder (the orphan_audit run dir) or -OrphansPath." -ForegroundColor Red
        exit 1
    }
    $OrphansPath = Join-Path $RunFolder "orphans.txt"
}
if (-not (Test-Path -LiteralPath $OrphansPath)) {
    Write-Host "[ERROR] orphans.txt not found: $OrphansPath" -ForegroundColor Red
    exit 1
}
Write-Host "[INFO]  Reading: $OrphansPath"

# --- (1) CONTRACT TEST ------------------------------------------------------
# Raw byte peek: confirm the UTF-8 BOM (EF BB BF) is present, as the auditor
# writes it (ID2). Get-Content -Encoding UTF8 on PS 5.1 strips this BOM.
$firstBytes = [System.IO.File]::ReadAllBytes($OrphansPath) | Select-Object -First 3
$hasBom = ($firstBytes.Count -ge 3 -and $firstBytes[0] -eq 0xEF -and `
           $firstBytes[1] -eq 0xBB -and $firstBytes[2] -eq 0xBF)
Write-Host "[TEST]  UTF-8 BOM present in file: $hasBom (expected True)"

$lines = @(Get-Content -LiteralPath $OrphansPath -Encoding UTF8 |
           Where-Object { $_.Trim().Length -gt 0 })
Write-Host "[INFO]  Non-empty lines read: $($lines.Count)"

# BOM must not survive into the first string (would corrupt the first path).
$bomLeak = $false
if ($lines.Count -gt 0) {
    $bomLeak = $lines[0][0] -eq [char]0xFEFF
}
Write-Host "[TEST]  BOM leaked into first line: $bomLeak (expected False)"

# Non-ASCII survival: count lines with any codepoint above U+007F and show a
# few so the owner can eyeball that accents/CJK/Hebrew read intact.
$nonAscii = @($lines | Where-Object { $_ -match '[^\u0000-\u007F]' })
Write-Host "[TEST]  Lines containing non-ASCII characters: $($nonAscii.Count) (expected > 0 for this library)"
if ($nonAscii.Count -gt 0) {
    Write-Host "[INFO]  Non-ASCII path examples (verify characters look correct):"
    $nonAscii | Select-Object -First $SamplePerBucket | ForEach-Object { Write-Host "          $_" }
}

# Decisive display-vs-data check. A mangled CONSOLE rendering (e.g.
# "Alegr[..]a" for "Alegria") is only a codepage DISPLAY issue if the
# in-memory string still resolves on disk. Test-Path a bounded non-ASCII
# sample: all-present => display-only, and the mover is safe using
# -LiteralPath. Any absent => the read itself corrupted the bytes; STOP and
# fix encoding before the mover moves anything.
$naSample = @($nonAscii | Select-Object -First $SpotCheckCount)
$naPresent = 0
$naAbsent = 0
$naAbsentList = New-Object System.Collections.ArrayList
foreach ($p in $naSample) {
    if (Test-Path -LiteralPath $p) { $naPresent++ } else { $naAbsent++; [void]$naAbsentList.Add($p) }
}
Write-Host "[TEST]  Non-ASCII resolution ($($naSample.Count) paths): present $naPresent, absent $naAbsent"
if ($naAbsent -gt 0) {
    Write-Host "[TEST]  DATA CORRUPTION: some non-ASCII paths do NOT resolve --" -ForegroundColor Red
    Write-Host "[TEST]  console mangling is not display-only. Fix read encoding before the mover." -ForegroundColor Red
    $naAbsentList | Select-Object -First 5 | ForEach-Object { Write-Host "          MISSING: $_" }
} elseif ($naSample.Count -gt 0) {
    Write-Host "[TEST]  Non-ASCII mangling is DISPLAY-ONLY (all sampled non-ASCII paths resolve)." -ForegroundColor Green
    Write-Host "[TEST]  Mover is safe on non-ASCII paths with -LiteralPath." -ForegroundColor Green
}

$contractOk = $hasBom -and (-not $bomLeak) -and ($lines.Count -gt 0) -and ($naAbsent -eq 0)
Write-Host "[TEST]  CONTRACT: $(if ($contractOk) { 'PASS' } else { 'FAIL -- fix before writing the mover' })" `
    -ForegroundColor $(if ($contractOk) { 'Green' } else { 'Red' })

# --- (2) TRIAGE -------------------------------------------------------------
# Heuristic buckets (NOT authoritative -- for owner review, not for automated
# action). A single path can only fall in the first bucket it matches.
$bOcrPageImage = New-Object System.Collections.ArrayList  # page-NNN.png OCR-my-PDF litter
$bConflictCopy = New-Object System.Collections.ArrayList  # "... 2.pdf", "... 3.pdf" (Dropbox/OS copies)
$bClippedExt   = New-Object System.Collections.ArrayList  # ".epu" and other clipped extensions
$bLowerName    = New-Object System.Collections.ArrayList  # lowercase-surname old scheme
$bNoYear       = New-Object System.Collections.ArrayList  # no _YYYY_ token (missing-date items)
$bResidual     = New-Object System.Collections.ArrayList  # everything else

foreach ($line in $lines) {
    $leaf = Split-Path -Path $line -Leaf
    # OCR page images first: "page-001.png" / "page_1.jpg" etc. These are
    # OCR-my-PDF output that sits beside the one real (matched) PDF; the
    # leaf is lowercase, so without this bucket they hide in lowercase-name
    # (confirmed by the Legouve folder: 1 PDF + ~393 page-NNN.png).
    if ($leaf -match '^page[-_]?\d+\.(png|jpe?g|tiff?|gif|bmp)$') {
        [void]$bOcrPageImage.Add($line)
    }
    elseif ($leaf -match ' \d+\.[A-Za-z0-9]+$') {
        [void]$bConflictCopy.Add($line)
    }
    elseif ($leaf -match '\.(epu|pd|htm|epub_|ep)$') {
        [void]$bClippedExt.Add($line)
    }
    elseif ($leaf -cmatch '^[a-z]') {
        [void]$bLowerName.Add($line)
    }
    elseif ($leaf -notmatch '_(19|20)\d{2}_') {
        [void]$bNoYear.Add($line)
    }
    else {
        [void]$bResidual.Add($line)
    }
}

function Show-Bucket {
    param([string]$Name, $Items, [int]$Sample)
    Write-Host ""
    Write-Host "[BUCKET] $Name : $($Items.Count)"
    $Items | Select-Object -First $Sample | ForEach-Object { Write-Host "          $_" }
}
Show-Bucket -Name "ocr-page-image (page-NNN.png OCR litter; safe)"        -Items $bOcrPageImage -Sample $SamplePerBucket
Show-Bucket -Name "conflict-copy ( N before ext; safe superseded copies)" -Items $bConflictCopy -Sample $SamplePerBucket
Show-Bucket -Name "clipped-extension (.epu etc; verify vs matched twins)"  -Items $bClippedExt   -Sample $SamplePerBucket
Show-Bucket -Name "lowercase-name (old naming scheme; likely superseded)"  -Items $bLowerName    -Sample $SamplePerBucket
Show-Bucket -Name "no-year (missing-date items; check before quarantine)"  -Items $bNoYear       -Sample $SamplePerBucket
Show-Bucket -Name "residual (no obvious pattern; manual review)"           -Items $bResidual     -Sample $SamplePerBucket

# --- Spot-check existence (metadata only; no hydration) ---------------------
# Confirms the listed paths resolve on this machine, catching path-encoding or
# separator problems before the mover relies on them. Bounded sample only.
$sample = $lines | Select-Object -First $SpotCheckCount
$present = 0
$absent  = 0
foreach ($s in $sample) {
    if (Test-Path -LiteralPath $s) { $present++ } else { $absent++ }
}
Write-Host ""
Write-Host "[TEST]  Spot-check ($($sample.Count) paths): present $present, absent $absent"
Write-Host "        (all-absent would signal a path/encoding mismatch -- investigate before moving)"

# --- Summary ----------------------------------------------------------------
Write-Host ""
Write-Host "[SUMMARY]"
Write-Host "  contract_pass    : $contractOk"
Write-Host "  total_orphans    : $($lines.Count)"
Write-Host "  non_ascii_lines  : $($nonAscii.Count)"
Write-Host "  non_ascii_resolve: $naPresent / $($naSample.Count) (absent $naAbsent)"
Write-Host "  ocr_page_image   : $($bOcrPageImage.Count)"
Write-Host "  conflict_copy    : $($bConflictCopy.Count)"
Write-Host "  clipped_ext      : $($bClippedExt.Count)"
Write-Host "  lowercase_name   : $($bLowerName.Count)"
Write-Host "  no_year          : $($bNoYear.Count)"
Write-Host "  residual         : $($bResidual.Count)"
Write-Host "  spotcheck_present: $present / $($sample.Count)"
