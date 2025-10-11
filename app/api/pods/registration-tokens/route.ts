import { NextRequest, NextResponse } from 'next/server';
import { createClient } from '@supabase/supabase-js';
import crypto from 'crypto';

export async function GET(request: NextRequest) {
  try {
    const authHeader = request.headers.get('authorization');
    if (!authHeader) {
      return NextResponse.json({ error: 'Unauthorized - No auth header' }, { status: 401 });
    }

    const authToken = authHeader.replace('Bearer ', '');

    const supabase = createClient(
      process.env.NEXT_PUBLIC_SUPABASE_URL!,
      process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY!,
      {
        global: {
          headers: {
            Authorization: `Bearer ${authToken}`
          }
        }
      }
    );

    const { data: { user }, error: userError } = await supabase.auth.getUser(authToken);

    if (userError || !user) {
      return NextResponse.json({ error: 'Unauthorized - Invalid token' }, { status: 401 });
    }

    const { searchParams } = new URL(request.url);
    const communityId = searchParams.get('community_id');

    if (!communityId) {
      return NextResponse.json({ error: 'community_id required' }, { status: 400 });
    }

    const { data: tokens, error } = await supabase
      .from('pod_registration_tokens')
      .select(`
        id,
        token,
        expires_at,
        used_at,
        used_by_serial,
        used_by_mac,
        pod_id,
        created_at,
        max_uses,
        use_count,
        notes
      `)
      .eq('community_id', communityId)
      .order('created_at', { ascending: false });

    if (error) {
      console.error('Error fetching tokens:', error);
      return NextResponse.json({ error: 'Failed to fetch tokens' }, { status: 500 });
    }

    return NextResponse.json({ tokens });
  } catch (error) {
    console.error('Error in GET /api/pods/registration-tokens:', error);
    return NextResponse.json({ error: 'Internal server error' }, { status: 500 });
  }
}

export async function POST(request: NextRequest) {
  try {
    const authHeader = request.headers.get('authorization');
    if (!authHeader) {
      return NextResponse.json({ error: 'Unauthorized - No auth header' }, { status: 401 });
    }

    const authToken = authHeader.replace('Bearer ', '');

    const supabase = createClient(
      process.env.NEXT_PUBLIC_SUPABASE_URL!,
      process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY!,
      {
        global: {
          headers: {
            Authorization: `Bearer ${authToken}`
          }
        }
      }
    );

    const { data: { user }, error: userError } = await supabase.auth.getUser(authToken);

    if (userError || !user) {
      console.error('Auth error:', userError);
      return NextResponse.json({
        error: 'Unauthorized - Invalid token',
        details: userError?.message
      }, { status: 401 });
    }

    const body = await request.json();
    const { community_id, expires_in_hours = 24, max_uses = 1, notes } = body;

    if (!community_id) {
      return NextResponse.json({ error: 'community_id is required' }, { status: 400 });
    }

    const { data: membership, error: membershipError } = await supabase
      .from('memberships')
      .select('role, companies!inner(id, communities!inner(id))')
      .eq('user_id', user.id)
      .eq('companies.communities.id', community_id)
      .maybeSingle();

    if (membershipError || !membership) {
      console.error('Membership check error:', membershipError);
      return NextResponse.json({
        error: 'Access denied - You do not have permission for this community',
        details: membershipError?.message
      }, { status: 403 });
    }

    if (!['owner', 'admin', 'manager'].includes(membership.role)) {
      return NextResponse.json({
        error: 'Access denied - Insufficient permissions'
      }, { status: 403 });
    }

    const token = `pbreg_${crypto.randomBytes(32).toString('hex')}`;
    const expiresAt = new Date();
    expiresAt.setHours(expiresAt.getHours() + expires_in_hours);

    const { data: newToken, error } = await supabase
      .from('pod_registration_tokens')
      .insert({
        community_id,
        token,
        expires_at: expiresAt.toISOString(),
        max_uses,
        notes,
        created_by: user.id,
      })
      .select()
      .single();

    if (error) {
      console.error('Error creating token:', error);
      return NextResponse.json({
        error: 'Failed to create token',
        details: error.message,
        code: error.code
      }, { status: 500 });
    }

    return NextResponse.json({ token: newToken });
  } catch (error) {
    console.error('Error in POST /api/pods/registration-tokens:', error);
    return NextResponse.json({ error: 'Internal server error' }, { status: 500 });
  }
}

export async function DELETE(request: NextRequest) {
  try {
    const authHeader = request.headers.get('authorization');
    if (!authHeader) {
      return NextResponse.json({ error: 'Unauthorized - No auth header' }, { status: 401 });
    }

    const authToken = authHeader.replace('Bearer ', '');

    const supabase = createClient(
      process.env.NEXT_PUBLIC_SUPABASE_URL!,
      process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY!,
      {
        global: {
          headers: {
            Authorization: `Bearer ${authToken}`
          }
        }
      }
    );

    const { data: { user }, error: userError } = await supabase.auth.getUser(authToken);

    if (userError || !user) {
      return NextResponse.json({ error: 'Unauthorized - Invalid token' }, { status: 401 });
    }

    const { searchParams } = new URL(request.url);
    const tokenId = searchParams.get('id');

    if (!tokenId) {
      return NextResponse.json({ error: 'id required' }, { status: 400 });
    }

    const { error } = await supabase
      .from('pod_registration_tokens')
      .delete()
      .eq('id', tokenId)
      .is('used_at', null);

    if (error) {
      console.error('Error deleting token:', error);
      return NextResponse.json({ error: 'Failed to delete token' }, { status: 500 });
    }

    return NextResponse.json({ success: true });
  } catch (error) {
    console.error('Error in DELETE /api/pods/registration-tokens:', error);
    return NextResponse.json({ error: 'Internal server error' }, { status: 500 });
  }
}
