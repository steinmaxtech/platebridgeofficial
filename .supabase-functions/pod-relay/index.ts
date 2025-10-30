/**
 * Tailscale Pod Relay - Supabase Edge Function
 *
 * This edge function acts as a relay between the Vercel-hosted portal
 * and pods on the Tailscale network.
 *
 * Deploy this on a server with Tailscale installed.
 *
 * Usage:
 *   POST /pod-relay
 *   {
 *     "pod_id": "uuid-123",
 *     "endpoint": "/stream",
 *     "method": "GET",
 *     "headers": {},
 *     "body": null
 *   }
 */

import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import { createClient } from 'jsr:@supabase/supabase-js@2';

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Methods": "GET, POST, PUT, DELETE, OPTIONS",
  "Access-Control-Allow-Headers": "Content-Type, Authorization, X-Client-Info, Apikey",
};

interface RelayRequest {
  pod_id: string;
  endpoint: string;
  method?: string;
  headers?: Record<string, string>;
  body?: any;
  query?: Record<string, string>;
}

Deno.serve(async (req: Request) => {
  // Handle CORS preflight
  if (req.method === "OPTIONS") {
    return new Response(null, {
      status: 200,
      headers: corsHeaders,
    });
  }

  try {
    // Verify authentication
    const authHeader = req.headers.get('Authorization');
    if (!authHeader) {
      return new Response(
        JSON.stringify({ error: 'Unauthorized' }),
        {
          status: 401,
          headers: { ...corsHeaders, 'Content-Type': 'application/json' }
        }
      );
    }

    // Parse request
    const relayReq: RelayRequest = await req.json();
    const { pod_id, endpoint, method = 'GET', headers = {}, body, query = {} } = relayReq;

    if (!pod_id || !endpoint) {
      return new Response(
        JSON.stringify({ error: 'pod_id and endpoint are required' }),
        {
          status: 400,
          headers: { ...corsHeaders, 'Content-Type': 'application/json' }
        }
      );
    }

    // Get pod info from database
    const supabase = createClient(
      Deno.env.get('SUPABASE_URL') ?? '',
      Deno.env.get('SUPABASE_SERVICE_ROLE_KEY') ?? ''
    );

    const { data: pod, error: podError } = await supabase
      .from('pods')
      .select('tailscale_ip, ip_address, status')
      .eq('id', pod_id)
      .maybeSingle();

    if (podError || !pod) {
      return new Response(
        JSON.stringify({ error: 'Pod not found' }),
        {
          status: 404,
          headers: { ...corsHeaders, 'Content-Type': 'application/json' }
        }
      );
    }

    if (pod.status !== 'online') {
      return new Response(
        JSON.stringify({ error: 'Pod is offline' }),
        {
          status: 503,
          headers: { ...corsHeaders, 'Content-Type': 'application/json' }
        }
      );
    }

    // Prefer Tailscale IP if available
    const podIp = pod.tailscale_ip || pod.ip_address;
    if (!podIp) {
      return new Response(
        JSON.stringify({ error: 'Pod has no IP address' }),
        {
          status: 500,
          headers: { ...corsHeaders, 'Content-Type': 'application/json' }
        }
      );
    }

    // Build URL with query parameters
    const queryString = new URLSearchParams(query).toString();
    const url = `http://${podIp}:8000${endpoint}${queryString ? `?${queryString}` : ''}`;

    console.log(`Relaying ${method} ${url}`);

    // Forward request to pod
    const podResponse = await fetch(url, {
      method,
      headers: {
        ...headers,
        'X-Forwarded-For': req.headers.get('X-Forwarded-For') || 'unknown',
      },
      body: body ? JSON.stringify(body) : undefined,
    });

    // Forward response from pod
    const responseBody = await podResponse.arrayBuffer();

    return new Response(responseBody, {
      status: podResponse.status,
      headers: {
        ...corsHeaders,
        'Content-Type': podResponse.headers.get('Content-Type') || 'application/octet-stream',
        'Content-Length': podResponse.headers.get('Content-Length') || '',
      },
    });

  } catch (error: any) {
    console.error('[Pod Relay] Error:', error);
    return new Response(
      JSON.stringify({
        error: 'Relay failed',
        details: error.message
      }),
      {
        status: 500,
        headers: { ...corsHeaders, 'Content-Type': 'application/json' }
      }
    );
  }
});
