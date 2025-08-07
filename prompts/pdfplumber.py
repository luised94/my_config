import pdfplumber
import os
#To use to.image() for troubleshooting, need to install ghoscript and imagemagick
#See https://stackoverflow.com/questions/25003117/python-doesnt-find-magickwand-libraries-despite-correct-location
# Download ImageMagick-6.9.12-64-Q16-x86-dll.exe at https://legacy.imagemagick.org/script/download.php
#Download gs927w32.exe at https://github.com/ArtifexSoftware/ghostpdl-downloads/releases/tag/gs927
magick_home=os.getcwd() + os.sep + "ImageMagick-6.9.12-Q16-HDRI"
os.environ["PATH"] += os.pathsep + magick_home + os.sep
os.environ["MAGICK_HOME"] = magick_home
os.environ["MAGICK_CODER_MODULE_PATH"] = magick_home + os.sep + "modules" + os.sep + "coders"

with pdfplumber.open("watsontextbook.pdf") as pdfw:
    first_page = pdfw.pages[0]
    print(first_page.chars[0])
    first_image = first_page.to_image()
    first_image

pdfw.close()

from wand.image import Image
