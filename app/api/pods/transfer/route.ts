import { NextRequest, NextResponse } from 'next/server';
import { supabaseServer } from '@/lib/supabase-server';
import crypto from 'crypto';

export async function POST(request: NextRequest) {
  try {
    const supabase = supabaseServer;
    const { data: { user } } = await supabase.auth.getUser();

    if (!user) {
      return NextResponse.json({ error: 'Unauthorized' }, { status: 401 });
    }

    const body = await request.json();
    const { pod_id, to_site_id, reason } = body;

    if (!pod_id || !to_site_id) {
      return NextResponse.json(
        { error: 'pod_id and to_site_id are required' },
        { status: 400 }
      );
    }

    const { data: pod, error: podError } = await supabase
      .from('pods')
      .select('id, site_id, api_key_hash')
      .eq('id', pod_id)
      .single();

    if (podError || !pod) {
      return NextResponse.json({ error: 'POD not found' }, { status: 404 });
    }

    const newApiKey = `pb_${crypto.randomBytes(32).toString('hex')}`;
    const newKeyHash = crypto.createHash('sha256').update(newApiKey).digest('hex');

    const { error: updateError } = await supabase
      .from('pods')
      .update({
        site_id: to_site_id,
        api_key_hash: newKeyHash,
        updated_at: new Date().toISOString(),
      })
      .eq('id', pod_id);

    if (updateError) {
      console.error('Error updating POD:', updateError);
      return NextResponse.json({ error: 'Failed to transfer POD' }, { status: 500 });
    }

    const { error: transferError } = await supabase
      .from('pod_transfers')
      .insert({
        pod_id,
        from_site_id: pod.site_id,
        to_site_id,
        transferred_by: user.id,
        reason,
        old_api_key_hash: pod.api_key_hash,
        new_api_key_hash: newKeyHash,
      });

    if (transferError) {
      console.error('Error recording transfer:', transferError);
    }

    return NextResponse.json({
      success: true,
      new_api_key: newApiKey,
      message: 'POD transferred successfully. Update POD configuration with new API key.',
    });
  } catch (error) {
    console.error('Error in POST /api/pods/transfer:', error);
    return NextResponse.json({ error: 'Internal server error' }, { status: 500 });
  }
}

export async function GET(request: NextRequest) {
  try {
    const supabase = supabaseServer;
    const { data: { user } } = await supabase.auth.getUser();

    if (!user) {
      return NextResponse.json({ error: 'Unauthorized' }, { status: 401 });
    }

    const { searchParams } = new URL(request.url);
    const podId = searchParams.get('pod_id');

    if (!podId) {
      return NextResponse.json({ error: 'pod_id required' }, { status: 400 });
    }

    const { data: transfers, error } = await supabase
      .from('pod_transfers')
      .select(`
        id,
        from_site_id,
        to_site_id,
        transferred_at,
        reason,
        transferred_by
      `)
      .eq('pod_id', podId)
      .order('transferred_at', { ascending: false });

    if (error) {
      console.error('Error fetching transfers:', error);
      return NextResponse.json({ error: 'Failed to fetch transfers' }, { status: 500 });
    }

    return NextResponse.json({ transfers });
  } catch (error) {
    console.error('Error in GET /api/pods/transfer:', error);
    return NextResponse.json({ error: 'Internal server error' }, { status: 500 });
  }
}
