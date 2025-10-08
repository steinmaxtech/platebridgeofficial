import { NextRequest, NextResponse } from 'next/server';
import { supabaseServer } from '@/lib/supabase-server';

export const dynamic = 'force-dynamic';

export async function POST(request: NextRequest) {
  try {
    const body = await request.json();
    const { site_id, plate, camera, pod_name } = body;

    if (!site_id || !plate) {
      return NextResponse.json(
        { success: false, error: 'site_id and plate are required' },
        { status: 400 }
      );
    }

    console.log(`[POD Detection] Site: ${site_id}, Plate: ${plate}, Camera: ${camera}`);

    const { data: site, error: siteError } = await supabaseServer
      .from('sites')
      .select('id, community_id, name')
      .eq('site_id', site_id)
      .maybeSingle();

    if (siteError || !site) {
      console.error('[POD Detection] Site not found:', site_id);
      return NextResponse.json(
        { success: false, error: 'Site not found', action: 'deny' },
        { status: 404 }
      );
    }

    const { data: plateEntry, error: plateError } = await supabaseServer
      .from('plates')
      .select('*')
      .eq('community_id', site.community_id)
      .eq('plate', plate.toUpperCase())
      .eq('enabled', true)
      .maybeSingle();

    if (plateError) {
      console.error('[POD Detection] Error checking plate:', plateError);
      return NextResponse.json(
        { success: false, error: 'Database error', action: 'deny' },
        { status: 500 }
      );
    }

    const isAuthorized = !!plateEntry;

    await supabaseServer.from('audit').insert({
      community_id: site.community_id,
      site_id: site_id,
      plate: plate.toUpperCase(),
      camera: camera || 'unknown',
      action: 'plate_detected',
      result: isAuthorized ? 'authorized' : 'unauthorized',
      by: pod_name || 'pod',
      metadata: {
        unit: plateEntry?.unit,
        tenant: plateEntry?.tenant,
        vehicle: plateEntry?.vehicle,
      },
    });

    if (isAuthorized) {
      console.log(`[POD Detection] Plate ${plate} authorized, checking Gatewise integration...`);

      const { data: gatewiseConfig, error: gatewiseError } = await supabaseServer
        .from('gatewise_config')
        .select('*')
        .eq('community_id', site.community_id)
        .eq('enabled', true)
        .maybeSingle();

      if (!gatewiseError && gatewiseConfig && gatewiseConfig.gatewise_access_point_id) {
        console.log(`[POD Detection] Triggering Gatewise gate for community ${site.community_id}`);

        try {
          const baseUrl = gatewiseConfig.api_endpoint.replace(/\/+$/, '');
          const openEndpoint = `${baseUrl}/community/${gatewiseConfig.gatewise_community_id}/access-point/${gatewiseConfig.gatewise_access_point_id}/open`;

          const gateResponse = await fetch(openEndpoint, {
            method: 'POST',
            headers: {
              'Authorization': `Bearer ${gatewiseConfig.api_key}`,
              'Accept': 'application/json',
              'Content-Type': 'application/json',
            },
            signal: AbortSignal.timeout(10000),
          });

          if (gateResponse.ok) {
            console.log(`[POD Detection] Gate opened successfully for plate ${plate}`);

            await supabaseServer.from('audit').insert({
              community_id: site.community_id,
              site_id: site_id,
              plate: plate.toUpperCase(),
              camera: camera || 'unknown',
              action: 'gate_opened',
              result: 'success',
              by: 'gatewise',
              metadata: {
                access_point_id: gatewiseConfig.gatewise_access_point_id,
                unit: plateEntry?.unit,
                tenant: plateEntry?.tenant,
              },
            });

            return NextResponse.json({
              success: true,
              action: 'allow',
              gate_opened: true,
              plate_info: {
                unit: plateEntry.unit,
                tenant: plateEntry.tenant,
                vehicle: plateEntry.vehicle,
              },
            });
          } else {
            console.error(`[POD Detection] Failed to open gate: ${gateResponse.status}`);

            await supabaseServer.from('audit').insert({
              community_id: site.community_id,
              site_id: site_id,
              plate: plate.toUpperCase(),
              camera: camera || 'unknown',
              action: 'gate_open_failed',
              result: 'error',
              by: 'gatewise',
              metadata: {
                error: `HTTP ${gateResponse.status}`,
                access_point_id: gatewiseConfig.gatewise_access_point_id,
              },
            });
          }
        } catch (error: any) {
          console.error('[POD Detection] Gatewise API error:', error);

          await supabaseServer.from('audit').insert({
            community_id: site.community_id,
            site_id: site_id,
            plate: plate.toUpperCase(),
            camera: camera || 'unknown',
            action: 'gate_open_failed',
            result: 'error',
            by: 'gatewise',
            metadata: {
              error: error.message,
            },
          });
        }
      } else {
        console.log(`[POD Detection] No Gatewise integration configured for community ${site.community_id}`);
      }

      return NextResponse.json({
        success: true,
        action: 'allow',
        gate_opened: false,
        plate_info: {
          unit: plateEntry.unit,
          tenant: plateEntry.tenant,
          vehicle: plateEntry.vehicle,
        },
      });
    } else {
      console.log(`[POD Detection] Plate ${plate} not authorized`);

      return NextResponse.json({
        success: true,
        action: 'deny',
        gate_opened: false,
        message: 'Plate not in whitelist',
      });
    }
  } catch (error: any) {
    console.error('[POD Detection] Error:', error);
    return NextResponse.json(
      { success: false, error: 'Internal server error', action: 'deny' },
      { status: 500 }
    );
  }
}
