#!/bin/bash
# Simple script to backup zotero from dropbox.
# Feels like I should always confirm before backing up.
# TODO: Add a few more checks for the paths.
# TODO: Add a more robust way to find destination directory.

if [ ! -z "$DROPBOX_PATH" ]; then
 echo "[ERROR] DROPBOX_PATH not set. Set manually or adjust."
 exit 1
fi

SOURCE_DIRECTORY="$DROPBOX_PATH/zotero-storage/"
#mapfile -t potential_backup_directories < <(find /mnt/ -type d )
#for directory in ${potential_backup_directories[@]}; do
#  echo $directory
#  if [ -z $directory/backup_drive.txt ]; then
#    DESTINATION_DIRECTORY="$directory/zotero-storage/"
#  fi
#done
DESTINATION_DIRECTORY="/mnt/f/zotero-storage/"

echo "Debugging: "
echo "  Source: ${SOURCE_DIRECTORY}"
echo "  DESTINATION: ${DESTINATION_DIRECTORY}"
if [ ! -d "$DESTINATION_DIRECTORY" ]; then
 echo "[ERROR] DESTINATION_DIRECTORY does not exist. Set manually or adjust."
 exit 1
fi
#mapfile -t number_of_files_destination < <( find $DESTINATION_DIRECTORY -type f | wc -l )
#mapfile -t number_of_files_source < <( find $DESTINATION_DIRECTORY -type f | wc -l )

rsync -nav --progress --stats --delete "$SOURCE_DIRECTORY" "$DESTINATION_DIRECTORY"

# TODO: Add before and after number verification
