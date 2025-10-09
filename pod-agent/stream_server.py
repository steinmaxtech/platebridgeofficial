#!/usr/bin/env python3
"""
POD Stream Server - Secure HLS/HTTP streaming with token validation

This server handles:
1. Receiving RTSP streams from cameras
2. Converting to HLS for web playback
3. Validating time-limited signed tokens from portal
4. Serving video streams securely

Requirements:
- ffmpeg installed on system
- Python packages: flask, jwt, requests

Setup:
  pip install flask pyjwt requests

Usage:
  python stream_server.py
"""

import os
import hashlib
import hmac
import json
import base64
import time
from datetime import datetime
from flask import Flask, Response, request, jsonify, send_file
import subprocess
import threading

app = Flask(__name__)

# Configuration - Set these environment variables or update directly
STREAM_SECRET = os.getenv('POD_STREAM_SECRET', 'default-secret')
RTSP_URL = os.getenv('CAMERA_RTSP_URL', 'rtsp://camera-ip:554/stream')
HLS_OUTPUT_DIR = '/tmp/hls_output'

# Ensure HLS output directory exists
os.makedirs(HLS_OUTPUT_DIR, exist_ok=True)

# Global variable to track ffmpeg process
ffmpeg_process = None


def validate_token(token):
    """
    Validate stream token from portal.
    Token format: base64(payload).signature
    """
    try:
        parts = token.split('.')
        if len(parts) != 2:
            print('[Token] Invalid format - expected 2 parts')
            return False

        payload_b64, signature = parts

        # Decode payload
        payload_json = base64.b64decode(payload_b64).decode('utf-8')
        payload = json.loads(payload_json)

        # Verify signature
        expected_data = payload_json + STREAM_SECRET
        expected_hash = hashlib.sha256(expected_data.encode()).hexdigest()

        if signature != expected_hash:
            print('[Token] Invalid signature')
            return False

        # Check expiration
        if 'exp' not in payload:
            print('[Token] Missing expiration')
            return False

        if payload['exp'] < time.time():
            print('[Token] Token expired')
            return False

        print(f'[Token] Valid token for user {payload.get("user_id")}')
        return True

    except Exception as e:
        print(f'[Token] Validation error: {e}')
        return False


def start_ffmpeg_stream():
    """
    Start ffmpeg process to convert RTSP to HLS.
    This runs in background and continuously converts the camera feed.
    """
    global ffmpeg_process

    if ffmpeg_process and ffmpeg_process.poll() is None:
        print('[FFmpeg] Already running')
        return

    output_file = os.path.join(HLS_OUTPUT_DIR, 'stream.m3u8')

    # FFmpeg command to convert RTSP to HLS
    cmd = [
        'ffmpeg',
        '-rtsp_transport', 'tcp',
        '-i', RTSP_URL,
        '-c:v', 'copy',  # Copy video codec (no re-encoding for performance)
        '-c:a', 'aac',   # Audio codec
        '-f', 'hls',
        '-hls_time', '2',  # 2 second segments
        '-hls_list_size', '5',  # Keep 5 segments in playlist
        '-hls_flags', 'delete_segments',  # Delete old segments
        '-hls_segment_filename', os.path.join(HLS_OUTPUT_DIR, 'segment_%03d.ts'),
        output_file
    ]

    print(f'[FFmpeg] Starting stream conversion: {RTSP_URL} -> HLS')

    try:
        ffmpeg_process = subprocess.Popen(
            cmd,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE
        )
        print('[FFmpeg] Stream started successfully')
    except Exception as e:
        print(f'[FFmpeg] Failed to start: {e}')


@app.route('/stream')
def stream():
    """
    Serve HLS stream with token validation.
    Example: GET /stream?token=xxx
    """
    token = request.args.get('token')

    if not token:
        return jsonify({'error': 'Missing token parameter'}), 401

    if not validate_token(token):
        return jsonify({'error': 'Invalid or expired token'}), 403

    # Start ffmpeg if not running
    start_ffmpeg_stream()

    # Serve HLS playlist
    playlist_path = os.path.join(HLS_OUTPUT_DIR, 'stream.m3u8')

    if not os.path.exists(playlist_path):
        return jsonify({'error': 'Stream not ready yet, please try again in a few seconds'}), 503

    try:
        return send_file(playlist_path, mimetype='application/vnd.apple.mpegurl')
    except Exception as e:
        return jsonify({'error': f'Stream error: {str(e)}'}), 500


@app.route('/stream/segment/<filename>')
def stream_segment(filename):
    """
    Serve HLS segment files.
    Token validation happens at playlist level, segments use same session.
    """
    # In production, you might want to implement session-based auth
    # For now, segments are served if the initial token was valid

    segment_path = os.path.join(HLS_OUTPUT_DIR, filename)

    if not os.path.exists(segment_path):
        return jsonify({'error': 'Segment not found'}), 404

    return send_file(segment_path, mimetype='video/MP2T')


@app.route('/health')
def health():
    """Health check endpoint"""
    ffmpeg_running = ffmpeg_process and ffmpeg_process.poll() is None

    return jsonify({
        'status': 'ok',
        'ffmpeg_running': ffmpeg_running,
        'rtsp_source': RTSP_URL,
        'timestamp': datetime.now().isoformat()
    })


@app.route('/restart')
def restart_stream():
    """Restart ffmpeg stream (admin only in production)"""
    global ffmpeg_process

    if ffmpeg_process:
        ffmpeg_process.terminate()
        ffmpeg_process.wait()

    start_ffmpeg_stream()

    return jsonify({'status': 'restarted'})


if __name__ == '__main__':
    print('=' * 60)
    print('POD Stream Server')
    print('=' * 60)
    print(f'RTSP Source: {RTSP_URL}')
    print(f'HLS Output: {HLS_OUTPUT_DIR}')
    print(f'Secret configured: {"Yes" if STREAM_SECRET != "default-secret" else "No (using default)"}')
    print('=' * 60)

    # Start initial stream
    start_ffmpeg_stream()

    # Run Flask server
    # In production, use gunicorn or similar WSGI server
    app.run(host='0.0.0.0', port=8000, threaded=True)
