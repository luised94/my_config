from pyzotero import zotero

# Initialize zotero 
zot = zotero.Zotero('user_id', 'user', 'api_key')

# Get all items
items = zot.everything(zot.items())

# Extract URLs
urls = []
for item in items:
  if item['data'].get('url'):
    urls.append(item['data']['url'])

# Print URLs
for url in urls:
  print(url)
