#!/usr/bin/env python3
"""
POD Recording Uploader - Upload video clips to PlateBridge Portal

This script handles:
1. Recording video clips when events occur (plate detection, motion, manual)
2. Requesting signed upload URLs from portal
3. Uploading clips to Supabase Storage
4. Confirming upload and creating database records

Requirements:
  pip install requests opencv-python

Usage:
  python recording_uploader.py
"""

import os
import sys
import time
import json
import requests
from datetime import datetime
from pathlib import Path

# Configuration
PORTAL_URL = os.getenv('PORTAL_URL', 'https://your-portal.vercel.app')
POD_API_KEY = os.getenv('POD_API_KEY', 'pbk_your_api_key_here')
CAMERA_ID = os.getenv('CAMERA_ID', 'your-camera-uuid')
RECORDINGS_DIR = os.getenv('RECORDINGS_DIR', '/tmp/recordings')

# Ensure recordings directory exists
os.makedirs(RECORDINGS_DIR, exist_ok=True)


class RecordingUploader:
    def __init__(self, portal_url, api_key):
        self.portal_url = portal_url
        self.api_key = api_key
        self.headers = {
            'Authorization': f'Bearer {api_key}',
            'Content-Type': 'application/json'
        }

    def request_upload_url(self, camera_id, filename, content_type='video/mp4'):
        """
        Step 1: Request signed upload URL from portal
        """
        print(f'[Upload] Requesting upload URL for {filename}...')

        try:
            response = requests.post(
                f'{self.portal_url}/api/pod/recordings/upload-url',
                headers=self.headers,
                json={
                    'camera_id': camera_id,
                    'filename': filename,
                    'content_type': content_type
                }
            )

            if response.status_code != 200:
                print(f'[Upload] Failed to get upload URL: {response.text}')
                return None

            data = response.json()
            print(f'[Upload] Got signed URL, expires in {data["expires_in"]}s')

            return {
                'signed_url': data['signed_url'],
                'file_path': data['file_path']
            }

        except Exception as e:
            print(f'[Upload] Error requesting upload URL: {e}')
            return None

    def upload_file(self, file_path, signed_url):
        """
        Step 2: Upload file to Supabase Storage using signed URL
        """
        print(f'[Upload] Uploading {file_path}...')

        try:
            with open(file_path, 'rb') as f:
                file_data = f.read()

            response = requests.put(
                signed_url,
                data=file_data,
                headers={
                    'Content-Type': 'video/mp4'
                }
            )

            if response.status_code not in [200, 201]:
                print(f'[Upload] Upload failed: {response.status_code} {response.text}')
                return False

            print('[Upload] Upload successful')
            return True

        except Exception as e:
            print(f'[Upload] Error uploading file: {e}')
            return False

    def confirm_upload(self, camera_id, file_path, duration_seconds=0,
                      event_type='manual', plate_number=None, metadata=None):
        """
        Step 3: Confirm upload and create database record
        """
        print('[Upload] Confirming upload with portal...')

        # Get file size
        local_file = os.path.join(RECORDINGS_DIR, os.path.basename(file_path))
        file_size = os.path.getsize(local_file) if os.path.exists(local_file) else 0

        try:
            response = requests.post(
                f'{self.portal_url}/api/pod/recordings/confirm',
                headers=self.headers,
                json={
                    'camera_id': camera_id,
                    'file_path': file_path,
                    'file_size_bytes': file_size,
                    'duration_seconds': duration_seconds,
                    'event_type': event_type,
                    'plate_number': plate_number,
                    'metadata': metadata or {}
                }
            )

            if response.status_code != 200:
                print(f'[Upload] Failed to confirm: {response.text}')
                return None

            data = response.json()
            print(f'[Upload] Recording confirmed: {data["recording"]["id"]}')
            return data['recording']

        except Exception as e:
            print(f'[Upload] Error confirming upload: {e}')
            return None

    def upload_recording(self, local_file_path, camera_id, event_type='manual',
                        plate_number=None, duration_seconds=0, metadata=None):
        """
        Complete upload workflow: request URL -> upload -> confirm
        """
        print('=' * 60)
        print(f'Starting upload: {local_file_path}')
        print('=' * 60)

        if not os.path.exists(local_file_path):
            print(f'[Error] File not found: {local_file_path}')
            return False

        filename = os.path.basename(local_file_path)

        # Step 1: Request upload URL
        upload_data = self.request_upload_url(camera_id, filename)
        if not upload_data:
            return False

        # Step 2: Upload file
        success = self.upload_file(local_file_path, upload_data['signed_url'])
        if not success:
            return False

        # Step 3: Confirm upload
        recording = self.confirm_upload(
            camera_id=camera_id,
            file_path=upload_data['file_path'],
            duration_seconds=duration_seconds,
            event_type=event_type,
            plate_number=plate_number,
            metadata=metadata
        )

        if recording:
            print('[Success] Recording uploaded successfully!')
            print(f'Recording ID: {recording["id"]}')
            return True

        return False


def record_clip(output_file, duration=30, rtsp_url=None):
    """
    Record a video clip from camera using ffmpeg.

    Args:
        output_file: Path to save the recording
        duration: Duration in seconds
        rtsp_url: RTSP URL of camera
    """
    rtsp_url = rtsp_url or os.getenv('CAMERA_RTSP_URL', 'rtsp://camera-ip:554/stream')

    print(f'[Record] Recording {duration}s clip from {rtsp_url}...')

    cmd = [
        'ffmpeg',
        '-rtsp_transport', 'tcp',
        '-i', rtsp_url,
        '-t', str(duration),
        '-c', 'copy',
        '-y',  # Overwrite output file
        output_file
    ]

    try:
        import subprocess
        result = subprocess.run(cmd, capture_output=True, text=True)

        if result.returncode == 0:
            print(f'[Record] Clip saved: {output_file}')
            return True
        else:
            print(f'[Record] Failed: {result.stderr}')
            return False

    except Exception as e:
        print(f'[Record] Error: {e}')
        return False


def main():
    """Example usage"""

    if POD_API_KEY == 'pbk_your_api_key_here':
        print('[Error] Please set POD_API_KEY environment variable')
        print('Get your API key from the portal: /pods page')
        return

    if CAMERA_ID == 'your-camera-uuid':
        print('[Error] Please set CAMERA_ID environment variable')
        return

    uploader = RecordingUploader(PORTAL_URL, POD_API_KEY)

    # Example 1: Upload existing file
    print('\nExample 1: Upload existing file')
    existing_file = '/tmp/test_video.mp4'
    if os.path.exists(existing_file):
        uploader.upload_recording(
            local_file_path=existing_file,
            camera_id=CAMERA_ID,
            event_type='manual',
            duration_seconds=30
        )
    else:
        print(f'File not found: {existing_file}')

    # Example 2: Record and upload on plate detection
    print('\nExample 2: Record clip on plate detection')
    timestamp = datetime.now().strftime('%Y%m%d_%H%M%S')
    output_file = os.path.join(RECORDINGS_DIR, f'plate_detection_{timestamp}.mp4')

    # Record 10 second clip
    if record_clip(output_file, duration=10):
        uploader.upload_recording(
            local_file_path=output_file,
            camera_id=CAMERA_ID,
            event_type='plate_detection',
            plate_number='ABC123',
            duration_seconds=10,
            metadata={
                'confidence': 0.95,
                'timestamp': timestamp
            }
        )

        # Clean up local file after upload
        os.remove(output_file)
        print(f'[Cleanup] Removed local file: {output_file}')


if __name__ == '__main__':
    print('=' * 60)
    print('PlateBridge Recording Uploader')
    print('=' * 60)
    print(f'Portal URL: {PORTAL_URL}')
    print(f'Camera ID: {CAMERA_ID}')
    print(f'API Key: {POD_API_KEY[:10]}...')
    print('=' * 60)
    print()

    main()
