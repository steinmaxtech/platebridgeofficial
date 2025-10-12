import { NextRequest, NextResponse } from 'next/server';
import { supabaseServer } from '@/lib/supabase-server';

export async function POST(request: NextRequest) {
  try {
    const authHeader = request.headers.get('Authorization');
    if (!authHeader || !authHeader.startsWith('Bearer ')) {
      return NextResponse.json({ error: 'Unauthorized' }, { status: 401 });
    }

    const token = authHeader.substring(7);
    const { data: { user }, error: authError } = await supabaseServer.auth.getUser(token);

    if (authError || !user) {
      return NextResponse.json({ error: 'Unauthorized' }, { status: 401 });
    }

    const { name, site_id, pod_id } = await request.json();

    if (!name || !site_id || !pod_id) {
      return NextResponse.json(
        { error: 'Missing required fields: name, site_id, pod_id' },
        { status: 400 }
      );
    }

    // Get the community_id from the site
    const { data: siteData, error: siteError } = await supabaseServer
      .from('sites')
      .select('community_id')
      .eq('id', site_id)
      .single();

    if (siteError || !siteData) {
      return NextResponse.json(
        { error: 'Invalid site ID' },
        { status: 400 }
      );
    }

    const apiKey = `pbk_${generateRandomString(32)}`;
    const hashedKey = await hashApiKey(apiKey);

    const { data: keyData, error: keyError } = await supabaseServer
      .from('pod_api_keys')
      .insert({
        name,
        community_id: siteData.community_id,
        pod_id,
        key_hash: hashedKey,
        created_by: user.id,
      })
      .select()
      .single();

    if (keyError) {
      console.error('Error creating API key:', keyError);
      return NextResponse.json(
        { error: 'Failed to create API key' },
        { status: 500 }
      );
    }

    return NextResponse.json({
      message: 'API key created successfully',
      api_key: apiKey,
      id: keyData.id,
      name: keyData.name,
      site_id: site_id,
      community_id: keyData.community_id,
      pod_id: keyData.pod_id,
      created_at: keyData.created_at,
      warning: 'Save this API key now. You will not be able to see it again.',
    });
  } catch (error) {
    console.error('Error in POST /api/pod/api-keys:', error);
    return NextResponse.json(
      { error: 'Internal server error' },
      { status: 500 }
    );
  }
}

export async function GET(request: NextRequest) {
  try {
    const authHeader = request.headers.get('Authorization');
    if (!authHeader || !authHeader.startsWith('Bearer ')) {
      return NextResponse.json({ error: 'Unauthorized' }, { status: 401 });
    }

    const token = authHeader.substring(7);
    const { data: { user }, error: authError } = await supabaseServer.auth.getUser(token);

    if (authError || !user) {
      return NextResponse.json({ error: 'Unauthorized' }, { status: 401 });
    }

    const { data: keys, error } = await supabaseServer
      .from('pod_api_keys')
      .select(`
        id,
        name,
        community_id,
        pod_id,
        created_at,
        last_used_at,
        communities!inner(id)
      `)
      .is('revoked_at', null)
      .order('created_at', { ascending: false });

    // Get site information for each key
    if (keys && keys.length > 0) {
      const communityIds = keys.map(k => k.community_id);
      const { data: sites } = await supabaseServer
        .from('sites')
        .select('id, community_id')
        .in('community_id', communityIds);

      // Map community_id to site_id (take first site in each community)
      const communityToSite = new Map();
      sites?.forEach(site => {
        if (!communityToSite.has(site.community_id)) {
          communityToSite.set(site.community_id, site.id);
        }
      });

      // Add site_id to each key
      keys.forEach(key => {
        (key as any).site_id = communityToSite.get(key.community_id) || key.community_id;
      });
    }

    if (error) {
      console.error('Error fetching API keys:', error);
      return NextResponse.json(
        { error: 'Failed to fetch API keys' },
        { status: 500 }
      );
    }

    return NextResponse.json({ keys });
  } catch (error) {
    console.error('Error in GET /api/pod/api-keys:', error);
    return NextResponse.json(
      { error: 'Internal server error' },
      { status: 500 }
    );
  }
}

export async function DELETE(request: NextRequest) {
  try {
    const authHeader = request.headers.get('Authorization');
    if (!authHeader || !authHeader.startsWith('Bearer ')) {
      return NextResponse.json({ error: 'Unauthorized' }, { status: 401 });
    }

    const token = authHeader.substring(7);
    const { data: { user }, error: authError } = await supabaseServer.auth.getUser(token);

    if (authError || !user) {
      return NextResponse.json({ error: 'Unauthorized' }, { status: 401 });
    }

    const { searchParams } = new URL(request.url);
    const keyId = searchParams.get('id');

    if (!keyId) {
      return NextResponse.json(
        { error: 'Missing key ID' },
        { status: 400 }
      );
    }

    const { error } = await supabaseServer
      .from('pod_api_keys')
      .update({ revoked_at: new Date().toISOString() })
      .eq('id', keyId);

    if (error) {
      console.error('Error deleting API key:', error);
      return NextResponse.json(
        { error: 'Failed to delete API key' },
        { status: 500 }
      );
    }

    return NextResponse.json({ message: 'API key deleted successfully' });
  } catch (error) {
    console.error('Error in DELETE /api/pod/api-keys:', error);
    return NextResponse.json(
      { error: 'Internal server error' },
      { status: 500 }
    );
  }
}

function generateRandomString(length: number): string {
  const chars = 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789';
  let result = '';
  const randomValues = new Uint8Array(length);
  crypto.getRandomValues(randomValues);

  for (let i = 0; i < length; i++) {
    result += chars[randomValues[i] % chars.length];
  }

  return result;
}

async function hashApiKey(apiKey: string): Promise<string> {
  const encoder = new TextEncoder();
  const data = encoder.encode(apiKey);
  const hashBuffer = await crypto.subtle.digest('SHA-256', data);
  const hashArray = Array.from(new Uint8Array(hashBuffer));
  const hashHex = hashArray.map(b => b.toString(16).padStart(2, '0')).join('');
  return hashHex;
}
