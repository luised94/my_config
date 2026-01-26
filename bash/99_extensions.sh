#!/usr/bin/env bash
# ==============================================================================
# File: 99_extensions.sh
# Project: my_config
# Description: Contains logic to load different bash files designed to extend the my_config with independent or establish bash code files.
# Usage: source 99_extensions.sh ==============================================================================
mc_extensions_status() {
  printf "Loaded: %d  Skipped: %d  Failed: %d\n" \
    "${#_MC_LOADED_EXTENSIONS[@]}" \
    "${#_MC_SKIPPED_EXTENSIONS[@]}" \
    "${#_MC_FAILED_EXTENSIONS[@]}"
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

  # Source file
  if [[ -f "$extension" ]]; then
    if source "$extension" 2>/dev/null; then
      _MC_LOADED_EXTENSIONS+=("$extension")
    else
      msg_error "Failed to source: ${extension##*/}"
      _MC_FAILED_EXTENSIONS+=("$extension")
    fi

  # Source directory entry point
  elif [[ -d "$extension" ]]; then
    for candidate in "${extension##*/}.sh" "init.sh" "main.sh"; do
      if [[ -f "$extension/$candidate" ]]; then
        if source "$extension" 2>/dev/null; then
          _MC_LOADED_EXTENSIONS+=("$extension")
          break
        else
          msg_error "Failed to source: ${extension##*/}"
          _MC_FAILED_EXTENSIONS+=("$extension")
        fi

      fi
    done

  # Neither file nor directory
  else
    msg_debug "Skipping ${extension##*/}: not a file or directory"
    _MC_FAILED_EXTENSIONS+=("$extension")
  fi
done
