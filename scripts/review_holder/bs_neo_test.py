from bs4 import BeautifulSoup
import requests

url = 'https://journal-neo.org/2022/04/28/the-fraud-of-modern-western-history/'
req = requests.get(url)
soup = BeautifulSoup(req.text, "html.parser")

print(url[0:len(url)-1].split('/')[-1])
print(soup.find_all(class_='author')[0].a.string)
print(soup.find_all(class_='entry-title')[0].string)
print(soup.find_all('span'))

for text in soup.find_all('span'):
        print(text.string)

for span in soup.find_all('p'):
    print(span.string)
