#!/usr/bin/env bash
# ==============================================================================
# File: 99_extensions.sh
# Project: my_config
# Description: Contains logic to load different bash files designed to extend the my_config with independent or establish bash code files.
# Usage: source 99_extensions.sh ==============================================================================

if [[ ! -d "$MC_EXTENSIONS_DIR" ]]; then
  msg_error "MC_EXTENSIONS_DIR does not exist: $MC_EXTENSIONS_DIR"
  return 1

fi

for extension in "$MC_EXTENSIONS_DIR/"*; do
  if [[ "$(basename "$extension")" == _* ]];then
    msg_warn "Skipping $extension: begins with '_'"
    _MC_SKIPPED_EXTENSIONS+=("$extension")
    continue
  fi

  if [[ -f "$extension" ]]; then
    source "$extension"
    _MC_LOADED_EXTENSIONS+=("$extension")
  elif [[ -d "$extension" ]]; then
    for candidate in "$(basename "$extension").sh" "main.sh" "init.sh"; do
      if [[ -f $candidate ]]; then
        source "$extension/$candidate"
        _MC_LOADED_EXTENSIONS+=("$extension/$candidate")
        break
      fi
    done
  else
    msg_debug "Extension not file or directory."
    _MC_FAILED_EXTENSIONS+=("$extension")
  fi

done
