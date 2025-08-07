from calendar import month
from bs4 import BeautifulSoup
import requests
import time
import pandas as pd

url = 'https://thezman.com/wordpress/'
print(url.split('/'))
req = requests.get(url)
soup = BeautifulSoup(req.text, "html.parser")

print(soup.body.contents)
print(soup.find_all('a'))
#Accessing the url link in the first entry of the archive widget 
print(str(soup.find(id='archives-2').ul.find_all('a')[0]['href']))

#Extracting text of articles for a given month 

url = 'https://thezman.com/wordpress/?m=201307'

req = requests.get(url)
soup = BeautifulSoup(req.text, "html.parser")

print(str(soup.find_all('article')[0].find('h1', class_='entry-title').string))
print(str(soup.find_all('article')[0].find('time', class_='entry-date').string).replace(" ", "_").replace(",", ""))
print(str(soup.find_all('article')[0].find('div', class_='entry-content').text))
print(len(soup.find_all('article')))
#Output the title and content of each article for a given month and year
for article in soup.find_all('article'):
    print(article.find('h1', class_='entry-title').string)
    print(article.find('div', class_='entry-content').text)


#Store all the soups in a list

url = 'https://thezman.com/wordpress/'
print(url.split('/'))
req = requests.get(url)
soup = BeautifulSoup(req.text, "html.parser")
month_year = []

#Create the file that will contain the title and content of all the articles
f = open(url.split('/')[2]+"_"+url.split('/')[3]+".txt", "w", encoding="utf-8")
print(f.name)

#Store the dates into a list. No longer need to use url or Beautiful soup
for date in soup.find(id='archives-2').ul.find_all('a'):
    print(date['href'])
    url_date = str(date['href'])
    req_date= requests.get(url_date)
    soup_date = BeautifulSoup(req_date.text, "html.parser")
    month_year.append(soup_date)
  
print(month_year)
num_article = 0
for entry in month_year:
    num_article = num_article + len(entry.find_all('article'))

print(num_article)

df_zman = pd.DataFrame(index=range(num_article),columns=range(2))
print(df_zman)


# For each month and year in the archive widget, access and parse the url, then write each article and content to the f file. 
for date in soup.find(id='archives-2').ul.find_all('a'):
    print(date['href'])
    url_date = str(date['href'])
    req_date= requests.get(url_date)
    soup_date = BeautifulSoup(req_date.text, "html.parser")
    for article in soup_date.find_all('article'):
        f.write(str(article.find('h1', class_='entry-title').string)+"_"+str(article.find('time', class_='datetime').string).replace(" ", "_").replace(",", "")+"\n")
        f.write(str(article.find('div', class_='entry-content').text)+"\n")
    
    print("Sleeping")
    time.sleep(30)
    
f.close()



