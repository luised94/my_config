#!/usr/bin/env bash
# ------------------------------------------------------------------------------
# 99_extensions.sh - User extension loader
# ------------------------------------------------------------------------------
# Sources user extensions from MC_EXTENSIONS_DIR (~/.config/mc_extensions/).
#
# Extension formats:
#   file.sh           - Sourced directly
#   dirname/          - Looks for entry point in priority order:
#                       1. dirname.sh  2. init.sh  3. main.sh
#
# Skip mechanisms:
#   - Files/dirs starting with '_' are skipped
#   - Entries in _MC_SKIP_EXTENSIONS array are skipped
#
# Tracking arrays (populated at load):
#   _MC_LOADED_EXTENSIONS   - Successfully sourced
#   _MC_SKIPPED_EXTENSIONS  - Skipped (prefix or skip list)
#   _MC_FAILED_EXTENSIONS   - Failed to source
#
# Use mc_extensions_status [-v] to view summary.
# ------------------------------------------------------------------------------

mc_extensions_status() {
  if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
    printf "Usage: mc_extensions_status [-v]\n"
    printf "Display extension loading summary.\n\n"
    printf "Options:\n"
    printf "  -v    Show full paths for each category\n"
    printf "  -h    Show this help message\n"
    return 0
  fi

  printf "Loaded: %d  Skipped: %d  Failed: %d\n" \
    "${#_MC_LOADED_EXTENSIONS[@]}" \
    "${#_MC_SKIPPED_EXTENSIONS[@]}" \
    "${#_MC_FAILED_EXTENSIONS[@]}"

  if [[ "${1:-}" == "-v" ]]; then
    if [[ ${#_MC_LOADED_EXTENSIONS[@]} -gt 0 ]]; then
      printf "\nLoaded:\n"
      printf "  %s\n" "${_MC_LOADED_EXTENSIONS[@]}"
    fi
    if [[ ${#_MC_SKIPPED_EXTENSIONS[@]} -gt 0 ]]; then
      printf "\nSkipped:\n"
      printf "  %s\n" "${_MC_SKIPPED_EXTENSIONS[@]}"
    fi
    if [[ ${#_MC_FAILED_EXTENSIONS[@]} -gt 0 ]]; then
      printf "\nFailed:\n"
      printf "  %s\n" "${_MC_FAILED_EXTENSIONS[@]}"
    fi
  fi
}

if [[ ! -d "$MC_EXTENSIONS_DIR" ]]; then
  msg_error "MC_EXTENSIONS_DIR does not exist: $MC_EXTENSIONS_DIR"
  return 1

fi

for extension in "$MC_EXTENSIONS_DIR"/*; do
  [[ -e "$extension" ]] || continue # guard against glob.
  skip_reason=""

  # Check underscore prefix
  if [[ "${extension##*/}" == _* ]]; then
    skip_reason="begins with '_'"
  fi

  # Check skip array
  if [[ -z "$skip_reason" ]]; then
    for skipped in "${_MC_SKIP_EXTENSIONS[@]}"; do
      if [[ "${extension##*/}" == "$skipped" ]]; then
        skip_reason="in skip list"
        break
      fi
    done
  fi

  # Handle skip
  if [[ -n "$skip_reason" ]]; then
    msg_warn "Skipping ${extension##*/}: $skip_reason"
    _MC_SKIPPED_EXTENSIONS+=("$extension")
    continue
  fi

  # Check for broken symlink
  if [[ -L "$extension" && ! -e "$extension" ]]; then
    msg_error "Broken symlink: ${extension##*/}  $(readlink "$extension")"
    _MC_FAILED_EXTENSIONS+=("$extension")
    continue
  fi

  # Source file
  if [[ -f "$extension" && "$extension" == *.sh ]]; then
    if source "$extension"; then
      _MC_LOADED_EXTENSIONS+=("$extension")
    else
      msg_error "Failed to source: ${extension##*/}"
      _MC_FAILED_EXTENSIONS+=("$extension")
    fi

  # Source directory entry point
  elif [[ -d "$extension" ]]; then
    for candidate in "${extension##*/}.sh" "init.sh" "main.sh"; do
      entry_point="$extension/$candidate"
      if [[ -f $entry_point ]]; then
        if source "$entry_point"; then
          _MC_LOADED_EXTENSIONS+=("$entry_point")
          break

        else
          msg_error "Failed to source: ${extension##*/}"
          _MC_FAILED_EXTENSIONS+=("$entry_point")

        fi

      fi
    done

  fi
  ## Neither bash file nor directory
  #else

  #  msg_debug "Skipping ${extension##*/}: not a file or directory"
  #  _MC_FAILED_EXTENSIONS+=("$extension")

  #fi

done
