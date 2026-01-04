# ------------------------------------------------------------------------------
# FUNCTION   : view_files
# PURPOSE    : Browse files in batches using system browser (WSL).
# USAGE      : view_files [-t type] [-x exclude] [-b batch] [-d depth] [directory]
# DEPENDS    : MC_BROWSER (from 00_config.sh), wslpath
# RETURNS    : 0 on success, 1 on error
# ------------------------------------------------------------------------------
view_files() {
  if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
    printf "Usage: %s [-t type] [-x exclude] [-b batch] [-d depth] [directory]\n\n" "${FUNCNAME[0]}"
    printf "Browse files in batches using system browser.\n\n"
    printf "Options:\n"
    printf "  -t TYPE     File extension to match (default: html)\n"
    printf "  -f PATTERN  Filter to files matching pattern\n"
    printf "  -b SIZE     Batch size (default: 5)\n"
    printf "  -d DEPTH    Search depth (default: 3)\n"
    printf "  -h          Show this help\n\n"
    printf "Examples:\n"
    printf "  %s ~/reports\n" "${FUNCNAME[0]}"
    printf "  %s -t svg -d 5 ~/plots\n" "${FUNCNAME[0]}"
    printf "  %s -t html -f report ~/output\n" "${FUNCNAME[0]}"
    return 0
  fi

  # --- Defaults ---
  local file_type="html"
  local filter=""
  local batch_size=5
  local depth=3

  # --- Parse Options ---
  local OPTIND opt
  while getopts ":t:f:b:d:h" opt; do
    case $opt in
      t) file_type="$OPTARG" ;;
      f) filter="$OPTARG" ;;
      b) batch_size="$OPTARG" ;;
      d) depth="$OPTARG" ;;
      h) view_files --help; return 0 ;;
      :) msg_error "Option -$OPTARG requires an argument"; return 1 ;;
      \?) msg_error "Invalid option: -$OPTARG"; return 1 ;;
    esac
  done
  shift $((OPTIND - 1))

  local target
  target="$(realpath -s "${1:-$(pwd)}")"

  # --- Validate ---
  if [[ ! -d "$target" ]]; then
    msg_error "Invalid directory: $target"
    return 1
  fi

  if [[ ! -f "$MC_BROWSER" ]]; then
    msg_error "Browser not configured or missing: ${MC_BROWSER:-<unset>}"
    msg_info "Set MC_BROWSER in 00_config.sh"
    return 1
  fi

  # --- Build find command ---
  local -a find_args=(-maxdepth "$depth" -type f -name "*.${file_type}")
  if [[ -n "$filter" ]]; then
    find_args+=(-name "*${filter}*")
  fi

  # --- Find files ---
  local -a files
  mapfile -t files < <(find "$target" "${find_args[@]}" 2>/dev/null | sort)

  local file_count=${#files[@]}

  if (( file_count == 0 )); then
    msg_warn "No *.${file_type} files found in $target (depth: $depth)"
    msg_info "Try increasing depth with: -d <number>"
    return 0
  fi

  msg_info "Found $file_count file(s)"

  # --- Confirm ---
  printf "Open files in browser? [y/N] "
  read -r response
  if [[ ! "$response" =~ ^[Yy]$ ]]; then
    msg_info "Cancelled"
    return 0
  fi

  # --- Process in batches ---
  local index=0
  local batch_num=1
  local windows_path

  while (( index < file_count )); do
    msg_info "Batch $batch_num: files $((index + 1))-$((index + batch_size > file_count ? file_count : index + batch_size))"

    for (( i = 0; i < batch_size && index < file_count; i++, index++ )); do
      windows_path="$(wslpath -w "${files[index]}")"
      "$MC_BROWSER" "$windows_path" &
      sleep 0.3
    done

    wait

    if (( index < file_count )); then
      printf "Next batch? [Y/n/q] "
      read -r input
      if [[ "$input" =~ ^[Qq]$ ]]; then
        msg_info "Stopped at file $index of $file_count"
        return 0
      fi
    fi

    batch_num=$((batch_num + 1))
  done

  msg_info "Complete: $file_count files opened"
}
