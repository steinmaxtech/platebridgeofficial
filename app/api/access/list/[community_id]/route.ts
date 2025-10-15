import { createClient } from '@/lib/supabase-server';
import { NextRequest, NextResponse } from 'next/server';

async function hashApiKey(apiKey: string): Promise<string> {
  const encoder = new TextEncoder();
  const data = encoder.encode(apiKey);
  const hashBuffer = await crypto.subtle.digest('SHA-256', data);
  const hashArray = Array.from(new Uint8Array(hashBuffer));
  const hashHex = hashArray.map(b => b.toString(16).padStart(2, '0')).join('');
  return hashHex;
}

async function verifyApiKey(authHeader: string | null, supabase: any) {
  if (!authHeader || !authHeader.startsWith('Bearer ')) {
    return null;
  }

  const apiKey = authHeader.substring(7);

  if (!apiKey.startsWith('pbk_')) {
    return null;
  }

  try {
    const keyHash = await hashApiKey(apiKey);

    const { data: keyData, error } = await supabase
      .from('pod_api_keys')
      .select('id, community_id, pod_id, revoked_at')
      .eq('key_hash', keyHash)
      .maybeSingle();

    if (error || !keyData || keyData.revoked_at) {
      return null;
    }

    return keyData;
  } catch (error) {
    return null;
  }
}

/**
 * GET /api/access/list/:community_id
 * Returns all active access list entries for a community
 * Used by PODs to cache the list locally
 */
export async function GET(
  request: NextRequest,
  { params }: { params: { community_id: string } }
) {
  try {
    const supabase = createClient();
    const { community_id } = params;

    if (!community_id) {
      return NextResponse.json(
        { error: 'Missing community_id' },
        { status: 400 }
      );
    }

    // Verify API key authentication
    const authHeader = request.headers.get('Authorization');
    const apiKeyData = await verifyApiKey(authHeader, supabase);

    if (!apiKeyData) {
      return NextResponse.json(
        { error: 'Invalid or revoked API key' },
        { status: 401 }
      );
    }

    // Verify the API key belongs to this community
    if (apiKeyData.community_id !== community_id) {
      return NextResponse.json(
        { error: 'API key does not have access to this community' },
        { status: 403 }
      );
    }

    // Get community settings
    const { data: settings } = await supabase
      .from('community_access_settings')
      .select('*')
      .eq('community_id', community_id)
      .single();

    // Get active access list entries
    const { data: accessList, error } = await supabase
      .from('access_lists')
      .select('*')
      .eq('community_id', community_id)
      .eq('is_active', true)
      .or('expires_at.is.null,expires_at.gt.now()')
      .order('type', { ascending: true });

    if (error) {
      console.error('Error fetching access list:', error);
      return NextResponse.json(
        { error: 'Failed to fetch access list' },
        { status: 500 }
      );
    }

    return NextResponse.json({
      settings: settings || {
        auto_grant_enabled: true,
        lockdown_mode: false,
        require_confidence: 85,
      },
      access_list: accessList || [],
      count: accessList?.length || 0,
      last_updated: new Date().toISOString(),
    });
  } catch (error) {
    console.error('Error in access list:', error);
    return NextResponse.json(
      { error: 'Internal server error' },
      { status: 500 }
    );
  }
}
