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

DESTINATION_DIRECTORY="/mnt/f/zotero-storage/"

if [ ! -d "$DESTINATION_DIRECTORY" ]; then
 echo "[ERROR] DESTINATION_DIRECTORY does not exist. Set manually or adjust."
 exit 1
fi

rsync -nav -delete "$SOURCE_DIRECTORY" "$DESTINATION_DIRECTORY"

# TODO: Add before and after number verification
