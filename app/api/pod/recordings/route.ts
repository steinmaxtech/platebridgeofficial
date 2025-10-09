import { NextRequest, NextResponse } from 'next/server';
import { supabaseServer } from '@/lib/supabase-server';
import { createClient } from '@supabase/supabase-js';

export const dynamic = 'force-dynamic';

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

    // Get user from session token
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

    // Parse query parameters
    const { searchParams } = new URL(request.url);
    const cameraId = searchParams.get('camera_id');
    const limit = parseInt(searchParams.get('limit') || '50');
    const offset = parseInt(searchParams.get('offset') || '0');
    const eventType = searchParams.get('event_type');
    const plateNumber = searchParams.get('plate_number');

    // Build query
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
          pods!inner (
            id,
            name,
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

    // Generate signed URLs for each recording
    const recordingsWithUrls = await Promise.all(
      (recordings || []).map(async (recording) => {
        const { data: signedUrlData } = await supabaseServer
          .storage
          .from('camera-recordings')
          .createSignedUrl(recording.file_path, 3600); // 1 hour expiry

        let thumbnailUrl = null;
        if (recording.thumbnail_path) {
          const { data: thumbData } = await supabaseServer
            .storage
            .from('camera-recordings')
            .createSignedUrl(recording.thumbnail_path, 3600);
          thumbnailUrl = thumbData?.signedUrl || null;
        }

        return {
          id: recording.id,
          camera_id: recording.camera_id,
          camera_name: (recording.cameras as any).name,
          pod_name: (recording.cameras as any).pods.name,
          site_name: (recording.cameras as any).pods.sites.name,
          community_name: (recording.cameras as any).pods.sites.communities.name,
          recorded_at: recording.recorded_at,
          duration_seconds: recording.duration_seconds,
          file_size_bytes: recording.file_size_bytes,
          event_type: recording.event_type,
          plate_number: recording.plate_number,
          video_url: signedUrlData?.signedUrl || null,
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
