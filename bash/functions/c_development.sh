# Purpose: Collection of functions for working with c programs
# Date: 2025-06-30

# cr - Compile and run
# TODO: Can "${@:2}" to pass the rest of the arguments to the compiled binary
cr() {
  local file_to_compile="$1"
  local binary_file="${file_to_compile%.*}"

  if [ ! -f "$file_to_compile" ]; then
    echo "[ERROR] File '$file_to_compile' does not exist." >&2
    return 1
  fi

  if [  -f binary_file ]; then
    echo "[WARNING] Binary '$binary_file' exists. Overwriting." >&2
  fi

  gcc -Wall -Wextra -pedantic -std=c11 "$file_to_compile" -o "$binary_file" #&& ./"$binary_file"

}
