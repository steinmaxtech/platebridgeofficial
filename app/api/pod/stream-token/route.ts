import { NextRequest, NextResponse } from 'next/server';
import { supabaseServer } from '@/lib/supabase-server';
import { createClient } from '@supabase/supabase-js';

export const dynamic = 'force-dynamic';

// JWT-like token generation (simple implementation)
async function generateStreamToken(payload: any, secret: string): Promise<string> {
  const encoder = new TextEncoder();
  const data = encoder.encode(JSON.stringify(payload) + secret);
  const hashBuffer = await crypto.subtle.digest('SHA-256', data);
  const hashArray = Array.from(new Uint8Array(hashBuffer));
  const signature = hashArray.map(b => b.toString(16).padStart(2, '0')).join('');

  const token = Buffer.from(JSON.stringify(payload)).toString('base64') + '.' + signature;
  return token;
}

export async function POST(request: NextRequest) {
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

    const { camera_id } = await request.json();

    if (!camera_id) {
      return NextResponse.json(
        { error: 'camera_id is required' },
        { status: 400 }
      );
    }

    // Verify user has access to this camera (via company membership)
    const { data: camera, error: cameraError } = await supabaseServer
      .from('cameras')
      .select(`
        id,
        name,
        stream_url,
        pod_id,
        pods!inner (
          id,
          stream_token_secret,
          sites!inner (
            id,
            communities!inner (
              id,
              company_id
            )
          )
        )
      `)
      .eq('id', camera_id)
      .maybeSingle();

    if (cameraError || !camera) {
      console.error('[Stream Token] Camera lookup error:', cameraError);
      return NextResponse.json(
        { error: 'Camera not found' },
        { status: 404 }
      );
    }

    // Check if user has membership to this company
    const companyId = (camera.pods as any).sites.communities.company_id;

    const { data: membership, error: membershipError } = await supabaseServer
      .from('memberships')
      .select('id')
      .eq('user_id', user.id)
      .eq('company_id', companyId)
      .maybeSingle();

    if (membershipError || !membership) {
      return NextResponse.json(
        { error: 'Access denied to this camera' },
        { status: 403 }
      );
    }

    // Generate stream token
    const expiresAt = Math.floor(Date.now() / 1000) + (10 * 60); // 10 minutes
    const tokenPayload = {
      user_id: user.id,
      camera_id: camera.id,
      pod_id: camera.pod_id,
      exp: expiresAt
    };

    // Use pod's secret or fallback to shared secret
    const secret = (camera.pods as any).stream_token_secret || process.env.POD_STREAM_SECRET || 'default-secret';
    const streamToken = await generateStreamToken(tokenPayload, secret);

    // Build stream URL with token
    const baseStreamUrl = camera.stream_url || `https://pod-${camera.pod_id}.local:8000/stream`;
    const streamUrlWithToken = `${baseStreamUrl}?token=${encodeURIComponent(streamToken)}`;

    return NextResponse.json({
      success: true,
      token: streamToken,
      stream_url: streamUrlWithToken,
      expires_at: expiresAt,
      expires_in: 600,
      camera: {
        id: camera.id,
        name: camera.name
      }
    });
  } catch (error: any) {
    console.error('[Stream Token] Error:', error);
    return NextResponse.json(
      { error: 'Internal server error', details: error.message },
      { status: 500 }
    );
  }
}
