# =============================================================================
# capture-clipboard.ps1  --  manual clipboard-to-file page capture
# =============================================================================
#
# PURPOSE
#   Assemble one Markdown file per page/thread from multiple manual clipboard
#   copies. You click a copy button in the source interface, then run a command
#   here that appends the clipboard text to the page file currently open.
#
# LOAD (once per PowerShell session -- functions share session state)
#   . .\capture-clipboard.ps1
#
# WORKFLOW
#   Start-PageCapture -Title "<page title>" -Source "<url or origin>"
#       Creates the next page-NNN.md file and writes placeholder frontmatter.
#       -Title and -Source are optional. If given, warns (never blocks) when an
#       existing file's frontmatter title/source matches -- possible duplicate.
#
#   Add-ClipboardCapture                 (FAST path)
#       Appends current clipboard text to the open page. Warns if the text is
#       byte-identical to the previous capture (likely an accidental double).
#
#   Add-ClipboardCaptureWithReview       (REVIEW path -- use while testing)
#       Shows the clipboard, asks y/n, then delegates to Add-ClipboardCapture.
#
#   Complete-PageCapture
#       Rewrites frontmatter with the final capture_count and finish timestamp,
#       then closes the page so the next Start-PageCapture begins clean.
#
#   Any command with -Help prints just its usage line.
#
# TYPICAL SESSION
#   . .\capture-clipboard.ps1
#   Start-PageCapture -Title "How to reset the widget" -Source "https://app/threads/482"
#   Add-ClipboardCapture        # after each copy button
#   Add-ClipboardCapture
#   Complete-PageCapture
#
# OUTPUT
#   Files land in $CaptureOutputFolder (set just below), one flat folder,
#   named page-001.md, page-002.md, ... auto-numbered from the highest existing.
#   Files are UTF-8 without BOM.
#
# VERSION 1 NOTES AND CONCERNS
#   1. NEWLINE NORMALIZATION IS A REAL MUTATION. Captured text has CRLF/CR
#      converted to LF for consistency across python/R/bash/nvim. This is the
#      one place your copied content is altered. Remove the normalization line
#      in Add-ClipboardCapture if you need bytes verbatim.
#   2. FRONTMATTER IS REWRITTEN WHOLESALE FROM SESSION STATE at Complete, not
#      merged. Do not hand-edit a file's frontmatter before completing it --
#      those edits are lost. Edit only after completion.
#   3. FORMATTING IS DISCARDED. Get-Clipboard -Raw pulls plain text only; rich
#      text / HTML formatting from the copy button is not preserved (by design).
#   4. SINGLE SESSION ASSUMED. Two PowerShell sessions running these commands at
#      once could both pick the same page-NNN number. Out of scope for v1.
#   5. STATE IS IN-MEMORY. Captures append to disk immediately (crash-safe for
#      the body), but the "which page is open" state lives only in this session.
#      Close the terminal mid-page and you must re-run Complete manually or the
#      frontmatter keeps its placeholder count. The body is intact regardless.
# =============================================================================


# --- EDIT THIS: where captured page files are written ------------------------
# GetFolderPath('Desktop') resolves the REAL desktop even when OneDrive Known
# Folder redirection is on; "$HOME\Desktop" would create a wrong second folder.
$global:CaptureOutputFolder = Join-Path ([Environment]::GetFolderPath('Desktop')) "clipboard-page-captures"


# --- session state for the page currently being assembled -------------------
$global:CurrentCaptureFilePath    = $null
$global:CurrentCaptureFileNumber  = $null
$global:CurrentPageTitle          = $null
$global:CurrentPageSource         = $null
$global:CurrentPageStartTimestamp = $null
$global:CurrentPageCaptureCount   = 0
$global:PreviousCaptureText       = $null


function Start-PageCapture {
    param(
        [string]$Title  = "",
        [string]$Source = "",
        [switch]$Help
    )
    Write-Host "Usage: Start-PageCapture [-Title '<page title>'] [-Source '<url or origin>']"
    if ($Help) { return }

    if ($global:CurrentCaptureFilePath) {
        Write-Warning ("A page is already open: {0}. Run Complete-PageCapture first, or that page stays half-finished." -f $global:CurrentCaptureFilePath)
        return
    }

    if (-not (Test-Path -LiteralPath $global:CaptureOutputFolder)) {
        New-Item -ItemType Directory -Path $global:CaptureOutputFolder | Out-Null
    }

    # Across-page duplicate check: warn (never block) if an existing file's
    # frontmatter title or source matches what we're about to capture.
    if ($Title -ne "" -or $Source -ne "") {
        $ExistingFiles = Get-ChildItem -LiteralPath $global:CaptureOutputFolder -File -Filter 'page-*.md' -ErrorAction SilentlyContinue
        foreach ($ExistingFile in $ExistingFiles) {
            $ExistingText = [System.IO.File]::ReadAllText($ExistingFile.FullName, [System.Text.Encoding]::UTF8)
            $TitleMatch  = [regex]::Match($ExistingText, "(?m)^title:\s*'(.*)'\s*$")
            $SourceMatch = [regex]::Match($ExistingText, "(?m)^source:\s*'(.*)'\s*$")
            $ExistingTitle  = if ($TitleMatch.Success)  { $TitleMatch.Groups[1].Value  -replace "''","'" } else { "" }
            $ExistingSource = if ($SourceMatch.Success) { $SourceMatch.Groups[1].Value -replace "''","'" } else { "" }
            if (($Title  -ne "" -and $ExistingTitle  -ieq $Title) -or
                ($Source -ne "" -and $ExistingSource -ieq $Source)) {
                Write-Warning ("Possible duplicate of existing file {0} (title/source match). Proceeding with a new file anyway." -f $ExistingFile.Name)
            }
        }
    }

    # Auto-number: highest existing page-NNN + 1.
    $HighestFileNumber = 0
    $NumberedFiles = Get-ChildItem -LiteralPath $global:CaptureOutputFolder -File -Filter 'page-*.md' -ErrorAction SilentlyContinue
    foreach ($NumberedFile in $NumberedFiles) {
        $NumberMatch = [regex]::Match($NumberedFile.Name, '^page-(\d+)\.md$')
        if ($NumberMatch.Success) {
            $ThisFileNumber = [int]$NumberMatch.Groups[1].Value
            if ($ThisFileNumber -gt $HighestFileNumber) { $HighestFileNumber = $ThisFileNumber }
        }
    }
    $global:CurrentCaptureFileNumber = $HighestFileNumber + 1

    $FileName = "page-{0:D3}.md" -f $global:CurrentCaptureFileNumber
    $global:CurrentCaptureFilePath    = Join-Path $global:CaptureOutputFolder $FileName
    $global:CurrentPageTitle          = $Title
    $global:CurrentPageSource         = $Source
    $global:CurrentPageStartTimestamp = (Get-Date).ToString("yyyy-MM-ddTHH:mm:ss")
    $global:CurrentPageCaptureCount   = 0
    $global:PreviousCaptureText       = $null

    # Frontmatter written now with placeholder count / empty finish; rewritten
    # by Complete-PageCapture. File is on disk immediately so a crash loses nothing.
    $TitleYaml  = "'" + ($Title  -replace "'","''") + "'"
    $SourceYaml = "'" + ($Source -replace "'","''") + "'"
    $Frontmatter = @(
        "---",
        "title: $TitleYaml",
        "source: $SourceYaml",
        "file_number: $($global:CurrentCaptureFileNumber)",
        "captured_start: $($global:CurrentPageStartTimestamp)",
        "captured_finish: ",
        "capture_count: 0",
        "---",
        ""
    ) -join "`n"

    $Utf8NoBom = New-Object System.Text.UTF8Encoding($false)
    [System.IO.File]::WriteAllText($global:CurrentCaptureFilePath, $Frontmatter + "`n", $Utf8NoBom)

    Write-Host ("Started {0} (file_number {1}). Now Add-ClipboardCapture per copy, then Complete-PageCapture." -f $FileName, $global:CurrentCaptureFileNumber)
}


function Add-ClipboardCapture {
    param([switch]$Help)
    Write-Host "Usage: Add-ClipboardCapture   (appends current clipboard text to the open page)"
    if ($Help) { return }

    if (-not $global:CurrentCaptureFilePath) {
        Write-Warning "No page open. Run Start-PageCapture first."
        return
    }

    $CapturedText = Get-Clipboard -Raw
    if ($null -eq $CapturedText -or $CapturedText.Trim() -eq "") {
        Write-Warning "Clipboard is empty. Nothing appended."
        return
    }

    # Normalize to LF so files stay consistent for python/R/bash/nvim.
    $CapturedText = $CapturedText -replace "`r`n","`n" -replace "`r","`n"

    # Within-page guard: identical to the last capture usually means the append
    # ran twice on one copy. Warn, but still append (real repeats can happen).
    if ($null -ne $global:PreviousCaptureText -and $CapturedText -eq $global:PreviousCaptureText) {
        Write-Warning "This clipboard is byte-identical to the previous capture. Appending anyway - check for an accidental double."
    }

    $global:CurrentPageCaptureCount = $global:CurrentPageCaptureCount + 1
    $Timestamp = (Get-Date).ToString("yyyy-MM-ddTHH:mm:ss")
    $DelimiterLine = "@@@ capture {0} {1} @@@" -f $global:CurrentPageCaptureCount, $Timestamp

    $Utf8NoBom = New-Object System.Text.UTF8Encoding($false)
    [System.IO.File]::AppendAllText($global:CurrentCaptureFilePath, "`n" + $DelimiterLine + "`n" + $CapturedText + "`n", $Utf8NoBom)

    $global:PreviousCaptureText = $CapturedText
    Write-Host ("Appended capture {0} ({1} chars)." -f $global:CurrentPageCaptureCount, $CapturedText.Length)
}


function Add-ClipboardCaptureWithReview {
    param([switch]$Help)
    Write-Host "Usage: Add-ClipboardCaptureWithReview   (shows clipboard, asks to confirm, then appends)"
    if ($Help) { return }

    if (-not $global:CurrentCaptureFilePath) {
        Write-Warning "No page open. Run Start-PageCapture first."
        return
    }

    $PreviewText = Get-Clipboard -Raw
    if ($null -eq $PreviewText -or $PreviewText.Trim() -eq "") {
        Write-Warning "Clipboard is empty. Nothing to review."
        return
    }

    Write-Host "----- clipboard preview -----"
    Write-Host $PreviewText
    Write-Host "----- end preview -----"
    $Answer = Read-Host "Append this to the open page? (y/n)"
    if ($Answer -ieq "y") {
        Add-ClipboardCapture   # append logic lives in one place only
    } else {
        Write-Host "Skipped. Nothing appended."
    }
}


function Complete-PageCapture {
    param([switch]$Help)
    Write-Host "Usage: Complete-PageCapture   (rewrites frontmatter with final count/timestamp, closes the page)"
    if ($Help) { return }

    if (-not $global:CurrentCaptureFilePath) {
        Write-Warning "No page open. Nothing to complete."
        return
    }

    $FinishTimestamp = (Get-Date).ToString("yyyy-MM-ddTHH:mm:ss")

    # Strip the placeholder frontmatter (exactly the first ---...--- block) and
    # keep the body untouched, even if the body itself contains --- lines.
    $Utf8NoBom = New-Object System.Text.UTF8Encoding($false)
    $FullText  = [System.IO.File]::ReadAllText($global:CurrentCaptureFilePath, [System.Text.Encoding]::UTF8)
    $BodyText  = [regex]::Replace($FullText, "(?s)^---\n.*?\n---\n", "")
    $BodyText  = $BodyText.TrimStart("`n")

    $TitleYaml  = "'" + ($global:CurrentPageTitle  -replace "'","''") + "'"
    $SourceYaml = "'" + ($global:CurrentPageSource -replace "'","''") + "'"
    $Frontmatter = @(
        "---",
        "title: $TitleYaml",
        "source: $SourceYaml",
        "file_number: $($global:CurrentCaptureFileNumber)",
        "captured_start: $($global:CurrentPageStartTimestamp)",
        "captured_finish: $FinishTimestamp",
        "capture_count: $($global:CurrentPageCaptureCount)",
        "---",
        ""
    ) -join "`n"

    [System.IO.File]::WriteAllText($global:CurrentCaptureFilePath, $Frontmatter + "`n" + $BodyText, $Utf8NoBom)

    $CompletedPath  = $global:CurrentCaptureFilePath
    $CompletedCount = $global:CurrentPageCaptureCount
    $CompletedBytes = (Get-Item -LiteralPath $CompletedPath).Length

    # Clear session state so the next Start-PageCapture begins clean.
    $global:CurrentCaptureFilePath    = $null
    $global:CurrentCaptureFileNumber  = $null
    $global:CurrentPageTitle          = $null
    $global:CurrentPageSource         = $null
    $global:CurrentPageStartTimestamp = $null
    $global:CurrentPageCaptureCount   = 0
    $global:PreviousCaptureText       = $null

    Write-Host ("Completed {0}: {1} captures, {2} bytes." -f (Split-Path $CompletedPath -Leaf), $CompletedCount, $CompletedBytes)
}
