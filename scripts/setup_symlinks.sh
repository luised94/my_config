#!/bin/bash

BASE_DIRECTORY="$HOME/personal_repos/my_config/"
#FILE_SYMLINK_DIRECTORY="~/"
DIR_SYMLINK_DIRECTORY="~/.config"
FILES_TO_SYMLINK=(
  "dotfiles/bashrc.sh"
  "dotfiles/vimrc.vim"
  "nvim"
)

for filename in "${FILES_TO_SYMLINK[@]}";
do
  filepath="${BASE_DIRECTORY}${filename}"
  printf "File to symlink: %s\n" "$filename"
  printf "Path to file: %s\n" "$filepath"

  if [ -f "$filepath" ];
  then
      symlink_name=$(readlink -f "$filepath" | awk -F/ -v home="$HOME" '{sub(/\..*$/,"",$NF); print home "/." $NF}' )
      printf "Symbolic link to create: %s\n" "$symlink_name"
      if [ -h "$symlink_name" ];
      then
        printf "Symbolic link exists: %s\n" "$symlink_name"
        continue
      fi
      echo "Creating symlink..."
      ln -s "$filepath" "$symlink_name"
  fi
  #echo "File or directory do not exist."
  #exit 1
done
