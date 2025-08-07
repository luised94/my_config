from bs4 import BeautifulSoup
import requests

url = 'http://thesaker.is/austrian-barbarians-go-home/'
req = requests.get(url)
soup = BeautifulSoup(req.text, "html.parser")

print(url[0:len(url)-1].split('/')[-1])
print(soup.find('strong').string.replace("By ", '').replace(" for The Saker blog", ''))

print(soup.get_text())
print(soup.find_all(class_='entry-title')[0].string)
print(soup.find_all(class_='post-content'))
print(type(soup.find(class_='post-content')))
print(soup.find(class_='post-content').find_all("p")[0:-2])
print(soup.find_all('p'))

for text in soup.find_all('span'):
        print(text.string)

for span in soup.find_all('p'):
    print(span.string)

for text in soup.find(class_='post-content').find_all("p")[0:-2]:
    print(text.string)