#!/bin/bash
# zotero_backup_to_hard_drive.sh
# Uses rsync to synchronize the backup hard drive from the local computer.
# Date: 2025-09-15
# Version: 1.0.0

#FROM="/mnt/c/Users/${WINDOWS_USER}/Zotero"
#FROM=()
DROPBOX_USER="Luis Martinez"
SOURCE_DIRECTORY="/mnt/c/Users/${WINDOWS_USER}/MIT Dropbox/${DROPBOX_USER}/zotero-storage"
ZOTERO_FOLDER_IN_DESTINATION=$(echo $SOURCE_DIRECTORY | awk -F/ '{print $NF}')
MARKER_FILE="backup_drive.txt"
DESTINATION_DIRECTORY=
echo "Source directory: $SOURCE_DIRECTORY"
echo "MARKER_FILE: $MARKER_FILE"
mounted_directories=$( find "/mnt/" -mindepth 1 -maxdepth 1 -type d)
FILE_FOUND=0
for directory in ${mounted_directories[@]}; do
  if [[ FILE_FOUND -eq 1 ]]; then
    echo "File found... Skipping"
    continue
  fi

  echo "$directory"
  echo "Trying to find file: ${directory}/$MARKER_FILE"
  if [[ -f ${directory}/$MARKER_FILE ]]; then
    echo "Found the maker file. Directory: $directory"
    DESTINATION_DIRECTORY=${directory}
    ZOTERO_DIRECTORY_IN_DESTINATION="${DESTINATION_DIRECTORY}/${ZOTERO_FOLDER_IN_DESTINATION}/"
    FILE_FOUND=1

  fi

done

echo "Source directory: ${SOURCE_DIRECTORY}/"
echo "Destination directory: $DESTINATION_DIRECTORY"
echo "Full Destination path: $ZOTERO_DIRECTORY_IN_DESTINATION"
#rsync -nav "${SOURCE_DIRECTORY}/" "$ZOTERO_FOLDER_IN_DESTINATION"
