
# Works ok.
# Use the title clean up or check how many are there and add 
# a letter at the end or something. Or even just use a timestamp to the second since they are
# meant to be quick and dirty.
mkdir -p "$HOME/text_nexus"
fleeting() {
  local timestamp; timestamp=$(date %Y%m%d)
  local temporary_file; temporary_file=$(mktemp )
  local output_dir; output_dir="$HOME/text_nexus/"
  cat "$HOME/my_config/bash/functions/quick_note_template.md" >> "$temporary_file"
  nvim "$temporary_file"
  mv "$temporary_file" "${output_dir}${timestamp}_quick_note.md"
}
