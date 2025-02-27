library(readtext)
x <- readtext("C:/Users/liusm/Dropbox (MIT)/Lab/Projects/publications-&-presentations/Tesis Doctoral/Text/Luis Thesis Drafts/091623/Luis_Thesis_complete_v8.docx")
doc.parts <- strsplit(x$text, "\n")[[1]]
# fd <- file("thesis-text.txt", open = "wt")
# for (line in doc.parts) {
#     write(line, fd, sep = "\n", append = TRUE)
# }
# close(fd)
# closeAllConnections()

# Initialize a flag to ignore lines before "Introduction"
ignore_lines <- TRUE

# Initialize an empty vector to store the processed lines
processed_lines <- c()

# Loop through each line and preprocess
for (line in doc.parts) {
  # Check if the line contains "Introduction" as the only word
  if (ignore_lines && grepl("^Introduction$", line)) {
    ignore_lines <- FALSE
  }
  
  # Check if the line contains "Figure" at the beginning
  if (!grepl("^Figure", line)) {
    # Remove Zotero citations
    line <- gsub("ADDIN ZOTERO_ITEM CSL_CITATION.*?\\)", "", line)
    
    # Add the processed line to the vector
    processed_lines <- c(processed_lines, line)
  }
}

# Join the processed lines back into a single text
processed_text <- paste(processed_lines, collapse = "\n")

# Print the processed text
cat(processed_text)

fd <- file("thesis-processed-text.txt", open = "wt")

write(processed_text, fd, sep = "\n", append = TRUE)

close(fd)
closeAllConnections()
