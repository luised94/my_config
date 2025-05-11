#!/usr/bin/bash
# Purpose: Backup zotero storage and library

missing_setting=0
if [ ! -z $WINDOWS_USER ]; then
  echo "[WARNING] WINDOWS_USER variable missing. Please define or export before running script."
  missing_setting=1
fi

if [ ! -z $WINDOWS_USER ]; then
  echo "[WARNING] WINDOWS_USER variable missing. Please define or export before running script."
  missing_setting=1
fi

[ missing_setting -eq 1 ] && {
  echo "Some settings missing. See warnings. Define and export before running script.";
  exit 1;
}
