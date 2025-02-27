from calendar import month
from bs4 import BeautifulSoup
import requests
import time
import pandas as pd

url = 'https://biology.mit.edu/faculty-and-research/faculty/'

req = requests.get(url)
soup = BeautifulSoup(req.text, "html.parser")

print(soup.body.contents)
print(soup.find_all(class_="profile-faculty-short-info")[1].find(class_='first-name').string)

for faculty in soup.find_all(class_="profile-faculty-short-info"):
    print(faculty.find(class_='first-name').string)
    print(faculty.find(class_='last-name').string)



    





  




