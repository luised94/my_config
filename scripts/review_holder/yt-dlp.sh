#Install ffmpeg and yt-dlp using pip after you activate the virtual environment (source/activate)

#!/bin/bash

# List of YouTube video URLs
videos=(
# Add urls ere
)

# Output directory
outdir="../output"

# Create output directory if it doesn't exist
mkdir -p "$outdir"

for video in "${videos[@]}"; do

  # Download video
  yt-dlp -f worst -o "%(title)s.%(ext)s" "$video"

  # Extract srt transcript 
  yt-dlp --write-auto-subs \
         --convert-subs srt \
         --ffmpeg-location "/c/Users/liusm/appdata/local/programs/python/python311/lib/site-packages/" \
         --sub-lang en "$video" > transcripts_to_summarize.vtt

  # Move srt file to output directory
  mv "*.en.srt" "$outdir"

  # Delete video file
  rm "*.%(ext)s"

done
