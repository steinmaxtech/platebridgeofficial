import { createClient } from '@/lib/supabase-server';
import { NextRequest, NextResponse } from 'next/server';

/**
 * POST /api/access/log
 * Allows PODs to manually log access decisions
 */
export async function POST(request: NextRequest) {
  try {
    const supabase = createClient();
    const body = await request.json();

    const {
      pod_id,
      community_id,
      plate,
      decision,
      reason,
      access_type,
      vendor_name,
      gate_triggered,
      confidence,
    } = body;

    if (!community_id || !plate || !decision) {
      return NextResponse.json(
        { error: 'Missing required fields' },
        { status: 400 }
      );
    }

    const { data, error } = await supabase
      .from('access_logs')
      .insert([
        {
          pod_id: pod_id || null,
          community_id,
          plate,
          decision,
          reason: reason || null,
          access_type: access_type || null,
          vendor_name: vendor_name || null,
          gate_triggered: gate_triggered || false,
          confidence: confidence || null,
        },
      ])
      .select()
      .single();

    if (error) {
      console.error('Error logging access:', error);
      return NextResponse.json(
        { error: 'Failed to log access' },
        { status: 500 }
      );
    }

    return NextResponse.json({ success: true, log: data });
  } catch (error) {
    console.error('Error in access log:', error);
    return NextResponse.json(
      { error: 'Internal server error' },
      { status: 500 }
    );
  }
}

/**
 * GET /api/access/log?community_id=xxx&limit=50
 * Retrieve access logs for a community
 */
export async function GET(request: NextRequest) {
  try {
    const supabase = createClient();
    const searchParams = request.nextUrl.searchParams;
    const community_id = searchParams.get('community_id');
    const limit = parseInt(searchParams.get('limit') || '50');
    const offset = parseInt(searchParams.get('offset') || '0');

    if (!community_id) {
      return NextResponse.json(
        { error: 'Missing community_id' },
        { status: 400 }
      );
    }

    const { data: logs, error } = await supabase
      .from('access_logs')
      .select('*')
      .eq('community_id', community_id)
      .order('timestamp', { ascending: false })
      .range(offset, offset + limit - 1);

    if (error) {
      console.error('Error fetching access logs:', error);
      return NextResponse.json(
        { error: 'Failed to fetch logs' },
        { status: 500 }
      );
    }

    return NextResponse.json({ logs: logs || [], count: logs?.length || 0 });
  } catch (error) {
    console.error('Error in access log fetch:', error);
    return NextResponse.json(
      { error: 'Internal server error' },
      { status: 500 }
    );
  }
}
