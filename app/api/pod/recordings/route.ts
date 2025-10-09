import { NextRequest, NextResponse } from 'next/server';
import { supabaseServer } from '@/lib/supabase-server';
import { createClient } from '@supabase/supabase-js';

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

async function generateRecordingToken(payload: any, secret: string): Promise<string> {
  const encoder = new TextEncoder();
  const data = encoder.encode(JSON.stringify(payload) + secret);
  const hashBuffer = await crypto.subtle.digest('SHA-256', data);
  const hashArray = Array.from(new Uint8Array(hashBuffer));
  const signature = hashArray.map(b => b.toString(16).padStart(2, '0')).join('');

  const token = Buffer.from(JSON.stringify(payload)).toString('base64') + '.' + signature;
  return token;
}

export async function GET(request: NextRequest) {
  try {
    const authHeader = request.headers.get('Authorization');

    if (!authHeader || !authHeader.startsWith('Bearer ')) {
      return NextResponse.json(
        { error: 'Missing authorization header' },
        { status: 401 }
      );
    }

    const token = authHeader.substring(7);

    const supabaseUrl = process.env.NEXT_PUBLIC_SUPABASE_URL!;
    const supabaseAnonKey = process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY!;
    const supabase = createClient(supabaseUrl, supabaseAnonKey, {
      global: {
        headers: {
          Authorization: `Bearer ${token}`
        }
      }
    });

    const { data: { user }, error: userError } = await supabase.auth.getUser();

    if (userError || !user) {
      return NextResponse.json(
        { error: 'Invalid session token' },
        { status: 401 }
      );
    }

    const { searchParams } = new URL(request.url);
    const cameraId = searchParams.get('camera_id');
    const limit = parseInt(searchParams.get('limit') || '50');
    const offset = parseInt(searchParams.get('offset') || '0');
    const eventType = searchParams.get('event_type');
    const plateNumber = searchParams.get('plate_number');

    let query = supabase
      .from('camera_recordings')
      .select(`
        id,
        camera_id,
        recorded_at,
        duration_seconds,
        file_path,
        file_size_bytes,
        event_type,
        plate_number,
        thumbnail_path,
        cameras!inner (
          id,
          name,
          stream_url,
          pods!inner (
            id,
            name,
            stream_token_secret,
            sites!inner (
              id,
              name,
              communities!inner (
                id,
                name,
                company_id
              )
            )
          )
        )
      `)
      .order('recorded_at', { ascending: false })
      .range(offset, offset + limit - 1);

    if (cameraId) {
      query = query.eq('camera_id', cameraId);
    }

    if (eventType) {
      query = query.eq('event_type', eventType);
    }

    if (plateNumber) {
      query = query.ilike('plate_number', `%${plateNumber}%`);
    }

    const { data: recordings, error: recordingsError } = await query;

    if (recordingsError) {
      console.error('[Recordings API] Query error:', recordingsError);
      return NextResponse.json(
        { error: 'Failed to fetch recordings', details: recordingsError.message },
        { status: 500 }
      );
    }

    const recordingsWithUrls = await Promise.all(
      (recordings || []).map(async (recording) => {
        const camera = recording.cameras as any;
        const pod = camera.pods;

        const expiresAt = Math.floor(Date.now() / 1000) + (3600);
        const tokenPayload = {
          user_id: user.id,
          camera_id: recording.camera_id,
          recording_id: recording.id,
          file_path: recording.file_path,
          exp: expiresAt
        };

        const secret = pod.stream_token_secret || process.env.POD_STREAM_SECRET || 'default-secret';
        const recordingToken = await generateRecordingToken(tokenPayload, secret);

        const baseUrl = camera.stream_url ? camera.stream_url.replace('/stream', '') : `https://pod-${pod.id}.local:8000`;
        const videoUrl = `${baseUrl}/recording/${recording.id}?token=${encodeURIComponent(recordingToken)}`;

        let thumbnailUrl = null;
        if (recording.thumbnail_path) {
          thumbnailUrl = `${baseUrl}/thumbnail/${recording.id}?token=${encodeURIComponent(recordingToken)}`;
        }

        return {
          id: recording.id,
          camera_id: recording.camera_id,
          camera_name: camera.name,
          pod_name: pod.name,
          pod_url: baseUrl,
          site_name: pod.sites.name,
          community_name: pod.sites.communities.name,
          recorded_at: recording.recorded_at,
          duration_seconds: recording.duration_seconds,
          file_size_bytes: recording.file_size_bytes,
          event_type: recording.event_type,
          plate_number: recording.plate_number,
          file_path: recording.file_path,
          video_url: videoUrl,
          thumbnail_url: thumbnailUrl,
          expires_in: 3600
        };
      })
    );

    return NextResponse.json({
      success: true,
      recordings: recordingsWithUrls,
      count: recordingsWithUrls.length,
      offset,
      limit
    });
  } catch (error: any) {
    console.error('[Recordings API] Error:', error);
    return NextResponse.json(
      { error: 'Internal server error', details: error.message },
      { status: 500 }
    );
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

    const { data: camera, error: cameraError } = await supabaseServer
      .from('cameras')
      .select('id, pod_id')
      .eq('id', camera_id)
      .eq('pod_id', apiKeyData.pod_id)
      .maybeSingle();

    if (cameraError || !camera) {
      console.error('[Recording Register] Camera verification failed:', cameraError);
      return NextResponse.json(
        { error: 'Camera not found or access denied' },
        { status: 403 }
      );
    }

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
      console.error('[Recording Register] Failed to create record:', recordingError);
      return NextResponse.json(
        { error: 'Failed to create recording record', details: recordingError.message },
        { status: 500 }
      );
    }

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
    console.error('[Recording Register] Error:', error);
    return NextResponse.json(
      { error: 'Internal server error', details: error.message },
      { status: 500 }
    );
  }
}
