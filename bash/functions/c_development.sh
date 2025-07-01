# Purpose: Collection of functions for working with c programs
# Date: 2025-06-30

# cr - Compile and run
cr() {
  local file_to_compile="$1"
  local binary_file; binary_file=${file_to_compile%.*}
  if [ ! -f $file_to_compile ]; then
    echo "[ERROR] File does not exist."
    exit 1
  fi
  if [  -f binary_file ]; then
    echo "[WARNING] Binary file exists. Will overwrite."
  fi
  gcc -Wall -Wextra -pedantic -std=c11 "$file_to_compile" -o "$binary_file" && ./"$binary_file"

}
