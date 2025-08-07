import re 
from pdfminer.high_level import extract_pages, extract_text

# for page_layout in extract_pages("cell1989.pdf"):
#     for element in page_layout:
#         print(element)

example = "watsontextbook.pdf"
text = extract_text(example)
text2 = extract_text(example2)
print(text)

pattern = re.compile(r"[a-zA-z]+,{1}\s{1}")
    
matches = pattern.findall(text)
print(matches)
print(pattern.findall(text2))


isbn_pattern = re.compile(r"978-0-321-76243-6")
elife_pattern = re.compile(r"10.7554/eLife.\d{5}")





matches = pd.DataFrame(elife_pattern.findall(text2))
matches.drop_duplicates()
names = [n[:-2] for n in matches]
print(names)


import fitz
import PIL.Image 
import io 

pdf = fitz.open("cell1989.pdf")
#This actually saves the page as slices for this pdf. 
counter = 1
for i in range(len(pdf)):
    page = pdf[i]
    images = page.get_images()
    for image in images:
        base_img = pdf.extract_image(image[0])
        image_data =base_img["image"]
        img = PIL.Image.open(io.BytesIO(image_data))
        extension = base_img["ext"]
        with open(f"image{counter}.{extension}", "wb") as fh:
            img.save(fh)
        counter += 1

import tabula
tables = tabula.read_pdf(example)
#This extracts the for cell file basically. 
df = tables[0]