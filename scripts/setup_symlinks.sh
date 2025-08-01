#!/bin/bash

BASE_DIRECTORY="$HOME/personal_repos/my_config/"
# Add more files to symlink here.
# Not robust enough to handle multiple branching logic depending on
# where it should be symlinked to.
FILES_TO_SYMLINK=(
  "dotfiles/bashrc.sh"
  "dotfiles/vimrc.vim"
  "nvim"
)

for filename in "${FILES_TO_SYMLINK[@]}";
do

  printf '\n%*s\n\n' "${COLUMNS:-80}" '' | tr ' ' '='

  filepath="${BASE_DIRECTORY}${filename}"
  printf "File to symlink: %s\n" "$filename"
  printf "Path to file: %s\n" "$filepath"

  # Skip if the target does not exist
  if [[ ! -e $filepath ]]; then
    printf 'Skipping: %s (not found)\n' "$filepath" >&2
    continue
  fi

  # --- Check for files ---
  if [ -f "$filepath" ];
  then

      symlink_name=$(
          readlink -f "$filepath" |
          awk -F/ -v home="$HOME" '
            {
              sub(/\..*$/,"",$NF)
              print home "/." $NF
            }'
        )

      printf "Symbolic link to create: %s\n" "$symlink_name"

      if [ -h "$symlink_name" ];
      then
        printf "Skipping... Symbolic link exists: %s\n" "$symlink_name"
        continue
      fi

      echo "Creating symlink..."
      ln -s "$filepath" "$symlink_name"

  fi

  # --- Check for dirs ---
  if [ -d "$filepath" ];
  then
      symlink_name=$(
          readlink -f "$filepath" |
          awk -F/ -v home="$HOME" -v config_dir="/.config/" '
            {
                sub(/\..*$/,"",$NF)
                print home config_dir $NF
            }' 
        )
      printf "Symbolic link to create: %s\n" "$symlink_name"

      if [ -h "$symlink_name" ];
      then
        printf "Skipping... Symbolic link exists: %s\n" "$symlink_name"
        continue
      fi

      echo "Creating symlink..."
      ln -s "$filepath" "$symlink_name"
      continue
  fi

done
