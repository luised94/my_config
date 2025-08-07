pip install google-api-python-client
from googleapiclient.discovery import build

# Replace 'YOUTUBE_API_KEY' with your own YouTube API key
service = build('youtube', 'v3', developerKey='YOUTUBE_API_KEY')

# Replace 'VIDEO_ID' with the ID of the YouTube video you want to get the transcript for
video_id = 'VIDEO_ID'

# Get the transcript for the video
transcript = service.captions().list(
  part='snippet',
  videoId=video_id,
).execute()

# Print the transcript
print(transcript)
