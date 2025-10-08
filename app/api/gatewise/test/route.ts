import { NextRequest, NextResponse } from 'next/server';

export async function POST(request: NextRequest) {
  try {
    const { api_key, api_endpoint, community_id, access_point_id } = await request.json();

    if (!api_key || !api_endpoint) {
      return NextResponse.json(
        { success: false, message: 'API key and endpoint are required' },
        { status: 400 }
      );
    }

    let baseUrl = api_endpoint.trim();

    if (baseUrl.includes('curl')) {
      return NextResponse.json(
        {
          success: false,
          message: 'Invalid API endpoint format. Please enter only the base URL (e.g., https://partners-api.gatewise.com)',
        },
        { status: 200 }
      );
    }

    baseUrl = baseUrl.replace(/\/+$/, '');

    if (!community_id || !access_point_id) {
      return NextResponse.json(
        {
          success: false,
          message: 'Community ID and Access Point ID are required for testing',
        },
        { status: 400 }
      );
    }

    const testEndpoint = `${baseUrl}/community/${community_id}/access-point/${access_point_id}/open`;

    console.log('Testing gate open command at:', testEndpoint);

    const response = await fetch(testEndpoint, {
      method: 'POST',
      headers: {
        'Authorization': `Bearer ${api_key}`,
        'Accept': 'application/json',
        'Content-Type': 'application/json',
      },
      signal: AbortSignal.timeout(10000),
    });

    console.log('Gatewise response status:', response.status);

    if (response.ok) {
      let data;
      try {
        data = await response.json();
      } catch (e) {
        data = { status: 'ok' };
      }
      return NextResponse.json({
        success: true,
        message: 'Gate opened successfully!',
        data: data,
      });
    } else if (response.status === 401 || response.status === 403) {
      return NextResponse.json(
        {
          success: false,
          message: 'Authentication failed. Please check your API key.',
          details: `HTTP ${response.status}: ${response.statusText}`,
        },
        { status: 200 }
      );
    } else if (response.status === 404) {
      return NextResponse.json(
        {
          success: false,
          message: 'Access point not found. Please verify the Community ID and Access Point ID.',
          details: `HTTP ${response.status}: ${response.statusText}`,
        },
        { status: 200 }
      );
    } else {
      const errorText = await response.text().catch(() => 'No error details available');
      return NextResponse.json(
        {
          success: false,
          message: `Failed to open gate: ${response.status} ${response.statusText}`,
          details: errorText,
        },
        { status: 200 }
      );
    }
  } catch (error: any) {
    console.error('Gatewise test error:', error);

    if (error.name === 'TimeoutError' || error.code === 'ETIMEDOUT') {
      return NextResponse.json(
        {
          success: false,
          message: 'Connection timeout - unable to reach Gatewise API within 10 seconds',
        },
        { status: 200 }
      );
    }

    if (error.cause?.code === 'ENOTFOUND') {
      return NextResponse.json(
        {
          success: false,
          message: 'Unable to resolve API endpoint. Please check the URL is correct.',
          details: error.message,
        },
        { status: 200 }
      );
    }

    return NextResponse.json(
      {
        success: false,
        message: `Connection error: ${error.message || 'Unknown error'}`,
      },
      { status: 200 }
    );
  }
}
