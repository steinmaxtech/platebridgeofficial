import { NextRequest, NextResponse } from 'next/server';
import { supabaseServer } from '@/lib/supabase-server';
import crypto from 'crypto';

export async function GET(request: NextRequest) {
  try {
    const supabase = supabaseServer;
    const { data: { user } } = await supabase.auth.getUser();

    if (!user) {
      return NextResponse.json({ error: 'Unauthorized' }, { status: 401 });
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
    const supabase = supabaseServer;
    const { data: { user } } = await supabase.auth.getUser();

    if (!user) {
      return NextResponse.json({ error: 'Unauthorized' }, { status: 401 });
    }

    const body = await request.json();
    const { community_id, expires_in_hours = 24, max_uses = 1, notes } = body;

    if (!community_id) {
      return NextResponse.json({ error: 'community_id is required' }, { status: 400 });
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
      return NextResponse.json({ error: 'Failed to create token' }, { status: 500 });
    }

    return NextResponse.json({ token: newToken });
  } catch (error) {
    console.error('Error in POST /api/pods/registration-tokens:', error);
    return NextResponse.json({ error: 'Internal server error' }, { status: 500 });
  }
}

export async function DELETE(request: NextRequest) {
  try {
    const supabase = supabaseServer;
    const { data: { user } } = await supabase.auth.getUser();

    if (!user) {
      return NextResponse.json({ error: 'Unauthorized' }, { status: 401 });
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
