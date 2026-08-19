## Slice 0 scripts (discrete, run in order, paste output)

All live in `~/personal_repos/my_config/zotero/experiments/citation-key-collision/`. Run steps 1-7 top to bottom.

### Step 1 - WSL: scaffold the experiment dir under uv

```bash
# Run from anywhere. Creates the experiment dir and inits uv WITHOUT touching git.
# We inspect what uv generated before trusting it (uv init behavior varies by version).
set -u
EXPERIMENT_DIRECTORY="$HOME/personal_repos/my_config/zotero/experiments/citation-key-collision"

echo "== uv version =="
uv --version || { echo "FAIL: uv not installed or not on PATH"; exit 1; }

echo "== creating experiment directory =="
mkdir -p "$EXPERIMENT_DIRECTORY"
cd "$EXPERIMENT_DIRECTORY" || { echo "FAIL: cannot cd into $EXPERIMENT_DIRECTORY"; exit 1; }

echo "== running uv init (no VCS, no workspace) =="
# --no-workspace: do not attach to a parent workspace / pyproject up the tree (my_config may grow one).
# We deliberately do NOT pass --no-readme etc; we inspect output next and adjust if needed.
uv init --no-workspace 2>&1 || echo "NOTE: uv init returned nonzero; inspect below before deciding"

echo "== what uv generated =="
ls -la
echo "== pyproject.toml contents =="
cat pyproject.toml 2>/dev/null || echo "no pyproject.toml"
```

Paste all output. If `uv init` created a `.git`, `main.py`, or a `.python-version` you don't want, we adjust at step 2 before committing anything.

```bash_output
sb[ ]luis@Luis:~/personal_repos/my_config/zotero/experiments/citation-key-collision$ ls
slice0.md
usb[ ]luis@Luis:~/personal_repos/my_config/zotero/experiments/citation-key-collision$ set -u
EXPERIMENT_DIRECTORY="$HOME/personal_repos/my_config/zotero/experiments/citation-key-collision"
usb[ ]luis@Luis:~/personal_repos/my_config/zotero/experiments/citation-key-collision$ echo $EXPERIMENT_DIRECTORY
/home/luis/personal_repos/my_config/zotero/experiments/citation-key-collision
usb[ ]luis@Luis:~/personal_repos/my_config/zotero/experiments/citation-key-collision$ echo "== uv version =="
uv --version || { echo "FAIL: uv not installed or not on PATH"; exit 1; }
== uv version ==
uv 0.11.1 (x86_64-unknown-linux-gnu)
usb[ ]luis@Luis:~/personal_repos/my_config/zotero/experiments/citation-key-collision$ echo "== creating experiment directory =="
mkdir -p "$EXPERIMENT_DIRECTORY"
cd "$EXPERIMENT_DIRECTORY" || { echo "FAIL: cannot cd into $EXPERIMENT_DIRECTORY"; exit 1; }
== creating experiment directory ==
usb[ ]luis@Luis:~/personal_repos/my_config/zotero/experiments/citation-key-collision$ echo "== running uv init (no VCS, no workspace) =="
# --no-workspace: do not attach to a parent workspace / pyproject up the tree (my_config may grow one).
# We deliberately do NOT pass --no-readme etc; we inspect output next and adjust if needed.
uv init --no-workspace 2>&1 || echo "NOTE: uv init returned nonzero; inspect below before deciding"

echo "== what uv generated =="
ls -la
echo "== pyproject.toml contents =="
cat pyproject.toml 2>/dev/null || echo "no pyproject.toml"
== running uv init (no VCS, no workspace) ==
Initialized project `citation-key-collision`
== what uv generated ==
total 28
drwxr-xr-x 2 luis luis 4096 Aug 19 14:19 .
drwxr-xr-x 3 luis luis 4096 Aug 19 14:10 ..
-rw-r--r-- 1 luis luis    5 Aug 19 14:19 .python-version
-rw-r--r-- 1 luis luis    0 Aug 19 14:19 README.md
-rw-r--r-- 1 luis luis  100 Aug 19 14:19 main.py
-rw-r--r-- 1 luis luis  168 Aug 19 14:19 pyproject.toml
-rw-r--r-- 1 luis luis 7105 Aug 19 14:11 slice0.md
== pyproject.toml contents ==
[project]
name = "citation-key-collision"
version = "0.1.0"
description = "Add your description here"
readme = "README.md"
requires-python = ">=3.12"
dependencies = []
```

No issues encountered.


### Step 2 - WSL: confirm the uv-managed Python and stdlib imports

```bash
set -u
EXPERIMENT_DIRECTORY="$HOME/personal_repos/my_config/zotero/experiments/citation-key-collision"
cd "$EXPERIMENT_DIRECTORY" || { echo "FAIL: cannot cd"; exit 1; }

echo "== python version under uv =="
uv run python --version || { echo "FAIL: uv run python failed"; exit 1; }

echo "== stdlib import check (must run INSIDE the uv env) =="
uv run python -c "import sqlite3, unicodedata, csv, json, collections, random; print('stdlib ok')" \
  || { echo "FAIL: a required stdlib module did not import"; exit 1; }
```

```bash_output
usb[ ]luis@Luis:~/personal_repos/my_config/zotero/experiments/citation-key-collision$ set -u
EXPERIMENT_DIRECTORY="$HOME/personal_repos/my_config/zotero/experiments/citation-key-collision"
cd "$EXPERIMENT_DIRECTORY" || { echo "FAIL: cannot cd"; exit 1; }

echo "== python version under uv =="
uv run python --version || { echo "FAIL: uv run python failed"; exit 1; }

echo "== stdlib import check (must run INSIDE the uv env) =="
uv run python -c "import sqlite3, unicodedata, csv, json, collections, random; print('stdlib ok')" \
  || { echo "FAIL: a required stdlib module did not import"; exit 1; }
== python version under uv ==
Using CPython 3.12.12
Creating virtual environment at: .venv
Python 3.12.12
== stdlib import check (must run INSIDE the uv env) ==
stdlib ok
```

### Step 3 - WSL: assert the env vars the two-device design depends on

```bash
set -u
echo "== WSL user =="
test -n "${USER:-}" && echo "USER=$USER" || { echo "FAIL: \$USER empty"; exit 1; }

echo "== Windows user bridge var =="
# MC_WINDOWS_USER must be exported on every device this experiment runs on.
# If empty, every downstream Windows path silently breaks -- hard-fail here.
test -n "${MC_WINDOWS_USER:-}" \
  && echo "MC_WINDOWS_USER=$MC_WINDOWS_USER" \
  || { echo "FAIL: \$MC_WINDOWS_USER empty -- export it before continuing"; exit 1; }
```

```bash_output
usb[ ]luis@Luis:~/personal_repos/my_config/zotero/experiments/citation-key-collision$ set -u
echo "== WSL user =="
test -n "${USER:-}" && echo "USER=$USER" || { echo "FAIL: \$USER empty"; exit 1; }

echo "== Windows user bridge var =="
# MC_WINDOWS_USER must be exported on every device this experiment runs on.
# If empty, every downstream Windows path silently breaks -- hard-fail here.
test -n "${MC_WINDOWS_USER:-}" \
  && echo "MC_WINDOWS_USER=$MC_WINDOWS_USER" \
  || { echo "FAIL: \$MC_WINDOWS_USER empty -- export it before continuing"; exit 1; }
== WSL user ==
USER=luis
== Windows user bridge var ==
MC_WINDOWS_USER=Luised94
```

### Step 4 - WSL: cross-boundary probe (does PowerShell-from-WSL work at all)

```bash
set -u
echo "== can WSL invoke powershell.exe and get a result back =="
# The point is that the CALL succeeds. Empty output is fine.
# We print two distinct signals: (a) the call worked, (b) whether Zotero is currently running.
powershell.exe -NoProfile -Command 'Write-Output "powershell-reachable"' 2>&1 \
  || { echo "FAIL: powershell.exe not reachable from WSL -- fall back to manual copy"; exit 1; }

echo "== is Zotero currently running (informational for Slice 0; load-bearing for Slice 1) =="
powershell.exe -NoProfile -Command '@(Get-Process zotero -ErrorAction SilentlyContinue).Count' 2>&1
```

```bash_output
usb[ ]luis@Luis:~/personal_repos/my_config/zotero/experiments/citation-key-collision$ set -u
echo "== can WSL invoke powershell.exe and get a result back =="
# The point is that the CALL succeeds. Empty output is fine.
# We print two distinct signals: (a) the call worked, (b) whether Zotero is currently running.
powershell.exe -NoProfile -Command 'Write-Output "powershell-reachable"' 2>&1 \
  || { echo "FAIL: powershell.exe not reachable from WSL -- fall back to manual copy"; exit 1; }

echo "== is Zotero currently running (informational for Slice 0; load-bearing for Slice 1) =="
powershell.exe -NoProfile -Command '@(Get-Process zotero -ErrorAction SilentlyContinue).Count' 2>&1
== can WSL invoke powershell.exe and get a result back ==
powershell-reachable
== is Zotero currently running (informational for Slice 0; load-bearing for Slice 1) ==
3
# After closing Zotero
usb[ ]luis@Luis:~/personal_repos/my_config/zotero/experiments/citation-key-collision$ powershell.exe -NoProfile -Command '@(Get-Process zotero -ErrorAction SilentlyContinue).Count' 2>&1
0
```

If step 4 fails, we record `copy-mechanism: manual` and stop treating PowerShell-from-WSL as available. If it prints `powershell-reachable` and a count, we proceed with `powershell-from-wsl`.

### Step 5 - create the sqlite-assertion PowerShell script (written as a file to dodge quoting)

Run this bash heredoc to write the `.ps1`, then invoke it:

```bash
set -u
EXPERIMENT_DIRECTORY="$HOME/personal_repos/my_config/zotero/experiments/citation-key-collision"
cd "$EXPERIMENT_DIRECTORY" || { echo "FAIL: cannot cd"; exit 1; }

cat > assert_zotero_sqlite.ps1 <<'PS1'
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
PS1

echo "== running the sqlite assertion via -File (bypasses the WSL->PS quoting layer) =="
# Convert the WSL path to a Windows path so powershell.exe -File can find the script.
SCRIPT_WINDOWS_PATH="$(wslpath -w "$EXPERIMENT_DIRECTORY/assert_zotero_sqlite.ps1")"
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "$SCRIPT_WINDOWS_PATH" 2>&1
echo "exit_code=$?"
```

```bash_output
echo "== running the sqlite assertion via -File (bypasses the WSL->PS quoting layer) =="
# Convert the WSL path to a Windows path so powershell.exe -File can find the script.
SCRIPT_WINDOWS_PATH="$(wslpath -w "$EXPERIMENT_DIRECTORY/assert_zotero_sqlite.ps1")"
echo "exit_code=$?"rofile -ExecutionPolicy Bypass -File "$SCRIPT_WINDOWS_PATH" 2>&1
== running the sqlite assertion via -File (bypasses the WSL->PS quoting layer) ==
zotero_data_directory=C:\Users\Luised94\Zotero
sqlite_path=C:\Users\Luised94\Zotero\zotero.sqlite
sqlite_size_bytes=2981036032
sqlite_mtime_epoch_utc=1787165115
exit_code=0
```

This is the hard assertion you asked for: missing file  nonzero exit + explicit message; zero bytes  same. On success it prints the four values the manifest needs.

### Step 6 - re-confirm the Zotero version (stamp check against VERIFIED_ENVIRONMENT.md's 9.0.6)

```bash
set -u
echo "== Zotero version from the Windows-side install =="
# VERIFIED_ENVIRONMENT.md is stamped Zotero 9.0.6 (2026-07). Re-confirm and note any drift.
# Zotero stores its version in application.ini next to the executable; location varies,
# so we try the common install roots and report whichever answers.
powershell.exe -NoProfile -Command '$paths = @("$env:ProgramFiles\Zotero\application.ini", "${env:ProgramFiles(x86)}\Zotero\application.ini", "$env:LOCALAPPDATA\Zotero\Zotero\application.ini"); foreach ($p in $paths) { if (Test-Path -LiteralPath $p) { $v = (Select-String -LiteralPath $p -Pattern "^Version=").Line; Write-Output "$p -> $v"; break } }' 2>&1
```

```bash_output
usb[ ]luis@Luis:~/personal_repos/my_config/zotero/experiments/citation-key-collision$ echo "== Zotero version from the Windows-side install =="
# VERIFIED_ENVIRONMENT.md is stamped Zotero 9.0.6 (2026-07). Re-confirm and note any drift.
# Zotero stores its version in application.ini next to the executable; location varies,
# so we try the common install roots and report whichever answers.
powershell.exe -NoProfile -Command '$paths = @("$env:ProgramFiles\Zotero\app\application.ini", "${env:ProgramFiles(x86)}\Zotero\app\application.ini", "$env:LOCALAPPDATA\Zotero\Zotero\app\application.ini"); foreach ($p in $paths) { if (Test-Path -LiteralPath $p) { $v = (Select-String -LiteralPath $p -Pattern "^Version=").Line; Write-Output "$p -> $v"; break } }' 2>&1
== Zotero version from the Windows-side install ==
usb[ ]luis@Luis:~/personal_repos/my_config/zotero/experiments/citation-key-collision$ powershell.exe -NoProfile -Command '$paths = @("$env:ProgramFiles\Zotero\app\application.ini", "${env:ProgramFiles(x86)}\Zotero\app\application.ini", "$env:LOCALAPPDATA\Zotero\Zotero\app\application.ini"); foreach ($p in $paths) { if (Test-Path -LiteralPath $p) { $v = (Select-String -LiteralPath $p -Pattern "^Version=").Line; Write-Output "$p -> $v"; break } }' 2>&1
C:\Program Files\Zotero\app\application.ini -> Version=9.0.6
```

Only fix was the app directory addition.

### Step 7 - write the manifest, clean the uv stub, print checksum + size

```bash
set -u
EXPERIMENT_DIRECTORY="$HOME/personal_repos/my_config/zotero/experiments/citation-key-collision"
cd "$EXPERIMENT_DIRECTORY" || { echo "FAIL: cannot cd"; exit 1; }

# Remove the uv init stub: main.py implies an entry point this experiment does not have,
# and README.md is empty. Neither is an artifact; delete before the manifest is checksummed
# so the recorded dir state matches reality.
rm -f main.py README.md

# The manifest holds THIS DEVICE's observed environment measurements (paths, versions,
# sqlite size/mtime, chosen copy mechanism). Reusable API facts go to VERIFIED_ENVIRONMENT.md
# instead (step 8). No wall-clock "generated-at" field: the manifest must be a pure function
# of observed facts so re-running the writer yields an identical checksum for reconciliation.
#
# device is a stable human-chosen label, not a hostname: the experiment spans two machines and
# Slice 1's cross-device snapshot reconciliation keys off it. "primary" = this machine (Luis@Luis).
cat > environment_manifest.primary.json <<'JSON'
{
  "manifest_schema": "citation-key-collision/environment/v1",
  "device": "primary",
  "wsl_user": "luis",
  "windows_user": "Luised94",
  "repo_path_wsl": "/home/luis/personal_repos/my_config/zotero/experiments/citation-key-collision",
  "uv_version": "0.11.1",
  "python_version": "3.12.12",
  "zotero_version": "9.0.6",
  "zotero_application_ini_path": "C:\\Program Files\\Zotero\\app\\application.ini",
  "zotero_data_directory": "C:\\Users\\Luised94\\Zotero",
  "zotero_sqlite_path": "C:\\Users\\Luised94\\Zotero\\zotero.sqlite",
  "zotero_sqlite_size_bytes": 2981036032,
  "zotero_sqlite_mtime_epoch_utc": 1787165115,
  "copy_mechanism": "powershell-from-wsl",
  "powershell_from_wsl_reachable": true
}
JSON

echo "== manifest written =="
cat environment_manifest.primary.json

echo "== manifest identity for the carry-forward (sha256 first 12 hex, byte size) =="
# These two are what Slice 1's gate recomputes and compares. A changed checksum or size
# means the manifest was edited or corrupted between threads -> Slice 1 halts before trusting it.
MANIFEST_SHA256_FULL="$(sha256sum environment_manifest.primary.json | cut -d' ' -f1)"
echo "manifest_sha256_first12=${MANIFEST_SHA256_FULL:0:12}"
echo "manifest_size_bytes=$(stat -c %s environment_manifest.primary.json)"

echo "== final directory state =="
ls -la
```

```bash_output
== manifest identity for the carry-forward (sha256 first 12 hex, byte size) ==
manifest_sha256_first12=62d5d6bedce1
manifest_size_bytes=711
== final directory state ==
total 48
drwxr-xr-x 3 luis luis  4096 Aug 19 15:05 .
drwxr-xr-x 3 luis luis  4096 Aug 19 14:10 ..
-rw-r--r-- 1 luis luis     5 Aug 19 14:19 .python-version
drwxr-xr-x 4 luis luis  4096 Aug 19 14:20 .venv
-rw-r--r-- 1 luis luis  1051 Aug 19 14:46 assert_zotero_sqlite.ps1
-rw-r--r-- 1 luis luis   711 Aug 19 15:05 environment_manifest.primary.json
-rw-r--r-- 1 luis luis   168 Aug 19 14:19 pyproject.toml
-rw-r--r-- 1 luis luis 15481 Aug 19 15:05 slice0.md
-rw-r--r-- 1 luis luis   142 Aug 19 14:20 uv.lock
```

### Step 8 - promote the two reusable facts to VERIFIED_ENVIRONMENT.md

This appends a new section. It doesn't touch existing content.

```bash
set -u
VERIFIED_ENVIRONMENT_PATH="$HOME/personal_repos/my_config/zotero/VERIFIED_ENVIRONMENT.md"
test -f "$VERIFIED_ENVIRONMENT_PATH" || { echo "FAIL: VERIFIED_ENVIRONMENT.md not at $VERIFIED_ENVIRONMENT_PATH"; exit 1; }

cat >> "$VERIFIED_ENVIRONMENT_PATH" <<'MARKDOWN'

## Zotero install path and PowerShell-from-WSL bridge

Tested: Zotero 9.0.6; Windows (profile via $env:USERPROFILE); WSL (citation-key-collision Slice 0, 2026-08).

- application.ini lives under the `app\` subdirectory of the install root,
  not the install root itself: `C:\Program Files\Zotero\app\application.ini`
  (also check `${env:ProgramFiles(x86)}\Zotero\app\` and
  `$env:LOCALAPPDATA\Zotero\Zotero\app\`). The version line is `Version=9.0.6`.
- powershell.exe is invocable from WSL and returns output across the boundary.
  `Get-Process zotero -ErrorAction SilentlyContinue` returns a count that is
  nonzero while Zotero runs and 0 when closed -- usable as the cold-copy
  process guard from the WSL side without a Windows-side helper.
- Cross-boundary file metadata is best emitted as UTC Unix epoch seconds
  (`[DateTimeOffset]::new($item.LastWriteTimeUtc).ToUnixTimeSeconds()`), not a
  formatted date, to stay locale-independent and comparable across devices.
- Non-trivial PowerShell run from WSL should be written to a .ps1 and invoked
  with `powershell.exe -NoProfile -ExecutionPolicy Bypass -File "$(wslpath -w ...)"`
  to avoid the bash->powershell quoting layer.
MARKDOWN

echo "== appended; showing the new tail =="
tail -n 25 "$VERIFIED_ENVIRONMENT_PATH"
```
