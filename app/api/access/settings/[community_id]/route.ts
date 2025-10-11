import { createClient } from '@/lib/supabase-server';
import { NextRequest, NextResponse } from 'next/server';

/**
 * GET /api/access/settings/:community_id
 * Get access control settings for a community
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

    let { data: settings, error } = await supabase
      .from('community_access_settings')
      .select('*')
      .eq('community_id', community_id)
      .single();

    // Create default settings if not found
    if (error && error.code === 'PGRST116') {
      const { data: newSettings, error: insertError } = await supabase
        .from('community_access_settings')
        .insert([{ community_id }])
        .select()
        .single();

      if (insertError) {
        console.error('Error creating settings:', insertError);
        return NextResponse.json(
          { error: 'Failed to create settings' },
          { status: 500 }
        );
      }

      settings = newSettings;
    } else if (error) {
      console.error('Error fetching settings:', error);
      return NextResponse.json(
        { error: 'Failed to fetch settings' },
        { status: 500 }
      );
    }

    return NextResponse.json({ settings });
  } catch (error) {
    console.error('Error in settings get:', error);
    return NextResponse.json(
      { error: 'Internal server error' },
      { status: 500 }
    );
  }
}

/**
 * PATCH /api/access/settings/:community_id
 * Update access control settings for a community
 */
export async function PATCH(
  request: NextRequest,
  { params }: { params: { community_id: string } }
) {
  try {
    const supabase = createClient();
    const { community_id } = params;
    const body = await request.json();

    if (!community_id) {
      return NextResponse.json(
        { error: 'Missing community_id' },
        { status: 400 }
      );
    }

    const {
      auto_grant_enabled,
      lockdown_mode,
      require_confidence,
      notification_on_grant,
      notification_emails,
    } = body;

    // Check if settings exist
    const { data: existing } = await supabase
      .from('community_access_settings')
      .select('id')
      .eq('community_id', community_id)
      .single();

    let data, error;

    if (existing) {
      // Update existing
      ({ data, error } = await supabase
        .from('community_access_settings')
        .update({
          auto_grant_enabled,
          lockdown_mode,
          require_confidence,
          notification_on_grant,
          notification_emails,
        })
        .eq('community_id', community_id)
        .select()
        .single());
    } else {
      // Create new
      ({ data, error } = await supabase
        .from('community_access_settings')
        .insert([
          {
            community_id,
            auto_grant_enabled,
            lockdown_mode,
            require_confidence,
            notification_on_grant,
            notification_emails,
          },
        ])
        .select()
        .single());
    }

    if (error) {
      console.error('Error updating settings:', error);
      return NextResponse.json(
        { error: 'Failed to update settings' },
        { status: 500 }
      );
    }

    return NextResponse.json({ success: true, settings: data });
  } catch (error) {
    console.error('Error in settings update:', error);
    return NextResponse.json(
      { error: 'Internal server error' },
      { status: 500 }
    );
  }
}
