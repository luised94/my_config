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
    "Montgomery.*Statistics"
    "Runger.*Statistics"
    "Walpole.*Probability"
    "Boyce.*Differential"
    "DiPrima.*Differential" 
    "Zill.*Differential"
    "Kreyszig.*Engineering.*Mathematics"
    "Riley.*Mathematical.*Methods"
    "James.*Statistical.*Learning"
    "Hastie.*Statistical.*Learning"
    "Tibshirani.*Statistical.*Learning"
    "Witten.*Statistical.*Learning"
    "Bishop.*Pattern.*Recognition"
    "Montgomery.*Design.*Analysis"
    "Beveridge.*Scientific.*Investigation"
    "Williams.*Style.*Clarity"
    "Bizup.*Style"
    "Penrose.*Writing.*Sciences"
    "Apostol.*Calculus"
    "Epp.*Discrete.*Mathematics"
    "Martin.*Clean.*Code"
    "Abelson.*Structure.*Interpretation"
    "Sussman.*Structure.*Interpretation"
    "Rudin.*Mathematical.*Analysis"
    "Dummit.*Abstract.*Algebra"
    "Foote.*Abstract.*Algebra"
    "Munkres.*Topology"
    "Griffiths.*Electrodynamics"
    "Griffiths.*Quantum"
    "Taylor.*Classical.*Mechanics"
    "Abramowitz.*Mathematical.*Functions"
    "Stegun.*Mathematical.*Functions"
    "Gradshteyn.*Integrals"
    "Ryzhik.*Integrals"
    "Brown.*Make.*Stick"
    "Roediger.*Make.*Stick"
    "McDaniel.*Make.*Stick"
    "Newport.*Deep.*Work"
    "Polya.*Mathematics.*Plausible"
    "Zeitz.*Art.*Craft.*Problem"
    "Homer.*Iliad"
    "Homer.*Odyssey"
    "Shakespeare"
    "Dante.*Divine.*Comedy"
    "Gardner.*Art.*Through.*Ages"
    "Janson.*History.*Art"
    "Norton.*Anthology.*Poetry"
    "Austen"
    "Dickens"
    "Tolstoy"
    "Joyce"
    "Kafka"
    "Kant.*Critique.*Judgment"
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
