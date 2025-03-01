#!/bin/bash

echo "Starting duplicate verification."
[[ ! -f $WINDOWS_USER ]] || {
    echo "WINDOWS_USER not defined."
    exit
}

directory_with_duplicates="/mnt/c/Users/$WINDOWS_USER/MIT Dropbox/Luis Martinez/pdf/"
directory_to_search="/mnt/c/Users/$WINDOWS_USER/MIT Dropbox/Luis Martinez/zotero-storage/"

echo "Directories set."
echo "Duplicate directory: $diretory_with_duplicates"
echo "Directory to Search: $diretory_to_search"

mapfile -t potential_duplicates < <(find "$directory_with_duplicates" -maxdepth 1 -type f -name "*.pdf")
echo "Found ${#potential_duplicates[@]} potential duplicate pdf files."

mapfile -t files_to_match < <(find "$directory_to_search" -type f -name "*.pdf" )
echo "Found ${#files_to_match[@]} pdf files in the zotero directory."

# Create associative array for faster lookup of files_to_match
declare -A match_files_hash
for file in "${files_to_match[@]}"; do
    basename=$(basename "$file")
    match_files_hash["$basename"]=1
done
echo "Created the hash."

# Check for duplicates by name
duplicates=()
for file in "${potential_duplicates[@]}"; do
    basename=$(basename "$file")
    if [[ -n "${match_files_hash[$basename]}" ]]; then
        duplicates+=("$file")
    fi
done

echo "Found ${#duplicates[@]} duplicate files by name."
