import { NextRequest, NextResponse } from 'next/server';
import { supabaseServer } from '@/lib/supabase-server';

export const dynamic = 'force-dynamic';

/**
 * Proxy requests to POD via Tailscale Funnel URL
 * This allows Vercel to securely access PODs that are behind NAT/cellular
 */
export async function POST(request: NextRequest) {
  try {
    const { pod_id, endpoint, method = 'GET', body } = await request.json();

    if (!pod_id) {
      return NextResponse.json(
        { error: 'pod_id is required' },
        { status: 400 }
      );
    }

    // Get POD's Tailscale Funnel URL from database
    const { data: pod, error: podError } = await supabaseServer
      .from('pods')
      .select('tailscale_funnel_url, tailscale_ip, tailscale_hostname, ip_address, api_key_hash')
      .eq('id', pod_id)
      .maybeSingle();

    if (podError || !pod) {
      return NextResponse.json(
        { error: 'POD not found' },
        { status: 404 }
      );
    }

    // Determine the best URL to use (priority order)
    let podUrl: string | null = null;

    if (pod.tailscale_funnel_url) {
      // Best: Tailscale Funnel (public HTTPS URL)
      podUrl = pod.tailscale_funnel_url;
    } else if (pod.tailscale_ip) {
      // Good: Tailscale IP (requires Vercel to be on Tailnet - won't work by default)
      podUrl = `https://${pod.tailscale_ip}:8000`;
    } else if (pod.ip_address && pod.ip_address !== 'unknown') {
      // Fallback: Public IP (may not work behind NAT)
      podUrl = `https://${pod.ip_address}:8000`;
    }

    if (!podUrl) {
      return NextResponse.json(
        {
          error: 'POD has no accessible URL. Enable Tailscale Funnel on the POD.',
          help: 'Run on POD: sudo tailscale funnel 8000'
        },
        { status: 503 }
      );
    }

    // Build full URL
    const fullUrl = `${podUrl}${endpoint}`;

    // Make request to POD
    const fetchOptions: RequestInit = {
      method,
      headers: {
        'Content-Type': 'application/json',
      },
    };

    if (body && (method === 'POST' || method === 'PUT')) {
      fetchOptions.body = JSON.stringify(body);
    }

    console.log(`[Tailscale Proxy] Requesting: ${fullUrl}`);

    const response = await fetch(fullUrl, fetchOptions);
    const data = await response.json();

    return NextResponse.json({
      success: true,
      data,
      pod_url: podUrl,
      via: pod.tailscale_funnel_url ? 'tailscale_funnel' :
           pod.tailscale_ip ? 'tailscale_ip' : 'public_ip'
    });

  } catch (error: any) {
    console.error('[Tailscale Proxy] Error:', error);
    return NextResponse.json(
      {
        error: 'Failed to connect to POD',
        details: error.message,
        help: 'Ensure POD has Tailscale Funnel enabled: sudo tailscale funnel 8000'
      },
      { status: 500 }
    );
  }
}

/**
 * Get POD connection info
 */
export async function GET(request: NextRequest) {
  try {
    const { searchParams } = new URL(request.url);
    const pod_id = searchParams.get('pod_id');

    if (!pod_id) {
      return NextResponse.json(
        { error: 'pod_id is required' },
        { status: 400 }
      );
    }

    const { data: pod, error } = await supabaseServer
      .from('pods')
      .select('id, name, tailscale_funnel_url, tailscale_ip, tailscale_hostname, ip_address, status, last_heartbeat')
      .eq('id', pod_id)
      .maybeSingle();

    if (error || !pod) {
      return NextResponse.json(
        { error: 'POD not found' },
        { status: 404 }
      );
    }

    // Determine connection method
    let connection_method = 'none';
    let connection_url = null;

    if (pod.tailscale_funnel_url) {
      connection_method = 'tailscale_funnel';
      connection_url = pod.tailscale_funnel_url;
    } else if (pod.tailscale_ip) {
      connection_method = 'tailscale_ip';
      connection_url = `https://${pod.tailscale_ip}:8000`;
    } else if (pod.ip_address && pod.ip_address !== 'unknown') {
      connection_method = 'public_ip';
      connection_url = `https://${pod.ip_address}:8000`;
    }

    return NextResponse.json({
      pod_id: pod.id,
      name: pod.name,
      status: pod.status,
      last_heartbeat: pod.last_heartbeat,
      connection: {
        method: connection_method,
        url: connection_url,
        tailscale_hostname: pod.tailscale_hostname,
        tailscale_ip: pod.tailscale_ip,
        tailscale_funnel_url: pod.tailscale_funnel_url,
        public_ip: pod.ip_address
      },
      recommendations: {
        best: 'tailscale_funnel',
        current: connection_method,
        action: connection_method === 'none'
          ? 'Enable Tailscale Funnel on POD: sudo tailscale funnel 8000'
          : connection_method === 'tailscale_funnel'
          ? 'Using optimal connection method'
          : 'Consider enabling Tailscale Funnel for better reliability'
      }
    });

  } catch (error: any) {
    console.error('[Tailscale Proxy] Error:', error);
    return NextResponse.json(
      { error: 'Internal server error', details: error.message },
      { status: 500 }
    );
  }
}
