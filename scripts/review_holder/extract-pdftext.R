library(pdftools)

# Read PDF file
pdf_file <- "C:\\Users\\liusm\\Dropbox (MIT)\\zotero-storage\\Gupta\\gupta_2022_an_orc_flip_enables_bidirectional_helicase_loading.pdf"

# Extract text 
text <- pdf_text(pdf_file)
text[c(31:36,39:44,121:125)]
write(text[c(31:36,39:44,121:125)], file = "./output/shalu-thesis-raw.txt") 

# Read in text
text <- readLines("./output/shalu-thesis-raw.txt") 

# Find references section 
lapply(grep("References", text), FUN = function(x){
  text[grepl("References", text):]
})
references <- text[grepl("References", text):length(text)] 
grep("References", text)
# Extract reference lines based on patterns
library(stringr) 
ref_lines <- str_subset(references, "^[A-Z][a-z]+,\\s[A-Z]\\.")