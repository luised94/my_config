#!/bin/bash

# Zotero Reading List Checker
# Usage: ./zotero_find_files.sh

# UPDATE THIS PATH TO YOUR ZOTERO DIRECTORY
ZOTERO_DIR="/mnt/c/Users/${WINDOWS_USER}/MIT Dropbox/Luis Martinez/zotero-storage"

# Check if directory exists
if [[ ! -d "$ZOTERO_DIR" ]]; then
    echo "ERROR: Zotero directory not found: $ZOTERO_DIR"
    echo "Please update the ZOTERO_DIR variable in this script."
    exit 1
fi

# All recommended books to search for
BOOKS=(
    "Montgomery_*_*"
    "Runger_*_*"
    "Walpole_*_*"
    "Boyce_*_*"
    "DiPrima_*_*" 
    "Zill_*_*"
    "Kreyszig_*_*"
    "Riley_*_*"
    "James_2013_*"
    "Hastie_*_*"
    "Tibshirani_*_*"
    "Witten_*_*"
    "Bishop_2006_*"
    "Beveridge_*_*"
    "Williams_*_*"
    "Bizup_*_*"
    "Penrose_*_*"
    "Apostol_*_*"
    "Epp_*_*"
    "Martin_2008_*"
    "Abelson_*_*"
    "Sussman_*_*"
    "Rudin_*_*"
    "Dummit_*_*"
    "Foote_*_*"
    "Munkres_*_*"
    "Griffiths_*_*"
    "Taylor_*_*"
    "Abramowitz_*_*"
    "Stegun_*_*"
    "Gradshteyn_*_*"
    "Ryzhik_*_*"
    "Brown_*_*"
    "Roediger_*_*"
    "McDaniel_*_*"
    "Newport_*_*"
    "Polya_*_*"
    "Zeitz_*_*"
    "Homer_*_*"
    "Shakespeare_*_*"
    "Dante_*_*"
    "Gardner_*_*"
    "Janson_*_*"
    "Norton_*_*"
    "Austen_*_*"
    "Dickens_*_*"
    "Tolstoy_*_*"
    "Joyce_*_*"
    "Kafka_*_*"
    "Kant_*_*"
)

# Search for each book and collect found files
found_files=()

for pattern in "${BOOKS[@]}"; do
    matches=$(find "$ZOTERO_DIR" -type f -iname "*${pattern}*" 2>/dev/null)
    if [[ -n "$matches" ]]; then
        while IFS= read -r file; do
            found_files+=("$file")
        done <<< "$matches"
    fi
done

# Print results
echo "Found ${#found_files[@]} recommended books in $ZOTERO_DIR:"
echo
for file in "${found_files[@]}"; do
    echo "$(basename "$file")"
done
