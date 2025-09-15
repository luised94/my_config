#!/bin/bash
# zotero_backup_to_hard_drive.sh
# Uses rsync to synchronize the backup hard drive from the local computer.
# Date: 2025-09-15
# Version: 1.0.0

FROM="/mnt/c/Users/${WINDOWS_USER}/Zotero"
FROM="/mnt/c/Users/${WINDOWS_USER}/MIT Dropbox/${DROPBOX_USER}/zotero-storage/"
MARKER_FILE=$( find "/mnt/" -mindepth 1 -maxdepth 1 -type f -name "filename" )
