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
# === FUNCTIONS ===
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

mc_link_extension() {
  if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
    printf "Usage: mc_link_extension [-f] <path>...
Create symlinks in MC_EXTENSIONS_DIR for the given extension paths.

Options:
  -f    Force overwrite existing symlinks
  -h    Show this help

Arguments:
  path  File (.sh) or directory to link as extension

Examples:
  mc_link_extension ~/projects/kbd.sh
  mc_link_extension -f ./my_extension/
  mc_link_extension ext1.sh ext2.sh ext3/
"
    return 0
  fi

  local force=false
  while getopts ":f" opt; do
    case $opt in
      f) force=true ;;
      *) msg_error "Unknown option: -$OPTARG"; return 1 ;;
    esac
  done
  shift $((OPTIND - 1))

  if [[ $# -eq 0 ]]; then
    msg_error "No paths provided. Use -h for help."
    return 1
  fi

  local path source_abs dest name entry_point
  local has_errors=false

  for path in "$@"; do
    # Check source exists
    if [[ ! -e "$path" ]]; then
      msg_error "Path does not exist: $path"
      has_errors=true
      continue
    fi

    # Convert to absolute path
    if ! source_abs=$(realpath "$path" 2>/dev/null); then
      msg_error "Failed to resolve path: $path"
      has_errors=true
      continue
    fi

    # Validate extension format
    if [[ -f "$source_abs" ]]; then
      local ext="${source_abs##*.}"
      if [[ ! " ${MC_EXTENSION_TYPES_ALLOWED[*]} " == *" $ext "* ]]; then
        msg_error "File type not allowed: .$ext (allowed: ${MC_EXTENSION_TYPES_ALLOWED[*]})"
        has_errors=true
        continue
      fi
      name="${source_abs##*/}"
    elif [[ -d "$source_abs" ]]; then
      name="${source_abs##*/}"
      # Check for valid entry point
      entry_point=""
      for candidate in "$source_abs/$name.sh" "$source_abs/init.sh" "$source_abs/main.sh"; do
        if [[ -f "$candidate" ]]; then
          entry_point="$candidate"
          break
        fi
      done
      if [[ -z "$entry_point" ]]; then
        msg_warn "No entry point found in directory: $name/ (expected $name.sh, init.sh, or main.sh)"
      fi
    else
      msg_error "Path is neither file nor directory: $path"
      has_errors=true
      continue
    fi

    dest="$MC_EXTENSIONS_DIR/$name"

    # Check destination
    if [[ -e "$dest" || -L "$dest" ]]; then
      if [[ "$force" == true ]]; then
        rm -f "$dest"
        msg_info "Removed existing: $name"
      else
        msg_error "Already exists: $name (use -f to overwrite)"
        has_errors=true
        continue
      fi
    fi

    # Create symlink
    if ln -s "$source_abs" "$dest"; then
      msg_info "Linked: $name -> $source_abs"
    else
      msg_error "Failed to create symlink: $name"
      has_errors=true
    fi
  done

  [[ "$has_errors" == false ]]
}

#=== PROCEDURE ===
if [[ ! -d "$MC_EXTENSIONS_DIR" ]]; then
  msg_warn "MC_EXTENSIONS_DIR does not exist: $MC_EXTENSIONS_DIR"
  mkdir -p $MC_EXTENSIONS_DIR
  #return 1

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
    msg_error "Broken symlink: ${extension##*/} -> $(readlink "$extension")"
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

