#!/usr/bin/env bash
# Slice 1 drift-reconciliation gate.
#
# WHY THIS EXISTS: a fresh thread cannot see prior artifacts on the human's disk
# (they live in WSL, not the assistant's sandbox). This script is the code the
# HUMAN runs in WSL; its printed output is pasted back into the thread and is the
# only thing the assistant reconciles against. See the plan's "Who checks what".
#
# It reconciles the Slice 0 environment manifest against the live machine, then
# reports the LIVE zotero.sqlite identity. It deliberately does NOT halt on a
# changed live size/mtime: the library moved on since Slice 0, so drift there is
# EXPECTED. The frozen snapshot identity is captured later, by the copy step, from
# the copied file -- not from this live value. (Adversarial finding 8.)
#
# Run from anywhere. Reads only; touches nothing.
set -u

EXPERIMENT_DIRECTORY="$HOME/personal_repos/my_config/zotero/experiments/citation-key-collision"
MANIFEST_PATH="$EXPERIMENT_DIRECTORY/environment_manifest.primary.json"

# The Slice 0 carry-forward recorded these. The gate recomputes and compares the
# manifest's own identity so a corrupted/edited manifest is caught before its
# values are trusted. First-12 sha256 is the cross-thread anchor already in use.
EXPECTED_MANIFEST_SHA256_FIRST12="62d5d6bedce1"
EXPECTED_MANIFEST_SIZE_BYTES="711"

echo "== Slice 1 gate: reconciling Slice 0 manifest =="

if [ ! -f "$MANIFEST_PATH" ]; then
    echo "HALT: manifest not found at $MANIFEST_PATH"
    exit 1
fi

OBSERVED_MANIFEST_SHA256_FIRST12="$(sha256sum "$MANIFEST_PATH" | cut -c1-12)"
OBSERVED_MANIFEST_SIZE_BYTES="$(stat -c %s "$MANIFEST_PATH")"

echo "manifest_path=$MANIFEST_PATH"
echo "manifest_sha256_first12_observed=$OBSERVED_MANIFEST_SHA256_FIRST12 expected=$EXPECTED_MANIFEST_SHA256_FIRST12"
echo "manifest_size_bytes_observed=$OBSERVED_MANIFEST_SIZE_BYTES expected=$EXPECTED_MANIFEST_SIZE_BYTES"

if [ "$OBSERVED_MANIFEST_SHA256_FIRST12" != "$EXPECTED_MANIFEST_SHA256_FIRST12" ] \
   || [ "$OBSERVED_MANIFEST_SIZE_BYTES" != "$EXPECTED_MANIFEST_SIZE_BYTES" ]; then
    echo "HALT: manifest identity mismatch -- manifest was edited or corrupted since Slice 0."
    echo "      Do not proceed; hand back with status: halted."
    exit 1
fi
echo "manifest identity: OK"

# Reconcile the toolchain versions the manifest recorded. A changed uv/python
# means the environment drifted; the extractor was written against the recorded
# pair. We report, and hard-fail only on the major.minor of python (patch drift
# is fine; the .python-version pin is 3.12, reconcile on that, not the manifest
# patch string -- noted in the peruse).
echo "== toolchain reconcile =="
# Parse the manifest with python's json, not grep/cut: the manifest contains
# Windows paths with backslashes and quoted values, and a shell delimiter split
# cannot handle the escaping robustly (an earlier grep|cut version broke on the
# backslash-quote). python is already required downstream, so this adds nothing.
RECORDED_UV_VERSION="$(python3 -c "import json; print(json.load(open('$MANIFEST_PATH'))['uv_version'])")"
RECORDED_PYTHON_VERSION="$(python3 -c "import json; print(json.load(open('$MANIFEST_PATH'))['python_version'])")"
OBSERVED_UV_VERSION="$(uv --version 2>/dev/null | awk '{print $2}')"
OBSERVED_PYTHON_VERSION="$(cd "$EXPERIMENT_DIRECTORY" && uv run python -c 'import platform; print(platform.python_version())' 2>/dev/null)"

echo "uv_version_recorded=$RECORDED_UV_VERSION observed=${OBSERVED_UV_VERSION:-MISSING}"
echo "python_version_recorded=$RECORDED_PYTHON_VERSION observed=${OBSERVED_PYTHON_VERSION:-MISSING}"

RECORDED_PYTHON_MAJOR_MINOR="$(echo "$RECORDED_PYTHON_VERSION" | cut -d. -f1,2)"
OBSERVED_PYTHON_MAJOR_MINOR="$(echo "$OBSERVED_PYTHON_VERSION" | cut -d. -f1,2)"
if [ "$RECORDED_PYTHON_MAJOR_MINOR" != "$OBSERVED_PYTHON_MAJOR_MINOR" ]; then
    echo "HALT: python major.minor drifted ($RECORDED_PYTHON_MAJOR_MINOR -> $OBSERVED_PYTHON_MAJOR_MINOR)."
    exit 1
fi
echo "toolchain: OK (patch-level uv/python drift, if any, is acceptable)"

# Report the LIVE zotero data dir + sqlite identity. This is INFORMATIONAL.
# The recorded Slice 0 mtime (1787165115) is from live probing and is now stale;
# a different value here is expected, not a halt. The frozen identity comes from
# the COPY, captured by slice1_cold_copy.ps1, not from this live file.
echo "== live zotero.sqlite identity (informational; drift here is expected) =="
RECORDED_DATA_DIR="$(python3 -c "import json; print(json.load(open('$MANIFEST_PATH'))['zotero_data_directory'])")"
echo "zotero_data_directory_recorded=$RECORDED_DATA_DIR"

# Ask Windows for the live file's identity via the same PowerShell-from-WSL bridge
# Slice 0 verified. Uses $env:USERPROFILE on the Windows side (device-independent).
powershell.exe -NoProfile -Command '
    $dataDir = Join-Path $env:USERPROFILE "Zotero"
    $sqlite = Join-Path $dataDir "zotero.sqlite"
    $wal = Join-Path $dataDir "zotero.sqlite-wal"
    if (-not (Test-Path -LiteralPath $sqlite)) { Write-Output "HALT: live zotero.sqlite not found at $sqlite"; exit 1 }
    $item = Get-Item -LiteralPath $sqlite
    $mtime = [DateTimeOffset]::new($item.LastWriteTimeUtc).ToUnixTimeSeconds()
    Write-Output "live_sqlite_path=$sqlite"
    Write-Output "live_sqlite_size_bytes=$($item.Length)"
    Write-Output "live_sqlite_mtime_epoch_utc=$mtime"
    if (Test-Path -LiteralPath $wal) {
        $walItem = Get-Item -LiteralPath $wal
        Write-Output "live_wal_present=true live_wal_size_bytes=$($walItem.Length)"
    } else {
        Write-Output "live_wal_present=false"
    }
' 2>&1
echo "gate_exit_code=$?"
echo "== gate complete: paste everything above back into the thread =="
