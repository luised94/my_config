### Add generalizable file naming obtained from page. 
### Figure out a way to identify papers that werent found on WoS search
### Add more journals 
###
from bs4 import BeautifulSoup
import requests


# url = "https://www.nature.com/articles/s41586-022-05027-y"
# url = "https://www.nature.com/articles/s41586-022-05028-x"
url = "https://www.nature.com/articles/nmeth.2840"
url = 'https://www.nature.com/articles/s41467-020-19532-z'
print(url.split('/')[-1])
article_doi=url.split('/')[-1]+"_"
req = requests.get(url)
soup = BeautifulSoup(req.text, "html.parser")
article_title=str(soup.find(class_='c-article-title').text).replace(" ", "_")
print(str(soup.find(class_='c-article-title').text).replace(" ", "_"))

print(soup.find_all('a'))

file1 =open(article_doi+article_title+".txt", 'w', encoding="utf-8")
count = 0 
reference_string = ""

check_string_1 ="Conference on Computer Vision"
check_string_2 = "International Conference on Learning Representations"
check_string_3 = "International Conference on Machine Learning"

for reference in soup.find_all(class_='c-article-references__text'):
	# print(reference)
	#print(str(reference.text))
	#print(str(reference.text).split("."))
	parsed_text = str(reference.text).split(".")
	# print(parsed_text)
	# print(sorted(parsed_text, key=len,reverse=True))
	# no_space = [i.replace(" ", '') for i in parsed_text]
	
	if sorted(parsed_text, key=len,reverse=True)[0][1].isdigit():
		title = sorted(parsed_text, key = len,reverse=True)[1][1:]
	elif check_string_1 in sorted(parsed_text, key=len,reverse=True)[0]:
		title = sorted(parsed_text, key = len,reverse=True)[1][1:]
	elif check_string_2 in sorted(parsed_text, key=len,reverse=True)[0]:
		title = sorted(parsed_text, key = len,reverse=True)[1][1:]
	elif check_string_3 in sorted(parsed_text, key=len,reverse=True)[0]:
		title = sorted(parsed_text, key = len,reverse=True)[1][1:]
	else:
		title = max(parsed_text, key = len)[1:]

	
	reference_string = reference_string + "(\""+str(title)+"\")" + "OR" +"\n"
	count = count + 1
	
file1.write(reference_string[:-3])
print(count)
file1.close()

# big_string_1 ="In 2016 IEEE Conference on Computer Vision and Pattern Recognition (CVPR) (eds"
# big_string_2 ="In International Conference on Learning Representations (ICLR, 2018)"
# print(big_string.find('IEEE'))
# print(big_string.find(check_string))
# print(big_string.find('pot'))
# print(check_string in big_string_1)
# print(check_string in big_string_2)
# print(reference_string[len(reference_string)-10:-3])
# print(reference_string[8085-10:8085+10])

#file1.write(reference_string[0:-3].replace("\u2032", '\''))
#file1.write(reference_string[0:-3].replace("(\"None\")OR", ''))

#print(soup.find_all(class_='ref__title').string)




#print(soup.title)


# def is_printable(data):
#     return all(c in string.printable for c in data)

# def strip_unprintable(data):
#     return ''.join(c for c in data if ord(c) > 0x1f and ord(c) != 0x7f and not (0x80 <= ord(c) <= 0x9f))

#for link in soup.find_all('a'):
#	print(link.get('href'))