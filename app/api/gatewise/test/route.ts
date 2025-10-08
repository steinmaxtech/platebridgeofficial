import { NextRequest, NextResponse } from 'next/server';

export async function POST(request: NextRequest) {
  try {
    const { api_key, api_endpoint } = await request.json();

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

    const testEndpoint = `${baseUrl}/health`;

    console.log('Testing Gatewise connection to:', testEndpoint);

    const response = await fetch(testEndpoint, {
      method: 'GET',
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
        message: 'Connection successful! Gatewise API is reachable.',
        data: data,
      });
    } else if (response.status === 404) {
      return NextResponse.json(
        {
          success: false,
          message: 'Health endpoint not found. Testing basic connectivity instead...',
          details: 'The API endpoint appears to be reachable but may not have a /health endpoint. This is okay - your configuration should work for actual API calls.',
          partial_success: true,
        },
        { status: 200 }
      );
    } else if (response.status === 401 || response.status === 403) {
      return NextResponse.json(
        {
          success: false,
          message: 'Authentication failed. Please check your API key.',
          details: `HTTP ${response.status}: ${response.statusText}`,
        },
        { status: 200 }
      );
    } else {
      const errorText = await response.text().catch(() => 'No error details available');
      return NextResponse.json(
        {
          success: false,
          message: `Connection failed: ${response.status} ${response.statusText}`,
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

    if (error.cause?.code === 'ENOTFOUND' || error.message.includes('fetch failed')) {
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
