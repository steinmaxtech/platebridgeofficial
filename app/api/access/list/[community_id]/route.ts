import { createClient } from '@/lib/supabase-server';
import { NextRequest, NextResponse } from 'next/server';

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
