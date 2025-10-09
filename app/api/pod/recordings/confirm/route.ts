import { NextRequest, NextResponse } from 'next/server';
import { supabaseServer } from '@/lib/supabase-server';

export const dynamic = 'force-dynamic';

async function hashApiKey(apiKey: string): Promise<string> {
  const encoder = new TextEncoder();
  const data = encoder.encode(apiKey);
  const hashBuffer = await crypto.subtle.digest('SHA-256', data);
  const hashArray = Array.from(new Uint8Array(hashBuffer));
  const hashHex = hashArray.map(b => b.toString(16).padStart(2, '0')).join('');
  return hashHex;
}

async function verifyPodApiKey(authHeader: string | null) {
  if (!authHeader || !authHeader.startsWith('Bearer ')) {
    return null;
  }

  const apiKey = authHeader.substring(7);

  if (!apiKey.startsWith('pbk_')) {
    return null;
  }

  try {
    const keyHash = await hashApiKey(apiKey);

    const { data: keyData, error } = await supabaseServer
      .from('pod_api_keys')
      .select('id, pod_id, community_id, revoked_at')
      .eq('key_hash', keyHash)
      .maybeSingle();

    if (error || !keyData || keyData.revoked_at) {
      return null;
    }

    return keyData;
  } catch (error) {
    console.error('[POD API Key] Verification error:', error);
    return null;
  }
}

export async function POST(request: NextRequest) {
  try {
    const authHeader = request.headers.get('Authorization');
    const apiKeyData = await verifyPodApiKey(authHeader);

    if (!apiKeyData) {
      return NextResponse.json(
        { error: 'Invalid or revoked API key' },
        { status: 401 }
      );
    }

    const {
      camera_id,
      file_path,
      file_size_bytes,
      duration_seconds,
      event_type,
      plate_number,
      thumbnail_path,
      metadata
    } = await request.json();

    if (!camera_id || !file_path) {
      return NextResponse.json(
        { error: 'camera_id and file_path are required' },
        { status: 400 }
      );
    }

    // Verify POD owns this camera
    const { data: camera, error: cameraError } = await supabaseServer
      .from('cameras')
      .select('id, pod_id')
      .eq('id', camera_id)
      .eq('pod_id', apiKeyData.pod_id)
      .maybeSingle();

    if (cameraError || !camera) {
      console.error('[Recording Confirm] Camera verification failed:', cameraError);
      return NextResponse.json(
        { error: 'Camera not found or access denied' },
        { status: 403 }
      );
    }

    // Create recording record in database
    const { data: recording, error: recordingError } = await supabaseServer
      .from('camera_recordings')
      .insert({
        camera_id,
        pod_id: apiKeyData.pod_id,
        file_path,
        file_size_bytes: file_size_bytes || 0,
        duration_seconds: duration_seconds || 0,
        event_type: event_type || 'manual',
        plate_number,
        thumbnail_path,
        metadata: metadata || {}
      })
      .select()
      .single();

    if (recordingError) {
      console.error('[Recording Confirm] Failed to create record:', recordingError);
      return NextResponse.json(
        { error: 'Failed to create recording record', details: recordingError.message },
        { status: 500 }
      );
    }

    // Update camera's last_recording_at timestamp
    await supabaseServer
      .from('cameras')
      .update({ last_recording_at: new Date().toISOString() })
      .eq('id', camera_id);

    return NextResponse.json({
      success: true,
      recording: {
        id: recording.id,
        camera_id: recording.camera_id,
        recorded_at: recording.recorded_at,
        duration_seconds: recording.duration_seconds,
        event_type: recording.event_type
      }
    });
  } catch (error: any) {
    console.error('[Recording Confirm] Error:', error);
    return NextResponse.json(
      { error: 'Internal server error', details: error.message },
      { status: 500 }
    );
  }
}
