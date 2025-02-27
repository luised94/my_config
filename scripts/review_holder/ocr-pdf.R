library(tesseract)
library(jpeg)
eng <- tesseract("eng")
file_to_ocr <- "C:/Users/Luis/Dropbox (MIT)/Lab/Experiments/Protocols/ORC Fluorescence Polarization · Benchling.pdf"
file_folder <- dirname(file_to_ocr)
delete_pngs <- TRUE
if (file.exists(file_to_ocr)){
  text <- tesseract::ocr("C:/Users/Luis/Dropbox (MIT)/Lab/Experiments/Protocols/ORC Fluorescence Polarization · Benchling.pdf")
} 
if (delete_pngs){
  file.remove(list.files(pattern = ".png"))
}

output_file_text <- paste(file_folder, "Fluorescence Polarization.md", sep = "/")
cat(text, file = output_file_text)
