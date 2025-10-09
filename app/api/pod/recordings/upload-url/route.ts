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

    const { camera_id, filename, content_type } = await request.json();

    if (!camera_id || !filename) {
      return NextResponse.json(
        { error: 'camera_id and filename are required' },
        { status: 400 }
      );
    }

    // Verify POD owns this camera
    const { data: camera, error: cameraError } = await supabaseServer
      .from('cameras')
      .select('id, pod_id, name')
      .eq('id', camera_id)
      .eq('pod_id', apiKeyData.pod_id)
      .maybeSingle();

    if (cameraError || !camera) {
      console.error('[Recording Upload] Camera verification failed:', cameraError);
      return NextResponse.json(
        { error: 'Camera not found or access denied' },
        { status: 403 }
      );
    }

    // Generate storage path: recordings/{community_id}/{camera_id}/{filename}
    const timestamp = new Date().toISOString().replace(/[:.]/g, '-');
    const sanitizedFilename = filename.replace(/[^a-zA-Z0-9._-]/g, '_');
    const filePath = `recordings/${apiKeyData.community_id}/${camera_id}/${timestamp}_${sanitizedFilename}`;

    // Create signed upload URL (expires in 1 hour)
    const { data: uploadData, error: uploadError } = await supabaseServer
      .storage
      .from('camera-recordings')
      .createSignedUploadUrl(filePath);

    if (uploadError) {
      console.error('[Recording Upload] Failed to create signed URL:', uploadError);
      return NextResponse.json(
        { error: 'Failed to generate upload URL', details: uploadError.message },
        { status: 500 }
      );
    }

    return NextResponse.json({
      success: true,
      signed_url: uploadData.signedUrl,
      file_path: filePath,
      expires_in: 3600,
      upload_token: uploadData.token
    });
  } catch (error: any) {
    console.error('[Recording Upload] Error:', error);
    return NextResponse.json(
      { error: 'Internal server error', details: error.message },
      { status: 500 }
    );
  }
}
