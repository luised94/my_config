# How to create a scratch (clone) Zotero library for the perf probe

**Type:** How-to guide (Diataxis). Task-oriented; assumes you already know why
you want a scratch library (to run `perf_probe_p1_p2.js` without touching real
data). It does not explain the probe or the perf investigation.

**Applies to:** Zotero 7.x on Windows. macOS/Linux differ only in paths and the
copy command (noted at the end).

---

## Goal

Produce a second, fully independent Zotero database on disk -- a byte copy of
your real library that the probe can write to and delete from freely, with no
path back to your real `zotero.sqlite`. You launch Zotero against the copy using
a separate profile, run the probe, then discard the copy.

## Why the full-directory clone, and not a new group library

Two methods can give you "a library to experiment in". They are not equally safe
for this probe, so pick deliberately:

1. **Full data-directory clone (this guide).** The copy is a separate
   `zotero.sqlite` in a separate folder. Even if every filter in the probe
   failed, it physically cannot reach your real items -- they are in a different
   file the running Zotero never opens. This is the method to use.
2. **A new group/empty library inside your real install (rejected here).** The
   scratch items live in the *same* `zotero.sqlite` as everything real, isolated
   only by a `libraryID` filter in code. A bug that dropped that filter would
   write to your real items. Fine for casual testing; wrong for a probe whose
   whole point is a hard isolation guarantee. Do not use it for this.

The tradeoff of the clone: it costs disk space equal to your data directory
(the `storage/` folder of attachments dominates -- see the optional slimming
step) and a few minutes of copy time. Worth it for the isolation.

---

## Preconditions

Confirm all of these before starting. Skipping the first risks corrupting the
*copy* (a torn read of a live SQLite file); the copy is disposable, but a torn
copy wastes the run.

- **Zotero is completely closed** for the duration of the copy. Not minimized to
  tray -- fully quit. Copying a live `zotero.sqlite` mid-write produces a torn
  database. (Zotero's own docs: close Zotero before copying the data directory,
  or the data may be corrupted.)
- **You know your real data directory path.** Find it before quitting: in
  Zotero, **Edit > Settings > Advanced > Files and Folders > Data Directory
  Location**, or click **Show Data Directory**. Default on Windows is
  `C:\Users\<you>\Zotero`.
- **Free disk space** at least equal to the size of that directory. Check the
  `storage\` subfolder size first; it is usually the bulk.
- **PowerShell** available (built into Windows). No admin rights needed if the
  destination is under your own user profile.
- **Sync consideration:** if you use Zotero sync, the clone will still hold your
  sync credentials in its copied prefs. The launch step below uses a *separate
  profile* so the clone does not sync as you -- but as a belt-and-braces measure,
  do not enter sync credentials in the scratch instance, and do not click "Sync"
  there.

## Postconditions (what success looks like)

- A folder `C:\Users\<you>\Zotero-scratch` containing `zotero.sqlite` (and
  `storage\` unless you slimmed it) that is a copy of your real one.
- A separate Zotero profile named `scratch` that opens that folder.
- Launching that profile shows your library items; running the probe writes and
  then removes `__perf_probe_*` tags there; your **real** Zotero, opened
  normally, is untouched.

---

## Inputs / variables

Set these once at the top of a PowerShell window. Adjust `$RealDataDir` if your
data directory is not the default.

```powershell
# --- variables -----------------------------------------------------------
# Your REAL Zotero data directory (source). Default Windows location shown.
# Verify via Zotero > Settings > Advanced > Show Data Directory before closing Zotero.
$RealDataDir  = "$env:USERPROFILE\Zotero"

# Where the disposable CLONE will live (destination). Anything you own is fine.
$ScratchDir   = "$env:USERPROFILE\Zotero-scratch"

# Name for the separate Zotero profile that will open the clone.
$ScratchProfile = "scratch"

# Set to $true to clone WITHOUT the storage\ attachments folder (metadata/tags
# only, much faster and smaller). The probe only reads/writes TAGS, so it does
# not need attachment files. Set $false for a full byte-for-byte clone.
$SlimClone = $true
# -------------------------------------------------------------------------
```

---

## Procedure

### Step 1 -- Quit Zotero completely

Close all Zotero windows, then check nothing is still running:

```powershell
Get-Process zotero -ErrorAction SilentlyContinue
```

**Expected:** no output (nothing returned) means Zotero is not running. If a
process is listed, close it from the tray or:

```powershell
# Only if a stray process is holding the database open:
Get-Process zotero -ErrorAction SilentlyContinue | Stop-Process
```

Re-run the `Get-Process` line and confirm no output before continuing. This is
the one step that, skipped, wastes the copy.

### Step 2 -- Verify the source and its size

```powershell
Test-Path (Join-Path $RealDataDir "zotero.sqlite")      # must print: True
"{0:N1} GB" -f ((Get-ChildItem $RealDataDir -Recurse -File |
    Measure-Object Length -Sum).Sum / 1GB)              # total size to copy
"{0:N1} GB" -f ((Get-ChildItem (Join-Path $RealDataDir "storage") -Recurse -File -ErrorAction SilentlyContinue |
    Measure-Object Length -Sum).Sum / 1GB)              # size of storage\ alone
```

**Expected:** first line `True`. If it is `False`, `$RealDataDir` is wrong --
re-open Zotero, read the real path from Settings, fix the variable, and quit
Zotero again. The two sizes tell you the disk cost; if `storage\` is most of it,
keep `$SlimClone = $true`.

### Step 3 -- Copy the data directory to the scratch location

The copy is the clone. `robocopy` is used because it is resilient and reports
what it did; `/MIR` mirrors the tree.

```powershell
if ($SlimClone) {
    # Metadata + tags only: copy everything EXCEPT the storage\ attachments tree.
    # The probe touches only tags, so attachments are not needed.
    robocopy $RealDataDir $ScratchDir /MIR /XD (Join-Path $RealDataDir "storage") /NFL /NDL /NJH /NP
} else {
    # Full byte-for-byte clone including all attachments.
    robocopy $RealDataDir $ScratchDir /MIR /NFL /NDL /NJH /NP
}

# robocopy uses exit codes 0-7 for success (8+ is failure). Normalize for a clear check.
if ($LASTEXITCODE -lt 8) { "COPY OK (robocopy code $LASTEXITCODE)" }
else { "COPY FAILED (robocopy code $LASTEXITCODE) -- do not use this clone" }
```

**Expected:** `COPY OK`. Then confirm the clone has its database:

```powershell
Test-Path (Join-Path $ScratchDir "zotero.sqlite")       # must print: True
```

Note: SQLite may leave a `zotero.sqlite-wal` / `-shm` or `-journal` alongside
the main file. Copying them is harmless; Zotero manages them. If Zotero was
closed cleanly in Step 1, they are usually absent or empty.

### Step 4 -- Create a separate Zotero profile for the clone

A separate *profile* keeps the scratch instance from disturbing your real
profile's settings, and lets you point it at `$ScratchDir` without changing your
real data directory. Open the Profile Manager:

```powershell
# Adjust the path if Zotero is installed elsewhere.
& "C:\Program Files\Zotero\zotero.exe" -P
```

In the Profile Manager window:

1. Click **Create Profile** > **Next**.
2. Name it exactly `scratch` (matches `$ScratchProfile`).
3. Finish. **Do not** tick "Use the selected profile without asking at startup".
4. Select the `scratch` profile and click **Start Zotero**.

**Expected:** a fresh Zotero opens on an *empty* library (a new profile has no
data directory of its own yet). That is correct -- the next step points it at the
clone.

### Step 5 -- Point the scratch profile at the clone

In the scratch Zotero instance:

1. **Edit > Settings > Advanced > Files and Folders**.
2. Under **Data Directory Location**, choose **Custom**, click **Choose**, and
   select `C:\Users\<you>\Zotero-scratch` (`$ScratchDir`) -- the folder that
   contains `zotero.sqlite`, not the `storage` folder inside it.
3. When prompted, let it **restart**.

**Expected:** after restart, the scratch instance shows **your library items**.
It is now running entirely off the clone. If `$SlimClone` was true, attachment
files show as missing (broken paperclip) -- expected and irrelevant; the probe
does not read attachments.

### Step 6 -- Confirm isolation before running the probe

This is the check that earns the trust. In the scratch instance:

- Confirm the data directory path shown in Settings is `$ScratchDir`, **not**
  `$RealDataDir`.

Then, separately, open your **real** Zotero the normal way (Start menu / desktop
icon, which uses the default profile) and confirm it still opens your real data
directory. The two now run off two different files.

**Expected:** scratch Zotero -> `Zotero-scratch\zotero.sqlite`; normal Zotero ->
`Zotero\zotero.sqlite`. Different files. The probe cannot cross between them.

### Step 7 -- Run the probe in the scratch instance

Only in the scratch instance:

1. **Tools > Developer > Run JavaScript**.
2. **Tick "Run as async function"** (the probe uses top-level `await`).
3. Paste `perf_probe_p1_p2.js`, set `CONFIG.I_UNDERSTAND_THIS_WRITES = true`,
   Run.
4. Read the returned `report` object.

The probe adds `__perf_probe_<timestamp>*` tags, times the saves, then removes
those tags in its cleanup phase. Because this is the clone, even a cleanup
failure only leaves junk tags on a disposable database.

---

## Teardown (after you have the numbers)

The clone is disposable. To remove it:

```powershell
# 1. Quit the scratch Zotero instance first.
Get-Process zotero -ErrorAction SilentlyContinue   # expect: no output

# 2. Delete the clone directory.
Remove-Item $ScratchDir -Recurse -Force
Test-Path $ScratchDir                              # expect: False
```

Optionally delete the `scratch` profile: run `zotero.exe -P`, select `scratch`,
**Delete Profile**. Choose "Don't Delete Files" if you already removed
`$ScratchDir` yourself, or "Delete Files" to have it remove the profile's own
folder. Your default profile and real data are untouched throughout.

---

## Troubleshooting

- **Step 3 `COPY FAILED` (code >= 8):** usually a locked file (Zotero still
  running -- redo Step 1) or insufficient disk space (re-check Step 2 sizes; set
  `$SlimClone = $true`).
- **Scratch instance opens an empty library, not your items:** the data
  directory in Step 5 points at the wrong level. It must be the folder that
  *contains* `zotero.sqlite`, not the `storage` subfolder and not a parent.
- **"Database is locked" or corruption error on scratch launch:** the copy was
  taken while Zotero was writing. Delete `$ScratchDir`, confirm Zotero is fully
  closed (Step 1), and re-copy.
- **Attachments show as missing with `$SlimClone = $true`:** expected. The probe
  is tag-only. If you need attachments for other testing, re-clone with
  `$SlimClone = $false`.
- **You accidentally pointed your REAL profile at the clone:** in that instance,
  Settings > Advanced > Files and Folders > set Data Directory back to
  `$RealDataDir` and restart. No data is lost -- you only changed which folder
  that profile reads.

---

## macOS / Linux note

Same procedure; only the paths and copy command change. Default data directory
is `~/Zotero`. Quit Zotero fully, then:

```bash
# Slim clone (metadata/tags only):
rsync -a --exclude 'storage' ~/Zotero/ ~/Zotero-scratch/
# Full clone:
rsync -a ~/Zotero/ ~/Zotero-scratch/
```

Launch the Profile Manager with `Zotero -P` (Linux) or
`/Applications/Zotero.app/Contents/MacOS/zotero -P` (macOS), then follow Steps
4-7 unchanged.
