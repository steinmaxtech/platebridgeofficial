import { NextRequest, NextResponse } from 'next/server';
import { supabaseServer } from '@/lib/supabase-server';
import { createClient } from '@supabase/supabase-js';

export const dynamic = 'force-dynamic';

async function generateStreamToken(payload: any, secret: string): Promise<string> {
  const encoder = new TextEncoder();
  const data = encoder.encode(JSON.stringify(payload) + secret);
  const hashBuffer = await crypto.subtle.digest('SHA-256', data);
  const hashArray = Array.from(new Uint8Array(hashBuffer));
  const signature = hashArray.map(b => b.toString(16).padStart(2, '0')).join('');

  const token = Buffer.from(JSON.stringify(payload)).toString('base64') + '.' + signature;
  return token;
}

export async function GET(
  request: NextRequest,
  { params }: { params: { pod_id: string } }
) {
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

    const { pod_id } = params;
    const { searchParams } = new URL(request.url);
    const cameraId = searchParams.get('camera_id');

    const { data: pod, error: podError } = await supabaseServer
      .from('pods')
      .select(`
        id,
        name,
        ip_address,
        stream_token_secret,
        sites!inner (
          id,
          communities!inner (
            id,
            company_id
          )
        )
      `)
      .eq('id', pod_id)
      .single();

    if (podError || !pod) {
      return NextResponse.json(
        { error: 'POD not found' },
        { status: 404 }
      );
    }

    const expiresAt = Math.floor(Date.now() / 1000) + 3600;
    const tokenPayload = {
      user_id: user.id,
      pod_id: pod.id,
      camera_id: cameraId || 'all',
      exp: expiresAt
    };

    const secret = pod.stream_token_secret || process.env.POD_STREAM_SECRET || 'default-secret';
    const streamToken = await generateStreamToken(tokenPayload, secret);

    const podInternalUrl = `http://${pod.ip_address || '127.0.0.1'}:8000/stream?token=${encodeURIComponent(streamToken)}`;

    const podResponse = await fetch(podInternalUrl, {
      method: 'GET',
      headers: {
        'Accept': 'application/vnd.apple.mpegurl,video/*',
      },
      signal: AbortSignal.timeout(10000),
    });

    if (!podResponse.ok) {
      return NextResponse.json(
        { error: 'Failed to connect to POD', status: podResponse.status },
        { status: 502 }
      );
    }

    const contentType = podResponse.headers.get('content-type') || 'application/vnd.apple.mpegurl';
    const stream = podResponse.body;

    return new NextResponse(stream, {
      headers: {
        'Content-Type': contentType,
        'Cache-Control': 'no-cache, no-store, must-revalidate',
        'Access-Control-Allow-Origin': '*',
      },
    });

  } catch (error: any) {
    console.error('[Proxy Stream] Error:', error);
    return NextResponse.json(
      { error: 'Internal server error', details: error.message },
      { status: 500 }
    );
  }
}
