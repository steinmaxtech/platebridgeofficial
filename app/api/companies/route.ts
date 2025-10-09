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

async function verifyApiKey(authHeader: string | null) {
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
      .select('id, community_id, revoked_at')
      .eq('key_hash', keyHash)
      .maybeSingle();

    if (error || !keyData || keyData.revoked_at) {
      return null;
    }

    return keyData;
  } catch (error) {
    console.error('[API Companies] Error:', error);
    return null;
  }
}

export async function GET(request: NextRequest) {
  try {
    const authHeader = request.headers.get('Authorization');
    const keyData = await verifyApiKey(authHeader);

    if (!keyData) {
      return NextResponse.json(
        { error: 'Invalid or revoked API key' },
        { status: 401 }
      );
    }

    const { data: community, error } = await supabaseServer
      .from('communities')
      .select(`
        id,
        name,
        sites:sites(
          id,
          name
        )
      `)
      .eq('id', keyData.community_id)
      .maybeSingle();

    if (error) {
      console.error('[API Companies] Error fetching community:', error);
      return NextResponse.json(
        { error: 'Failed to fetch community data' },
        { status: 500 }
      );
    }

    if (!community) {
      return NextResponse.json(
        { error: 'Community not found' },
        { status: 404 }
      );
    }

    return NextResponse.json({
      companies: [{
        id: community.id,
        name: community.name,
        sites: community.sites || []
      }]
    });
  } catch (error: any) {
    console.error('[API Companies] Error:', error);
    return NextResponse.json(
      { error: 'Internal server error' },
      { status: 500 }
    );
  }
}
