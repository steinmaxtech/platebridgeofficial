import { createClient } from '@/lib/supabase-server';
import { NextRequest, NextResponse } from 'next/server';

/**
 * GET /api/access/manage?community_id=xxx
 * Get all access list entries for a community (admin view)
 */
export async function GET(request: NextRequest) {
  try {
    const supabase = createClient();
    const searchParams = request.nextUrl.searchParams;
    const community_id = searchParams.get('community_id');

    if (!community_id) {
      return NextResponse.json(
        { error: 'Missing community_id' },
        { status: 400 }
      );
    }

    const { data: accessList, error } = await supabase
      .from('access_lists')
      .select('*')
      .eq('community_id', community_id)
      .order('created_at', { ascending: false });

    if (error) {
      console.error('Error fetching access list:', error);
      return NextResponse.json(
        { error: 'Failed to fetch access list' },
        { status: 500 }
      );
    }

    return NextResponse.json({ access_list: accessList || [] });
  } catch (error) {
    console.error('Error in access manage:', error);
    return NextResponse.json(
      { error: 'Internal server error' },
      { status: 500 }
    );
  }
}

/**
 * POST /api/access/manage
 * Create new access list entry
 */
export async function POST(request: NextRequest) {
  try {
    const supabase = createClient();
    const body = await request.json();

    const {
      community_id,
      plate,
      type,
      vendor_name,
      schedule_start,
      schedule_end,
      days_active,
      expires_at,
      notes,
    } = body;

    if (!community_id || !plate || !type) {
      return NextResponse.json(
        { error: 'Missing required fields' },
        { status: 400 }
      );
    }

    // Get current user
    const {
      data: { user },
    } = await supabase.auth.getUser();

    // Normalize plate
    const normalizedPlate = plate.toUpperCase().replace(/\s/g, '');

    const { data, error } = await supabase
      .from('access_lists')
      .insert([
        {
          community_id,
          plate: normalizedPlate,
          type,
          vendor_name: vendor_name || null,
          schedule_start: schedule_start || null,
          schedule_end: schedule_end || null,
          days_active: days_active || 'Mon-Sun',
          expires_at: expires_at || null,
          notes: notes || null,
          created_by: user?.id || null,
        },
      ])
      .select()
      .single();

    if (error) {
      console.error('Error creating access entry:', error);
      return NextResponse.json(
        { error: 'Failed to create access entry' },
        { status: 500 }
      );
    }

    return NextResponse.json({ success: true, entry: data });
  } catch (error) {
    console.error('Error in access manage:', error);
    return NextResponse.json(
      { error: 'Internal server error' },
      { status: 500 }
    );
  }
}

/**
 * PATCH /api/access/manage
 * Update an access list entry
 */
export async function PATCH(request: NextRequest) {
  try {
    const supabase = createClient();
    const body = await request.json();

    const { id, ...updates } = body;

    if (!id) {
      return NextResponse.json({ error: 'Missing entry id' }, { status: 400 });
    }

    // Normalize plate if being updated
    if (updates.plate) {
      updates.plate = updates.plate.toUpperCase().replace(/\s/g, '');
    }

    const { data, error } = await supabase
      .from('access_lists')
      .update(updates)
      .eq('id', id)
      .select()
      .single();

    if (error) {
      console.error('Error updating access entry:', error);
      return NextResponse.json(
        { error: 'Failed to update access entry' },
        { status: 500 }
      );
    }

    return NextResponse.json({ success: true, entry: data });
  } catch (error) {
    console.error('Error in access manage:', error);
    return NextResponse.json(
      { error: 'Internal server error' },
      { status: 500 }
    );
  }
}

/**
 * DELETE /api/access/manage?id=xxx
 * Delete an access list entry
 */
export async function DELETE(request: NextRequest) {
  try {
    const supabase = createClient();
    const searchParams = request.nextUrl.searchParams;
    const id = searchParams.get('id');

    if (!id) {
      return NextResponse.json({ error: 'Missing entry id' }, { status: 400 });
    }

    const { error } = await supabase.from('access_lists').delete().eq('id', id);

    if (error) {
      console.error('Error deleting access entry:', error);
      return NextResponse.json(
        { error: 'Failed to delete access entry' },
        { status: 500 }
      );
    }

    return NextResponse.json({ success: true });
  } catch (error) {
    console.error('Error in access manage:', error);
    return NextResponse.json(
      { error: 'Internal server error' },
      { status: 500 }
    );
  }
}
