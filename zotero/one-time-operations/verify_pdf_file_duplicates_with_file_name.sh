#!/bin/bash
echo "Starting duplicate verification with Zotero name handling."

# Check for WINDOWS_USER
[[ -n "$WINDOWS_USER" ]] || {
    echo "WINDOWS_USER not defined."
    exit 1
}

directory_with_duplicates="/mnt/c/Users/$WINDOWS_USER/MIT Dropbox/Luis Martinez/pdf/"
directory_to_search="/mnt/c/Users/$WINDOWS_USER/MIT Dropbox/Luis Martinez/zotero-storage/"
echo "Directories set."
echo "Duplicate directory: $directory_with_duplicates"
echo "Directory to Search: $directory_to_search"

# Setup cache directories and files
cache_dir="./cache"
mkdir -p "$cache_dir"
files_to_match_cache="$cache_dir/files_to_match.txt"
files_to_match_normalized="$cache_dir/files_to_match_normalized.txt"
potential_duplicates_cache="$cache_dir/potential_duplicates.txt"
potential_duplicates_normalized="$cache_dir/potential_duplicates_normalized.txt"
duplicates_file="$cache_dir/duplicates.txt"

# Number of characters to keep when truncating (adjust as needed)
TRUNCATE_LENGTH=15

# Function to normalize filenames for Zotero matching
normalize_filename() {
    # Remove extension, truncate, replace spaces with underscores (no lowercase conversion)
    sed 's/\.pdf$//i' | cut -c1-$TRUNCATE_LENGTH | tr ' ' '_'
}

# Generate or use cached file lists - Zotero files are already in their final format
if [[ ! -f "$files_to_match_cache" || $(find "$files_to_match_cache" -mtime +1 -print) ]]; then
    echo "Generating files_to_match cache..."
    find "$directory_to_search" -type f -name "*.pdf" -print0 |
      xargs -0 -I{} basename "{}" |
      sort > "$files_to_match_cache"
    echo "Found $(wc -l < "$files_to_match_cache") files to match."
else
    echo "Using cached files_to_match list ($(wc -l < "$files_to_match_cache") files)."
fi

# We'll use the original Zotero filenames directly - no need to normalize them

# Same for potential duplicates
if [[ ! -f "$potential_duplicates_cache" || $(find "$potential_duplicates_cache" -mtime +1 -print) ]]; then
    echo "Generating potential_duplicates cache..."
    find "$directory_with_duplicates" -maxdepth 1 -type f -name "*.pdf" -print0 |
      xargs -0 -I{} basename "{}" |
      sort > "$potential_duplicates_cache"
    echo "Found $(wc -l < "$potential_duplicates_cache") potential duplicates."
    
    # Create normalized version for matching
    cat "$potential_duplicates_cache" | normalize_filename | sort > "$potential_duplicates_normalized"
else
    echo "Using cached potential_duplicates list ($(wc -l < "$potential_duplicates_cache") files)."
    # Regenerate normalized version if original exists but normalized doesn't
    if [[ ! -f "$potential_duplicates_normalized" ]]; then
        cat "$potential_duplicates_cache" | normalize_filename | sort > "$potential_duplicates_normalized"
    fi
fi

# Find duplicates by normalizing potential duplicates and comparing with Zotero files
echo "Finding duplicates by comparing normalized filenames against Zotero files..."
if [[ ! -f "$duplicates_file" || $(find "$duplicates_file" -mtime +1 -print) ]]; then
    > "$duplicates_file"  # Clear the duplicates file
    
    # For each potential duplicate, normalize it and check if it matches any Zotero filename
    while IFS= read -r potential_file; do
        # Get normalized version of this potential file
        normalized=$(echo "$potential_file" | normalize_filename)
        
        # Check if any file in files_to_match (Zotero files) contains this normalized name
        if grep -F -q -- "$normalized" "$files_to_match_cache"; then
            echo "$potential_file" >> "$duplicates_file"
        fi
    done < "$potential_duplicates_cache"
    
    echo "Found $(wc -l < "$duplicates_file") potential duplicates after normalization check."
else
    echo "Using cached duplicates_file list ($(wc -l < "$duplicates_file") files)."
fi

echo "Found $(wc -l < "$duplicates_file") potential duplicates after normalization."

# Read the duplicate files into an array
mapfile -t files_to_remove < "$duplicates_file"

# Define trash directory
trash_directory="/mnt/c/Users/$WINDOWS_USER/MIT Dropbox/Luis Martinez/pdf_to_delete/"
mkdir -p "$trash_directory"

# Check if there are any files to remove
if [ ${#files_to_remove[@]} -eq 0 ]; then
    echo "No duplicate files found to move."
    exit 0
fi

# Show all files that will be moved to trash
echo "The following ${#files_to_remove[@]} files will be moved to trash:"
for (( i=0; i<${#files_to_remove[@]}; i++ )); do
    echo "[$i] ${directory_with_duplicates}${files_to_remove[$i]}"
done

# Ask for confirmation before proceeding
read -p "Are you sure you want to move these files to trash? (yes/N): " confirm
if [[ "$confirm" != "yes" ]]; then
    echo "Operation cancelled."
    exit 1
fi

# Move files to trash with success/error reporting
moved=0
errors=0
for file in "${files_to_remove[@]}"; do
    full_path="${directory_with_duplicates}${file}"
   if [ -f "$full_path" ]; then
        if mv "$full_path" "$trash_directory"; then
            echo "Moved to trash: $full_path"
            ((moved++))
        else
            echo "ERROR: Failed to move $full_path"
            ((errors++))
        fi
    else
        echo "WARNING: File not found: $full_path"
        ((errors++))
    fi
done

echo "Operation complete. Moved $moved files to trash. Encountered $errors errors."
echo "Files are in: $trash_directory"
echo "You can recover them from there if needed."
##mapfile -t potential_duplicates < <(find "$directory_with_duplicates" -maxdepth 1 -type f -name "*.pdf")
##echo "Found ${#potential_duplicates[@]} potential duplicate pdf files."
##
##mapfile -t files_to_match < <(find "$directory_to_search" -type f -name "*.pdf" )
##echo "Found ${#files_to_match[@]} pdf files in the zotero directory."
##
### Create associative array for faster lookup of files_to_match
##declare -A match_files_hash
##for file in "${files_to_match[@]}"; do
##    basename=$(basename "$file")
##    match_files_hash["$basename"]=1
##done
##echo "Created the hash."
##
### Check for duplicates by name
##duplicates=()
##for file in "${potential_duplicates[@]}"; do
##    basename=$(basename "$file")
##    if [[ -n "${match_files_hash[$basename]}" ]]; then
##        duplicates+=("$file")
##    fi
##done
##
##echo "Found ${#duplicates[@]} duplicate files by name."
