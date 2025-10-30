import { NextRequest, NextResponse } from 'next/server';
import { supabaseServer } from '@/lib/supabase-server';

export const dynamic = 'force-dynamic';

async function hashApiKey(apiKey: string): Promise<string> {
  const encoder = new TextEncoder();
  const data = encoder.encode(apiKey);
  const hashBuffer = await crypto.subtle.digest('SHA-256', data);
  const hashArray = Array.from(new Uint8Array(hashBuffer));
  const hashHex = hashArray.map(b => b.toString(16).padStart(2, '0')).join('');
  return hashHex;
}

async function verifyApiKey(authHeader: string | null) {
  if (!authHeader || !authHeader.startsWith('Bearer ')) {
    return null;
  }

  const apiKey = authHeader.substring(7);

  if (!apiKey.startsWith('pbk_')) {
    return null;
  }

  try {
    const keyHash = await hashApiKey(apiKey);

    const { data: keyData, error } = await supabaseServer
      .from('pod_api_keys')
      .select('id, revoked_at')
      .eq('key_hash', keyHash)
      .maybeSingle();

    if (error || !keyData || keyData.revoked_at) {
      return null;
    }

    return keyData;
  } catch (error) {
    return null;
  }
}

export async function POST(request: NextRequest) {
  try {
    const authHeader = request.headers.get('Authorization');
    const apiKeyData = await verifyApiKey(authHeader);

    if (!apiKeyData) {
      return NextResponse.json(
        { error: 'Invalid or revoked API key' },
        { status: 401 }
      );
    }

    const body = await request.json();
    const {
      pod_id,
      ip_address,
      tailscale_ip,
      tailscale_hostname,
      tailscale_funnel_url,
      firmware_version,
      status = 'online',
      cameras = []
    } = body;

    if (!pod_id) {
      return NextResponse.json(
        { error: 'pod_id is required' },
        { status: 400 }
      );
    }

    const keyHash = await hashApiKey(authHeader!.substring(7));

    const { data: keyDetails } = await supabaseServer
      .from('pod_api_keys')
      .select('community_id, pod_id')
      .eq('key_hash', keyHash)
      .single();

    if (!keyDetails) {
      return NextResponse.json({ error: 'API key not found' }, { status: 404 });
    }

    const { data: community } = await supabaseServer
      .from('communities')
      .select('id, company_id, sites(id)')
      .eq('id', keyDetails.community_id)
      .single();

    if (!community || !community.sites || community.sites.length === 0) {
      return NextResponse.json(
        { error: 'Community has no sites configured' },
        { status: 400 }
      );
    }

    const siteId = (community.sites as any)[0].id;

    const { data: existingPod } = await supabaseServer
      .from('pods')
      .select('id')
      .eq('id', pod_id)
      .maybeSingle();

    if (existingPod) {
      const updateData: any = {
        last_heartbeat: new Date().toISOString(),
        status,
        ip_address,
        firmware_version,
        updated_at: new Date().toISOString()
      };

      // Add Tailscale data if provided
      if (tailscale_ip) {
        updateData.tailscale_ip = tailscale_ip;
      }
      if (tailscale_hostname) {
        updateData.tailscale_hostname = tailscale_hostname;
      }
      if (tailscale_funnel_url) {
        updateData.tailscale_funnel_url = tailscale_funnel_url;
      }

      await supabaseServer
        .from('pods')
        .update(updateData)
        .eq('id', pod_id);
    } else {
      const dummyHash = await hashApiKey(`dummy-${pod_id}-${Date.now()}`);

      await supabaseServer
        .from('pods')
        .insert({
          id: pod_id,
          site_id: siteId,
          name: keyDetails.pod_id,
          api_key_hash: dummyHash,
          last_heartbeat: new Date().toISOString(),
          status,
          ip_address,
          firmware_version
        });
    }

    for (const camera of cameras) {
      const { camera_id, name, rtsp_url, position } = camera;

      if (!camera_id || !name) continue;

      // Prefer Tailscale Funnel URL, then Tailscale IP, then public IP
      let streamUrl;
      if (tailscale_funnel_url) {
        streamUrl = `${tailscale_funnel_url}/stream`;
      } else {
        const connectIp = tailscale_ip || ip_address;
        streamUrl = connectIp
          ? `https://${connectIp}:8000/stream`
          : `https://pod-${pod_id}.local:8000/stream`;
      }

      const { data: existingCamera } = await supabaseServer
        .from('cameras')
        .select('id')
        .eq('id', camera_id)
        .maybeSingle();

      if (existingCamera) {
        await supabaseServer
          .from('cameras')
          .update({
            name,
            stream_url: streamUrl,
            position: position || null,
            status: 'active',
            updated_at: new Date().toISOString()
          })
          .eq('id', camera_id);
      } else {
        await supabaseServer
          .from('cameras')
          .insert({
            id: camera_id,
            pod_id,
            name,
            stream_url: streamUrl,
            position: position || null,
            status: 'active'
          });
      }
    }

    await supabaseServer
      .from('pod_api_keys')
      .update({ last_used_at: new Date().toISOString() })
      .eq('key_hash', keyHash);

    return NextResponse.json({
      success: true,
      pod_id,
      community_id: keyDetails.community_id,
      cameras_registered: cameras.length
    });
  } catch (error: any) {
    console.error('[POD Heartbeat] Error:', error);
    return NextResponse.json(
      { error: 'Internal server error', details: error.message },
      { status: 500 }
    );
  }
}
