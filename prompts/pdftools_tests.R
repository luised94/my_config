library(pdftools)
library(tesseract)
library(magick)
#?ocr()
receipt <- "C:/Users/liusm/Desktop/R_and_Pdfs/receipt_example.jpg"
filename <- "C:/Users/liusm/Desktop/R_and_Pdfs/MigrationsandCultures.pdf"
text <- pdf_text(filename) 
bitmap_pdf <- pdf_render_page(filename, page = 400)

# Save bitmap image
png::writePNG(bitmap, "C:/Users/liusm/Desktop/R_and_Pdfs/trial.png")
jpeg::writeJPEG(bitmap, "trial.jpeg")
webp::write_webp(bitmap, "imagtrial.webp")

txt <- ocr("C:/Users/liusm/Desktop/R_and_Pdfs/trial.png", HOCR =  TRUE)
txt <- ocr(receipt, HOCR =  FALSE)
cat(txt)




receipt <- "C:/Users/liusm/Desktop/R_and_Pdfs/20210804_190838.jpg"
txt <- ocr(receipt)
cat(txt)

#added flash to picture
receipt <- "C:/Users/liusm/Desktop/R_and_Pdfs/20210804_191717_mod_2.jpg"
txt <- ocr(receipt)
cat(txt)
#attempt with textbook
txtbook <- "C:/Users/liusm/Desktop/R_and_Pdfs/Janeways.pdf"
#text <- pdf_text(txtbook) 
pdf_ocr_text(txtbook, pages = 95)

bitmap <- pdf_render_page(txtbook, page = 95)
png::writePNG(bitmap, "C:/Users/liusm/Desktop/R_and_Pdfs/trial.png")
txt <- ocr("C:/Users/liusm/Desktop/R_and_Pdfs/trial.png", HOCR =  FALSE)
txt <- ocr(receipt, HOCR =  FALSE)
cat(txt)
