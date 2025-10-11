import { NextRequest, NextResponse } from 'next/server';
import { supabaseServer } from '@/lib/supabase-server';
import crypto from 'crypto';

export async function POST(request: NextRequest) {
  try {
    const body = await request.json();
    const { serial, mac, model, version, community_id, site_id } = body;

    if (!serial || !mac) {
      return NextResponse.json(
        { error: 'Serial number and MAC address are required' },
        { status: 400 }
      );
    }

    if (!community_id && !site_id) {
      return NextResponse.json(
        { error: 'Either community_id or site_id is required' },
        { status: 400 }
      );
    }

    const supabase = supabaseServer;

    // If site_id provided, get community_id
    let resolvedCommunityId = community_id;
    if (site_id && !community_id) {
      const { data: site } = await supabase
        .from('sites')
        .select('community_id')
        .eq('id', site_id)
        .single();

      if (site) {
        resolvedCommunityId = site.community_id;
      }
    }

    if (!resolvedCommunityId) {
      return NextResponse.json(
        { error: 'Could not determine community' },
        { status: 400 }
      );
    }

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

    // Get current user (if authenticated via portal)
    const { data: { user } } = await supabase.auth.getUser();
    const createdBy = user?.id;

    // Create API key record
    if (createdBy) {
      await supabase
        .from('pod_api_keys')
        .insert({
          name: `${serial} Registration Key`,
          community_id: resolvedCommunityId,
          pod_id: serial,
          key_hash: keyHash,
          created_by: createdBy,
        });
    }

    // Return registration response
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
