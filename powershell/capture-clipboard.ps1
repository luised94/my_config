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
# VERSION 3.1 NOTES AND CONCERNS
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
#   5. STATE IS IN-MEMORY. Captures append to disk immediately (crash-safe for
#      the body), but the "which page is open" state lives only in this session.
#      Close the terminal mid-page and you must re-run Complete manually or the
#      frontmatter keeps its placeholder count. The body is intact regardless.
#   6. DUPLICATE DETECTION IS EXACT-MATCH ONLY. A re-copied section is flagged
#      only if byte-identical (after newline normalization) to an earlier
#      capture this page. Near-duplicates are not detected. Warn, never block.
#   7. FRONTMATTER FIELD NAMES ARE LITERAL IN THREE PLACES that must stay in
#      sync: the two write blocks (Start and Complete) and the read regexes in
#      Start. Change a field name in one and update the others. See the sync
#      comments at each site.
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
# The same marker string opens and closes the line.
$global:CaptureDelimiterMarker    = "@@@"
$global:CaptureDelimiterLabel     = "capture"
$global:CaptureDelimiterNoteLabel = "note:"

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
        Write-Warning ("A page is already open: {0}. Run Complete-PageCapture first, or that page stays half-finished." -f $global:CurrentCaptureFilePath)
        return
    }

    if (-not (Test-Path -LiteralPath $global:CaptureOutputFolder)) {
        New-Item -ItemType Directory -Path $global:CaptureOutputFolder | Out-Null
    }

    # Across-page duplicate check: warn (never block) if an existing file's
    # frontmatter title or source matches what we're about to capture.
    # SYNC: these two regexes read the field names written by the frontmatter
    # blocks below and in Complete-PageCapture. Keep 'title:' / 'source:' aligned.
    if ($Title -ne "" -or $Source -ne "") {
        $ExistingFiles = Get-ChildItem -LiteralPath $global:CaptureOutputFolder -File -Filter $global:PageFileListingGlob -ErrorAction SilentlyContinue
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
    $NumberedFiles = Get-ChildItem -LiteralPath $global:CaptureOutputFolder -File -Filter $global:PageFileListingGlob -ErrorAction SilentlyContinue
    foreach ($NumberedFile in $NumberedFiles) {
        $NumberMatch = [regex]::Match($NumberedFile.Name, $global:PageFileNumberRegex)
        if ($NumberMatch.Success) {
            $ThisFileNumber = [int]$NumberMatch.Groups[1].Value
            if ($ThisFileNumber -gt $HighestFileNumber) { $HighestFileNumber = $ThisFileNumber }
        }
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
    # the read regexes above. Left literal by design (templating YAML earns little).
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
        Write-Warning "No page open. Run Start-PageCapture first."
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
        Write-Host "Last capture: (none yet)"
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


function Complete-PageCapture {
    param([switch]$Help)
    Write-Host "Usage: Complete-PageCapture   (rewrites frontmatter with final count/timestamp, closes the page)"
    if ($Help) { return }

    if (-not $global:CurrentCaptureFilePath) {
        Write-Warning "No page open. Nothing to complete."
        return
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
    # regexes in Start. Left literal by design.
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
