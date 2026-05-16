import urllib.request
import urllib.parse
import json

api_key = 'AIzaSyDktvpBhIwvCLiGubtc0-s4I07vIuWDBxA'
folder_id = '1hw9znxf4iqqsOWJwSgMl4Q_OcgCfDytL'
q = "name = 'catalog.json' and '" + folder_id + "' in parents and trashed = false"
list_url = 'https://www.googleapis.com/drive/v3/files?q=' + urllib.parse.quote(q) + '&key=' + api_key

def test_url(url, name):
    print(f"Testing {name}...")
    try:
        with urllib.request.urlopen(url) as response:
            print(f"  Status: {response.getcode()}")
            return True
    except Exception as e:
        print(f"  Error: {e}")
        return False

print(f"Listing catalog.json...")
try:
    with urllib.request.urlopen(list_url) as response:
        data = json.loads(response.read().decode())
        files = data.get('files', [])
        if files:
            file_id = files[0]['id']
            print(f"  File ID: {file_id}")
            
            test_url(f'https://www.googleapis.com/drive/v3/files/{file_id}?alt=media&key={api_key}', "API (alt=media)")
            test_url(f'https://drive.google.com/uc?export=download&id={file_id}', "UC (No Key)")
            test_url(f'https://drive.google.com/uc?export=download&id={file_id}&key={api_key}', "UC (With Key)")
        else:
            print("  File not found")
except Exception as e:
    print(f"  List Error: {e}")
