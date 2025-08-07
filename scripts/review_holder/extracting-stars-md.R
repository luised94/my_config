

file_index <- grep("provide-writing-feedback.Rmd", list.files("./prompts"))
list.files("./prompts", full.names = TRUE)[file_index]
# Read in the Rmd file
rmd <- readLines(list.files("./prompts", full.names = TRUE)[file_index]) 

# Find lines starting with ""**""
bold_lines <- grep('^\\*\\*', rmd)

# Extract text between quotation marks 
bold_text <- gsub('^\\*\\*(.*)\\*\\*$', '\\1', rmd[bold_lines])

# Print the bold text
print(bold_text)
write(bold_text, file = "clipboard")
