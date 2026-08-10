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
#       Also warns if any incomplete (never-Completed) page files are found.
#
#   Add-ClipboardCapture [-Note "<branch label>"]           (FAST path)
#       Appends current clipboard text to the open page. Warns if the text is
#       byte-identical to ANY earlier capture on this page (accidental re-copy
#       while navigating branches). -Note is optional and lands in the capture's
#       delimiter line so you can mark branch boundaries as you go.
#
#   Add-ClipboardCaptureWithReview                          (REVIEW path)
#       Shows the clipboard, asks y/n, then delegates to Add-ClipboardCapture.
#       Use while testing; switch to the fast path once confident.
#
#   Show-CaptureStatus
#       Prints the open page's file path, title/source, capture count, bytes so
#       far, and a head+tail preview of the last capture. Use this to see where
#       you are after navigating up/down, before the next copy.
#
#   Complete-PageCapture
#       Rewrites frontmatter with the final capture_count and finish timestamp,
#       then closes the page so the next Start-PageCapture begins clean.
#
#   Resume-PageCapture -FileName <page-NNN.md>
#       Reopens an incomplete page file (one whose captured_finish is empty --
#       e.g. the terminal was closed mid-page, or Complete was forgotten) as the
#       session's current page, so you can keep capturing and then Complete it.
#
#   Abandon-PageCapture
#       Deletes the currently open page file and clears session state, after a
#       confirmation prompt. Use when a page was started by mistake. To discard
#       an orphan from a dead terminal: Resume it, then Abandon it.
#
#   Any command with -Help prints just its usage line.
#
# TYPICAL SESSION
#   . .\capture-clipboard.ps1
#   Start-PageCapture -Title "How to reset the widget" -Source "https://app/threads/482"
#   Add-ClipboardCapture                      # after each copy button
#   Add-ClipboardCapture -Note "branch-A"     # mark a branch boundary
#   Show-CaptureStatus                        # check where you are
#   Complete-PageCapture
#
# RECOVERY (forgot to Complete, or closed the terminal mid-page)
#   Start-PageCapture will warn and list incomplete files. To continue one:
#       Resume-PageCapture -FileName page-003.md
#       Add-ClipboardCapture ...   # numbering continues from the existing count
#       Complete-PageCapture
#   To discard it instead: Resume-PageCapture -FileName page-003.md; Abandon-PageCapture
#
# RECOMMENDED WINDOW SETUP (reduces the back-and-forth of a long page)
#   - Snap the source interface and this PowerShell window side by side:
#       Win+Left  snaps the active window to the left half
#       Win+Right snaps the active window to the right half
#   - Alt+Tab switches between the two without touching the mouse.
#   - Keep this window focused-enough that after each copy you press Up then
#     Enter to re-run the last Add-ClipboardCapture (PowerShell command history).
#   - For branching content: finish one branch fully, then navigate back and
#     walk the next branch. Use -Note at each branch boundary so the linear file
#     stays navigable afterward.
#
# OUTPUT
#   Files land in $CaptureOutputFolder (set in CONFIGURATION below), one flat
#   folder, named page-001.md, page-002.md, ... auto-numbered from the highest
#   existing. Files are UTF-8 without BOM.
#   Attachments are handled manually, outside this script: download them and
#   save alongside as page-NNN-attachments.zip (or a page-NNN-attachments\
#   folder if a zip download is not offered).
#
# VERSION 3.2 NOTES AND CONCERNS
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
#      once could both pick the same page-NNN number. Out of scope.
#   5. INCOMPLETE PAGES ARE RECOVERABLE. Captures append to disk immediately, so
#      the body is never lost. If Complete is skipped (terminal closed, forgot),
#      the file keeps its placeholder frontmatter (empty captured_finish). Start
#      detects and warns; Resume-PageCapture reopens it to finish or Abandon.
#   6. DUPLICATE DETECTION IS EXACT-MATCH ONLY. A re-copied section is flagged
#      only if byte-identical (after newline normalization) to an earlier
#      capture this page. Near-duplicates are not detected. Warn, never block.
#   7. FRONTMATTER FIELD NAMES ARE LITERAL IN SEVERAL PLACES that must stay in
#      sync: the write blocks (Start, Complete) and the read regexes (Start's
#      dup/orphan checks, Resume). Change a field name in one and update all.
#      See the SYNC comments at each site.
#   8. AFTER RESUME, DEDUP AND PREVIEW ARE PARTIAL. Resume rebuilds the capture
#      count (from delimiter lines) reliably, but NOT the per-capture hashes or
#      last-capture text -- so duplicate detection and Show-CaptureStatus's
#      preview cover only captures added after the resume, not earlier ones.
# =============================================================================


# =============================================================================
# CONFIGURATION -- edit these to change output location, naming, format, markers
# =============================================================================

# Output folder. GetFolderPath('Desktop') resolves the REAL desktop even under
# OneDrive Known Folder redirection; "$HOME\Desktop" would create a wrong second
# folder that is not the one shown in Explorer.
$global:CaptureOutputFolderName = "clipboard-page-captures"
$global:CaptureOutputFolder     = Join-Path ([Environment]::GetFolderPath('Desktop')) $global:CaptureOutputFolderName

# Page file naming. The write format, listing glob, and number-parsing regex are
# all DERIVED from the three primitives below so they cannot drift out of sync.
# Change a primitive and all three follow automatically.
$global:PageFileNamePrefix     = "page-"
$global:PageFileExtension      = ".md"
$global:PageFileNumberPadWidth = 3
$global:PageFileNameFormat     = $global:PageFileNamePrefix + "{0:D$($global:PageFileNumberPadWidth)}" + $global:PageFileExtension
$global:PageFileListingGlob    = $global:PageFileNamePrefix + "*" + $global:PageFileExtension
$global:PageFileNumberRegex    = '^' + [regex]::Escape($global:PageFileNamePrefix) + '(\d+)' + [regex]::Escape($global:PageFileExtension) + '$'

# Timestamp format for captured_start, captured_finish, and delimiter lines.
$global:TimestampFormat = "yyyy-MM-ddTHH:mm:ss"

# Capture delimiter line. Produces, e.g.:
#   @@@ capture 3 2025-01-15T14:22:01 @@@
#   @@@ capture 3 2025-01-15T14:22:01 note: branch-A @@@
# The same marker string opens and closes the line. The line regex (used by
# Resume to count existing captures) is DERIVED from the marker and label so it
# cannot drift from the builder.
$global:CaptureDelimiterMarker    = "@@@"
$global:CaptureDelimiterLabel     = "capture"
$global:CaptureDelimiterNoteLabel = "note:"
$global:CaptureDelimiterLineRegex = '(?m)^' + [regex]::Escape($global:CaptureDelimiterMarker) + '\s+' + [regex]::Escape($global:CaptureDelimiterLabel) + '\s+(\d+)\b'

# Head+tail preview size (characters) shown by Show-CaptureStatus.
$global:LastCapturePreviewCharacterCount = 200


# =============================================================================
# SESSION STATE for the page currently being assembled
# =============================================================================
$global:CurrentCaptureFilePath    = $null
$global:CurrentCaptureFileNumber  = $null
$global:CurrentPageTitle          = $null
$global:CurrentPageSource         = $null
$global:CurrentPageStartTimestamp = $null
$global:CurrentPageCaptureCount   = 0
$global:LastCaptureText           = $null    # text of most recent capture, for Show-CaptureStatus
$global:AllCaptureHashesThisPage  = @()      # SHA256 of every capture this page, for exact-match dedup


function Start-PageCapture {
    param(
        [string]$Title  = "",
        [string]$Source = "",
        [switch]$Help
    )
    Write-Host "Usage: Start-PageCapture [-Title '<page title>'] [-Source '<url or origin>']"
    if ($Help) { return }

    if ($global:CurrentCaptureFilePath) {
        Write-Warning ("A page is already open: {0}. Complete or Abandon it first." -f $global:CurrentCaptureFilePath)
        return
    }

    if (-not (Test-Path -LiteralPath $global:CaptureOutputFolder)) {
        New-Item -ItemType Directory -Path $global:CaptureOutputFolder | Out-Null
    }

    # Single pass over existing page files: find the highest number (for the next
    # filename), warn on title/source duplicates, and collect incomplete orphans.
    # NOTE: this reads every file's content on every Start (needed for the orphan
    # check). Fine at this scale; revisit only if the folder grows very large.
    # SYNC: the title/source/captured_finish read regexes must match the field
    # names written by the frontmatter blocks below and in Complete-PageCapture.
    $HighestFileNumber   = 0
    $IncompleteFileNames = @()
    $AllPageFiles = Get-ChildItem -LiteralPath $global:CaptureOutputFolder -File -Filter $global:PageFileListingGlob -ErrorAction SilentlyContinue
    foreach ($PageFile in $AllPageFiles) {
        $NumberMatch = [regex]::Match($PageFile.Name, $global:PageFileNumberRegex)
        if ($NumberMatch.Success) {
            $ThisFileNumber = [int]$NumberMatch.Groups[1].Value
            if ($ThisFileNumber -gt $HighestFileNumber) { $HighestFileNumber = $ThisFileNumber }
        }

        $ExistingText = [System.IO.File]::ReadAllText($PageFile.FullName, [System.Text.Encoding]::UTF8)

        $FinishMatch = [regex]::Match($ExistingText, "(?m)^captured_finish:\s*(.*)$")
        if ($FinishMatch.Success -and $FinishMatch.Groups[1].Value.Trim() -eq "") {
            $IncompleteFileNames += $PageFile.Name
        }

        if ($Title -ne "" -or $Source -ne "") {
            $TitleMatch  = [regex]::Match($ExistingText, "(?m)^title:\s*'(.*)'\s*$")
            $SourceMatch = [regex]::Match($ExistingText, "(?m)^source:\s*'(.*)'\s*$")
            $ExistingTitle  = if ($TitleMatch.Success)  { $TitleMatch.Groups[1].Value  -replace "''","'" } else { "" }
            $ExistingSource = if ($SourceMatch.Success) { $SourceMatch.Groups[1].Value -replace "''","'" } else { "" }
            if (($Title  -ne "" -and $ExistingTitle  -ieq $Title) -or
                ($Source -ne "" -and $ExistingSource -ieq $Source)) {
                Write-Warning ("Possible duplicate of existing file {0} (title/source match). Proceeding with a new file anyway." -f $PageFile.Name)
            }
        }
    }
    if ($IncompleteFileNames.Count -gt 0) {
        Write-Warning ("Incomplete page file(s) found (never Completed): {0}. Use Resume-PageCapture -FileName <name> to continue one, then Complete or Abandon it." -f ($IncompleteFileNames -join ", "))
    }
    $global:CurrentCaptureFileNumber = $HighestFileNumber + 1

    $FileName = $global:PageFileNameFormat -f $global:CurrentCaptureFileNumber
    $global:CurrentCaptureFilePath    = Join-Path $global:CaptureOutputFolder $FileName
    $global:CurrentPageTitle          = $Title
    $global:CurrentPageSource         = $Source
    $global:CurrentPageStartTimestamp = (Get-Date).ToString($global:TimestampFormat)
    $global:CurrentPageCaptureCount   = 0
    $global:LastCaptureText           = $null
    $global:AllCaptureHashesThisPage  = @()

    # Frontmatter written now with placeholder count / empty finish; rewritten
    # by Complete-PageCapture. File is on disk immediately so a crash loses nothing.
    # SYNC: field names / '---' fences here must match the block in Complete and
    # the read regexes in Start and Resume. Left literal by design.
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

    Write-Host ("Started {0} (file_number {1})." -f $FileName, $global:CurrentCaptureFileNumber)
    Write-Host "Next: Add-ClipboardCapture after each copy  |  Show-CaptureStatus to check  |  Complete-PageCapture when done."
}


function Add-ClipboardCapture {
    param(
        [string]$Note = "",
        [switch]$Help
    )
    Write-Host "Usage: Add-ClipboardCapture [-Note '<branch label>']   (appends current clipboard text to the open page)"
    if ($Help) { return }

    if (-not $global:CurrentCaptureFilePath) {
        Write-Warning "No page open. Run Start-PageCapture (or Resume-PageCapture) first."
        return
    }

    $CapturedText = Get-Clipboard -Raw
    if ($null -eq $CapturedText -or $CapturedText.Trim() -eq "") {
        Write-Warning "Clipboard is empty. Nothing appended."
        return
    }

    # Normalize to LF so files stay consistent for python/R/bash/nvim.
    $CapturedText = $CapturedText -replace "`r`n","`n" -replace "`r","`n"

    # Exact-match dedup across ALL captures this page (not just the previous one),
    # because up/down navigation of branches makes re-copying an earlier section
    # the real risk. Warn, never block -- shared text across branches is valid.
    $Sha256 = [System.Security.Cryptography.SHA256]::Create()
    $CaptureHash = [BitConverter]::ToString($Sha256.ComputeHash([System.Text.Encoding]::UTF8.GetBytes($CapturedText)))
    $Sha256.Dispose()
    $PriorIndex = [array]::IndexOf($global:AllCaptureHashesThisPage, $CaptureHash)
    if ($PriorIndex -ge 0) {
        Write-Warning ("This clipboard is byte-identical to capture {0} earlier this page. Appending anyway - check for an accidental re-copy." -f ($PriorIndex + 1))
    }

    # A newline in the note would split the single-line delimiter and corrupt the
    # audit marker, so collapse any CR/LF in the note to spaces.
    $CleanNote = $Note -replace "`r`n"," " -replace "`r"," " -replace "`n"," "

    $global:CurrentPageCaptureCount = $global:CurrentPageCaptureCount + 1
    $Timestamp = (Get-Date).ToString($global:TimestampFormat)
    if ($CleanNote -ne "") {
        $DelimiterLine = "{0} {1} {2} {3} {4} {5} {0}" -f $global:CaptureDelimiterMarker, $global:CaptureDelimiterLabel, $global:CurrentPageCaptureCount, $Timestamp, $global:CaptureDelimiterNoteLabel, $CleanNote
    } else {
        $DelimiterLine = "{0} {1} {2} {3} {0}" -f $global:CaptureDelimiterMarker, $global:CaptureDelimiterLabel, $global:CurrentPageCaptureCount, $Timestamp
    }

    $Utf8NoBom = New-Object System.Text.UTF8Encoding($false)
    [System.IO.File]::AppendAllText($global:CurrentCaptureFilePath, "`n" + $DelimiterLine + "`n" + $CapturedText + "`n", $Utf8NoBom)

    $global:LastCaptureText          = $CapturedText
    $global:AllCaptureHashesThisPage += $CaptureHash
    if ($CleanNote -ne "") {
        Write-Host ("Appended capture {0} ({1} chars, note: {2})." -f $global:CurrentPageCaptureCount, $CapturedText.Length, $CleanNote)
    } else {
        Write-Host ("Appended capture {0} ({1} chars)." -f $global:CurrentPageCaptureCount, $CapturedText.Length)
    }
}


function Add-ClipboardCaptureWithReview {
    param(
        [string]$Note = "",
        [switch]$Help
    )
    Write-Host "Usage: Add-ClipboardCaptureWithReview [-Note '<branch label>']   (shows clipboard, asks to confirm, then appends)"
    if ($Help) { return }

    if (-not $global:CurrentCaptureFilePath) {
        Write-Warning "No page open. Run Start-PageCapture (or Resume-PageCapture) first."
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
        Add-ClipboardCapture -Note $Note   # append logic lives in one place only
    } else {
        Write-Host "Skipped. Nothing appended."
    }
}


function Show-CaptureStatus {
    param([switch]$Help)
    Write-Host "Usage: Show-CaptureStatus   (prints the open page's state and a preview of the last capture)"
    if ($Help) { return }

    if (-not $global:CurrentCaptureFilePath) {
        Write-Warning "No page open. Run Start-PageCapture (or Resume-PageCapture) first."
        return
    }

    $CurrentBytes = if (Test-Path -LiteralPath $global:CurrentCaptureFilePath) { (Get-Item -LiteralPath $global:CurrentCaptureFilePath).Length } else { 0 }

    Write-Host ("File:     {0}" -f $global:CurrentCaptureFilePath)
    Write-Host ("Title:    {0}" -f $global:CurrentPageTitle)
    Write-Host ("Source:   {0}" -f $global:CurrentPageSource)
    Write-Host ("Started:  {0}" -f $global:CurrentPageStartTimestamp)
    Write-Host ("Captures: {0}" -f $global:CurrentPageCaptureCount)
    Write-Host ("Bytes:    {0}" -f $CurrentBytes)

    if ($null -eq $global:LastCaptureText) {
        Write-Host "Last capture: (none yet this session; note: preview is empty right after a Resume)"
        return
    }

    # Head+tail preview so you can confirm which section landed last without
    # dumping a large capture into the console.
    Write-Host "----- last capture preview -----"
    if ($global:LastCaptureText.Length -le (2 * $global:LastCapturePreviewCharacterCount)) {
        Write-Host $global:LastCaptureText
    } else {
        Write-Host $global:LastCaptureText.Substring(0, $global:LastCapturePreviewCharacterCount)
        Write-Host ("... [{0} chars omitted] ..." -f ($global:LastCaptureText.Length - (2 * $global:LastCapturePreviewCharacterCount)))
        Write-Host $global:LastCaptureText.Substring($global:LastCaptureText.Length - $global:LastCapturePreviewCharacterCount)
    }
    Write-Host "----- end preview -----"
}


function Resume-PageCapture {
    param(
        [string]$FileName = "",
        [switch]$Help
    )
    Write-Host "Usage: Resume-PageCapture -FileName <page-NNN.md>   (reopens an incomplete page file to keep capturing)"
    if ($Help) { return }

    if ($global:CurrentCaptureFilePath) {
        Write-Warning ("A page is already open: {0}. Complete or Abandon it before resuming another." -f $global:CurrentCaptureFilePath)
        return
    }

    if ($FileName -eq "") {
        Write-Warning "Provide -FileName, e.g. Resume-PageCapture -FileName page-003.md"
        return
    }

    $ResumePath = Join-Path $global:CaptureOutputFolder $FileName
    if (-not (Test-Path -LiteralPath $ResumePath)) {
        Write-Warning ("File not found: {0}" -f $ResumePath)
        return
    }

    # The filename is authoritative for the page number; refuse a nonconforming
    # name because we could not number subsequent captures/files consistently.
    $NumberMatch = [regex]::Match($FileName, $global:PageFileNumberRegex)
    if (-not $NumberMatch.Success) {
        Write-Warning ("'{0}' does not match the page file naming pattern; cannot resume it safely." -f $FileName)
        return
    }
    $ResumedFileNumber = [int]$NumberMatch.Groups[1].Value

    $ResumeText = [System.IO.File]::ReadAllText($ResumePath, [System.Text.Encoding]::UTF8)

    # SYNC: these read regexes must match the frontmatter field names written in
    # Start-PageCapture and Complete-PageCapture.
    $TitleMatch  = [regex]::Match($ResumeText, "(?m)^title:\s*'(.*)'\s*$")
    $SourceMatch = [regex]::Match($ResumeText, "(?m)^source:\s*'(.*)'\s*$")
    $StartMatch  = [regex]::Match($ResumeText, "(?m)^captured_start:\s*(.*)$")
    $FinishMatch = [regex]::Match($ResumeText, "(?m)^captured_finish:\s*(.*)$")

    $ResumedTitle  = if ($TitleMatch.Success)  { $TitleMatch.Groups[1].Value  -replace "''","'" } else { "" }
    $ResumedSource = if ($SourceMatch.Success) { $SourceMatch.Groups[1].Value -replace "''","'" } else { "" }
    # captured_start should always be present (our own Start writes it); fall back
    # to the file's creation time only if the frontmatter was hand-mangled.
    $ResumedStart  = if ($StartMatch.Success -and $StartMatch.Groups[1].Value.Trim() -ne "") { $StartMatch.Groups[1].Value.Trim() } else { (Get-Item -LiteralPath $ResumePath).CreationTime.ToString($global:TimestampFormat) }

    if ($FinishMatch.Success -and $FinishMatch.Groups[1].Value.Trim() -ne "") {
        Write-Warning "This file was already completed (captured_finish is set). Reopening to add more captures; Complete-PageCapture will refresh it when done."
    }

    # Capture count = number of delimiter lines already in the body. This is the
    # value that must be right so the next capture is numbered correctly and the
    # final capture_count is accurate. (Per-capture hashes / last-capture text are
    # NOT reconstructed -- see note 8 in the header.)
    $ExistingCaptureCount = ([regex]::Matches($ResumeText, $global:CaptureDelimiterLineRegex)).Count

    $global:CurrentCaptureFilePath    = $ResumePath
    $global:CurrentCaptureFileNumber  = $ResumedFileNumber
    $global:CurrentPageTitle          = $ResumedTitle
    $global:CurrentPageSource         = $ResumedSource
    $global:CurrentPageStartTimestamp = $ResumedStart
    $global:CurrentPageCaptureCount   = $ExistingCaptureCount
    $global:LastCaptureText           = $null   # preview empty until the next capture
    $global:AllCaptureHashesThisPage  = @()     # dedup covers only captures added after resume

    Write-Host ("Resumed {0}: {1} existing capture(s), next will be capture {2}." -f $FileName, $ExistingCaptureCount, ($ExistingCaptureCount + 1))
    Write-Warning "Duplicate detection and the status preview cover only captures added from now on; earlier captures on this page are not compared."
}


function Abandon-PageCapture {
    param([switch]$Help)
    Write-Host "Usage: Abandon-PageCapture   (deletes the open page file and clears session state)"
    if ($Help) { return }

    if (-not $global:CurrentCaptureFilePath) {
        Write-Warning "No page open. Nothing to abandon."
        return
    }

    $AbandonPath = $global:CurrentCaptureFilePath
    $AbandonName = Split-Path $AbandonPath -Leaf
    $Answer = Read-Host ("Delete {0} ({1} capture(s)) and discard it? (y/n)" -f $AbandonName, $global:CurrentPageCaptureCount)
    if (-not ($Answer -ieq "y")) {
        Write-Host "Kept. Nothing deleted."
        return
    }

    if (Test-Path -LiteralPath $AbandonPath) {
        Remove-Item -LiteralPath $AbandonPath
    }

    $global:CurrentCaptureFilePath    = $null
    $global:CurrentCaptureFileNumber  = $null
    $global:CurrentPageTitle          = $null
    $global:CurrentPageSource         = $null
    $global:CurrentPageStartTimestamp = $null
    $global:CurrentPageCaptureCount   = 0
    $global:LastCaptureText           = $null
    $global:AllCaptureHashesThisPage  = @()

    Write-Host ("Abandoned {0}: file deleted, session cleared." -f $AbandonName)
}


function Complete-PageCapture {
    param([switch]$Help)
    Write-Host "Usage: Complete-PageCapture   (rewrites frontmatter with final count/timestamp, closes the page)"
    if ($Help) { return }

    if (-not $global:CurrentCaptureFilePath) {
        Write-Warning "No page open. Nothing to complete."
        return
    }

    # Gap 6: the open file may have been deleted externally since it was opened.
    # Clear state and bail rather than throw on ReadAllText.
    if (-not (Test-Path -LiteralPath $global:CurrentCaptureFilePath)) {
        Write-Warning ("The open page file no longer exists at {0}. Clearing session state; nothing written." -f $global:CurrentCaptureFilePath)
        $global:CurrentCaptureFilePath    = $null
        $global:CurrentCaptureFileNumber  = $null
        $global:CurrentPageTitle          = $null
        $global:CurrentPageSource         = $null
        $global:CurrentPageStartTimestamp = $null
        $global:CurrentPageCaptureCount   = 0
        $global:LastCaptureText           = $null
        $global:AllCaptureHashesThisPage  = @()
        return
    }

    if ($global:CurrentPageCaptureCount -eq 0) {
        Write-Warning "This page has no captures. Completing will leave an empty stub file. Consider Abandon-PageCapture instead."
    }

    $FinishTimestamp = (Get-Date).ToString($global:TimestampFormat)

    # Strip the placeholder frontmatter (exactly the first ---...--- block) and
    # keep the body untouched, even if the body itself contains --- lines.
    # SYNC: the '---' fence here matches the frontmatter blocks. Left literal.
    $Utf8NoBom = New-Object System.Text.UTF8Encoding($false)
    $FullText  = [System.IO.File]::ReadAllText($global:CurrentCaptureFilePath, [System.Text.Encoding]::UTF8)
    $BodyText  = [regex]::Replace($FullText, "(?s)^---\n.*?\n---\n", "")
    $BodyText  = $BodyText.TrimStart("`n")

    # SYNC: field names / '---' fences must match the block in Start and the read
    # regexes in Start and Resume. Left literal by design.
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
    $global:LastCaptureText           = $null
    $global:AllCaptureHashesThisPage  = @()

    Write-Host ("Completed {0}: {1} captures, {2} bytes." -f (Split-Path $CompletedPath -Leaf), $CompletedCount, $CompletedBytes)
    Write-Host ("Saved in: {0}" -f $global:CaptureOutputFolder)
}
