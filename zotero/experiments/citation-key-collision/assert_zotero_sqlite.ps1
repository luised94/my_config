# Asserts zotero.sqlite exists under the CURRENT device's Windows profile.
# Uses $env:USERPROFILE so it is device-independent (never a hardcoded user).
# Emits size in bytes and mtime as UTC Unix epoch seconds (integer) --
# locale-independent and cross-device comparable, unlike a formatted date.
$ErrorActionPreference = "Stop"
$ZoteroDataDirectory = Join-Path $env:USERPROFILE "Zotero"
$SqlitePath = Join-Path $ZoteroDataDirectory "zotero.sqlite"

if (-not (Test-Path -LiteralPath $SqlitePath)) {
    Write-Error "FAIL: zotero.sqlite not found at $SqlitePath"
    exit 1
}
$SqliteItem = Get-Item -LiteralPath $SqlitePath
if ($SqliteItem.Length -le 0) {
    Write-Error "FAIL: zotero.sqlite exists but is zero bytes at $SqlitePath"
    exit 1
}
$MtimeEpochSeconds = [DateTimeOffset]::new($SqliteItem.LastWriteTimeUtc).ToUnixTimeSeconds()

Write-Output "zotero_data_directory=$ZoteroDataDirectory"
Write-Output "sqlite_path=$SqlitePath"
Write-Output "sqlite_size_bytes=$($SqliteItem.Length)"
Write-Output "sqlite_mtime_epoch_utc=$MtimeEpochSeconds"
