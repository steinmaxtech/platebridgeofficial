import { NextRequest, NextResponse } from 'next/server';
import { supabaseServer } from '@/lib/supabase-server';

export const dynamic = 'force-dynamic';

export async function POST(request: NextRequest) {
  try {
    const authHeader = request.headers.get('authorization');
    const adminSecret = process.env.ADMIN_NUDGE_SECRET || 'change_me';

    let isAuthorized = false;

    if (authHeader?.startsWith('Bearer ')) {
      const token = authHeader.substring(7);
      if (token === adminSecret) {
        isAuthorized = true;
      } else {
        const { data: { user }, error } = await supabaseServer.auth.getUser(token);

        if (!error && user) {
          const { data: profile } = await supabaseServer
            .from('user_profiles')
            .select('role')
            .eq('id', user.id)
            .maybeSingle();

          if (profile && ['owner', 'admin'].includes(profile.role)) {
            isAuthorized = true;
          }
        }
      }
    }

    if (!isAuthorized) {
      return NextResponse.json(
        { error: 'Unauthorized' },
        { status: 401 }
      );
    }

    const body = await request.json();
    const { property, reason } = body;

    if (!property) {
      return NextResponse.json(
        { error: 'Property parameter is required' },
        { status: 400 }
      );
    }

    const { data: propertyData, error: propertyError } = await supabaseServer
      .from('properties')
      .select('id, config_version')
      .eq('name', property)
      .maybeSingle();

    if (propertyError || !propertyData) {
      return NextResponse.json(
        { error: 'Property not found' },
        { status: 404 }
      );
    }

    const newVersion = propertyData.config_version + 1;

    const { error: updateError } = await supabaseServer
      .from('properties')
      .update({ config_version: newVersion })
      .eq('id', propertyData.id);

    if (updateError) {
      return NextResponse.json(
        { error: 'Failed to update config version' },
        { status: 500 }
      );
    }

    await supabaseServer.from('audit').insert({
      ts: new Date().toISOString(),
      property_id: propertyData.id,
      action: 'config_nudge',
      result: 'success',
      by: 'api:nudge',
      metadata: { reason: reason || 'manual_nudge', old_version: propertyData.config_version, new_version: newVersion }
    });

    return NextResponse.json({
      property,
      config_version: newVersion,
      previous_version: propertyData.config_version,
      timestamp: new Date().toISOString()
    });
  } catch (error) {
    console.error('Nudge API error:', error);
    return NextResponse.json(
      { error: 'Internal server error' },
      { status: 500 }
    );
  }
}
