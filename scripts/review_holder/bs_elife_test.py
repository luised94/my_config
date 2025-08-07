### Add generalizable file naming obtained from page. 
### Figure out a way to identify papers that werent found on WoS search
### Add more journals 
###
from bs4 import BeautifulSoup
import requests


url = "https://elifesciences.org/articles/76923"
print(url.split('/')[-1])
article_doi=url.split('/')[-1]+"_"

req = requests.get(url)
soup = BeautifulSoup(req.text, "html.parser")

article_title=str(soup.find(class_='content-header__title').text).replace(" ", "_")
print(str(soup.find(class_='content-header__title').text).replace(" ", "_"))

file1 =open(article_doi+article_title+".txt", 'w', encoding="utf-8")
count = 0 
reference_string = ""

check_string_1 ="Conference on Computer Vision"
check_string_2 = "International Conference on Learning Representations"
check_string_3 = "International Conference on Machine Learning"

for reference in soup.find_all(class_='reference__title'):
	# print(reference)
	# print(str(reference.text))
	#print(str(reference.text).split("."))
	
	# print(parsed_text)
	# print(sorted(parsed_text, key=len,reverse=True))
	# no_space = [i.replace(" ", '') for i in parsed_text]
    parsed_text = str(reference.text).split(".")
    # print(" " in parsed_text)
    # print(" " in parsed_text[0])

    if not(" " in parsed_text[0]):
        print(str(parsed_text[0])+" is a single word. Ambigous search.")

    elif sorted(parsed_text, key=len,reverse=True)[0][1].isdigit():
        title = sorted(parsed_text, key = len,reverse=True)[1]
        reference_string = reference_string + "(\""+str(title)+"\")" + "OR" +"\n"
    elif check_string_1 in sorted(parsed_text, key=len,reverse=True)[0]:
        title = sorted(parsed_text, key = len,reverse=True)[1]
        reference_string = reference_string + "(\""+str(title)+"\")" + "OR" +"\n"
    elif check_string_2 in sorted(parsed_text, key=len,reverse=True)[0]:
        title = sorted(parsed_text, key = len,reverse=True)[1]
        reference_string = reference_string + "(\""+str(title)+"\")" + "OR" +"\n"
    elif check_string_3 in sorted(parsed_text, key=len,reverse=True)[0]:
        title = sorted(parsed_text, key = len,reverse=True)[1]
        reference_string = reference_string + "(\""+str(title)+"\")" + "OR" +"\n"
    else:
        title = max(parsed_text, key = len)
        reference_string = reference_string + "(\""+str(title)+"\")" + "OR" +"\n"
    count = count + 1

# print(reference_string)	

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