param(
    [ValidateRange(1, 200)]
    [int]$Count = 15,

    [ValidateRange(100, 60000)]
    [int]$DelayMs = 1500,

    [ValidateRange(0, 30)]
    [int]$StartDelaySeconds = 5
)

Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

$baseFolder = Join-Path $env:USERPROFILE 'Pictures\PageCaptures'
$runFolder = Join-Path $baseFolder (Get-Date -Format 'yyyy-MM-dd_HH-mm-ss-fff')
New-Item -ItemType Directory -Path $runFolder -Force -ErrorAction Stop | Out-Null

function Save-PrimaryScreen {
    param([string]$Path)

    $bounds = [System.Windows.Forms.Screen]::PrimaryScreen.Bounds
    $bitmap = [System.Drawing.Bitmap]::new($bounds.Width, $bounds.Height)
    $graphics = $null
    try {
        $graphics = [System.Drawing.Graphics]::FromImage($bitmap)
        $graphics.CopyFromScreen($bounds.Location, [System.Drawing.Point]::Empty, $bounds.Size)
        $bitmap.Save($Path, [System.Drawing.Imaging.ImageFormat]::Png)
    }
    finally {
        if ($null -ne $graphics) { $graphics.Dispose() }
        $bitmap.Dispose()
    }
}

function Get-FileHashValue {
    param([string]$Path)
    return (Get-FileHash -LiteralPath $Path -Algorithm SHA256 -ErrorAction Stop).Hash
}

Write-Host "Saving up to $Count screenshots in: $runFolder"
Write-Host "Click the page now. Starting in $StartDelaySeconds seconds."
Write-Host 'To interrupt, focus the PowerShell window and press Ctrl+C.'
Start-Sleep -Seconds $StartDelaySeconds

$previousHash = $null
$allIdentical = $true
$unchangedTransitions = 0

for ($n = 1; $n -le $Count; $n++) {
    $path = Join-Path $runFolder ('page-{0:D3}.png' -f $n)
    Save-PrimaryScreen -Path $path
    $currentHash = Get-FileHashValue -Path $path
    Write-Host "Saved $path"

    if ($null -ne $previousHash) {
        if ($currentHash -eq $previousHash) {
            $unchangedTransitions++
            Write-Warning "No pixel changes between screenshots $($n - 1) and $n."
        }
        else {
            $allIdentical = $false
        }
    }
    $previousHash = $currentHash

    if ($n -lt $Count) {
        [System.Windows.Forms.SendKeys]::SendWait('{PGDN}')
        Start-Sleep -Milliseconds $DelayMs
    }
}

if ($Count -gt 1 -and $allIdentical) {
    Write-Warning "All $Count screenshots in this batch are byte-identical. Page Down may have reached the end, or the page may not have responded. Check the images."
}
elseif ($unchangedTransitions -gt 0) {
    Write-Warning "$unchangedTransitions of $($Count - 1) Page Down transitions showed no pixel change. Check the images for gaps or an endpoint."
}
else {
    Write-Host 'Every screenshot in this batch differed from the one before it.'
}

Write-Host "Batch complete. Files are in: $runFolder"
