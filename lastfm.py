import requests
import json
import os
import datetime
from azure.storage.blob import BlobServiceClient
from dotenv import load_dotenv
load_dotenv()

API_KEY = os.environ.get("LASTFM_API_KEY")

URL = f"http://ws.audioscrobbler.com/2.0/?method=chart.gettoptracks&api_key={API_KEY}&format=json&limit=50"

response = requests.get(URL)
data = response.json()

tracks = data["tracks"]["track"]
for position, track in enumerate(tracks, start=1):
    track["chart_position"] = position

timestamp = datetime.datetime.now().strftime("%Y-%m-%dT%H-%M")
filename = f"data/lastfm_top_tracks_{timestamp}.json"

os.makedirs("data", exist_ok=True)
with open(filename, "w") as f:
    json.dump(data, f, indent=2)

print(f"Saved {filename}")

try:
    connection_string = os.environ.get("AZURE_CONNECTION_STRING")
    blob_service_client = BlobServiceClient.from_connection_string(connection_string)
    container_name = "lastfm-raw-data"
    blob_name = filename

    with open(filename, "rb") as upload_data:
        blob_service_client.get_container_client(container_name).upload_blob(name=blob_name, data=upload_data, overwrite=True)

    print(f"Uploaded {filename} to Azure Blob Storage")
except Exception as e:
    print(f"Azure upload failed: {e}")