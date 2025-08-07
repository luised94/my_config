from bs4 import BeautifulSoup
import requests
#url = "https://www.cell.com/molecular-cell/fulltext/S1097-2765(22)00577-9"
url = "https://www.cell.com/cell/fulltext/S0092-8674(15)00265-2"
url = 'https://www.cell.com/cell/pdf/S0092-8674(22)00458-5.pdf#secsectitle0355'
req = requests.get(url)
soup = BeautifulSoup(req.text, "html.parser")
#print(soup.title)


# def is_printable(data):
#     return all(c in string.printable for c in data)

# def strip_unprintable(data):
#     return ''.join(c for c in data if ord(c) > 0x1f and ord(c) != 0x7f and not (0x80 <= ord(c) <= 0x9f))

#for link in soup.find_all('a'):
#	print(link.get('href'))
file1 =open('myfile.txt', 'w')
count = 0 
reference_string = ""
for reference in soup.find_all(class_='ref__title'):	
	reference_string = reference_string + "(\""+str(reference.string).replace('.', '')+"\")" + "OR" +"\n"
	count = count + 1
	print(reference.string)

print(reference_string[len(reference_string)-10:-3])
print(reference_string[540-10:540+10])
file1.write(reference_string[0:-3].replace("\u2032", '\''))
#file1.write(reference_string[0:-3].replace("(\"None\")OR", ''))
print(count)
file1.close()
#print(soup.find_all(class_='ref__title').string)


