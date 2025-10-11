import { NextRequest, NextResponse } from 'next/server';
import { createClient } from '@supabase/supabase-js';
import crypto from 'crypto';

export async function POST(request: NextRequest) {
  try {
    const body = await request.json();
    const { serial, mac, model, version, registration_token } = body;

    if (!serial || !mac) {
      return NextResponse.json(
        { error: 'Serial number and MAC address are required' },
        { status: 400 }
      );
    }

    if (!registration_token) {
      return NextResponse.json(
        { error: 'Registration token is required. Get one from the portal Properties page.' },
        { status: 400 }
      );
    }

    const supabase = createClient(
      process.env.NEXT_PUBLIC_SUPABASE_URL!,
      process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY!
    );

    const { data: tokenData, error: tokenError } = await supabase
      .from('pod_registration_tokens')
      .select('id, community_id, expires_at, used_at, use_count, max_uses')
      .eq('token', registration_token)
      .maybeSingle();

    if (tokenError || !tokenData) {
      return NextResponse.json(
        { error: 'Invalid registration token' },
        { status: 401 }
      );
    }

    // Check if token has already been used (single-use tokens)
    if (tokenData.used_at) {
      return NextResponse.json(
        { error: 'Registration token has already been used' },
        { status: 401 }
      );
    }

    if (new Date(tokenData.expires_at) < new Date()) {
      return NextResponse.json(
        { error: 'Registration token has expired' },
        { status: 401 }
      );
    }

    const community_id = tokenData.community_id;

    const { data: defaultSite } = await supabase
      .from('sites')
      .select('id')
      .eq('community_id', community_id)
      .limit(1)
      .maybeSingle();

    const site_id = defaultSite?.id || null;

    // Check if POD already exists
    const { data: existingPod } = await supabase
      .from('pods')
      .select('id, status, api_key_hash')
      .eq('serial_number', serial)
      .maybeSingle();

    let podId: string;
    let apiKey: string;

    if (existingPod) {
      // POD already registered, return existing info
      podId = existingPod.id;

      // Update last heartbeat and status
      await supabase
        .from('pods')
        .update({
          status: 'online',
          last_heartbeat: new Date().toISOString(),
          software_version: version || '1.0.0',
          mac_address: mac,
          hardware_model: model || 'PB-M1',
        })
        .eq('id', podId);

      // Return success but no new API key (already exists)
      return NextResponse.json({
        pod_id: podId,
        message: 'POD already registered. Use existing API key.',
        docker_compose_url: `${process.env.NEXT_PUBLIC_SITE_URL}/api/pods/config/${podId}`,
      });
    }

    // Generate new API key
    apiKey = `pb_${crypto.randomBytes(32).toString('hex')}`;
    const keyHash = crypto.createHash('sha256').update(apiKey).digest('hex');

    // Create new POD
    const { data: newPod, error: podError } = await supabase
      .from('pods')
      .insert({
        site_id: site_id,
        name: `POD-${serial}`,
        serial_number: serial,
        mac_address: mac,
        hardware_model: model || 'PB-M1',
        software_version: version || '1.0.0',
        api_key_hash: keyHash,
        status: 'online',
        last_heartbeat: new Date().toISOString(),
      })
      .select('id')
      .single();

    if (podError || !newPod) {
      console.error('Error creating POD:', podError);
      return NextResponse.json(
        { error: 'Failed to register POD' },
        { status: 500 }
      );
    }

    podId = newPod.id;

    // Mark token as used (single-use)
    await supabase
      .from('pod_registration_tokens')
      .update({
        used_at: new Date().toISOString(),
        used_by_serial: serial,
        used_by_mac: mac,
        pod_id: podId,
        use_count: 1,
      })
      .eq('id', tokenData.id);

    return NextResponse.json({
      pod_id: podId,
      api_key: apiKey,
      docker_compose_url: `${process.env.NEXT_PUBLIC_SITE_URL}/api/pods/config/${podId}`,
      env: {
        PLATEBRIDGE_API: `${process.env.NEXT_PUBLIC_SITE_URL}/api`,
        PLATEBRIDGE_API_KEY: apiKey,
        POD_ID: podId,
        PORTAL_URL: process.env.NEXT_PUBLIC_SITE_URL,
      },
      message: 'POD registered successfully',
    });
  } catch (error) {
    console.error('Error in POD registration:', error);
    return NextResponse.json(
      { error: 'Internal server error' },
      { status: 500 }
    );
  }
}
