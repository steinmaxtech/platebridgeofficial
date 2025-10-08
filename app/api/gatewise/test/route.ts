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

    const testEndpoint = `${api_endpoint}/health`;

    const response = await fetch(testEndpoint, {
      method: 'GET',
      headers: {
        'Authorization': `Bearer ${api_key}`,
        'Content-Type': 'application/json',
      },
      signal: AbortSignal.timeout(10000),
    });

    if (response.ok) {
      const data = await response.json();
      return NextResponse.json({
        success: true,
        message: 'Connection successful',
        data: data,
      });
    } else {
      const errorText = await response.text();
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
    if (error.name === 'TimeoutError') {
      return NextResponse.json(
        {
          success: false,
          message: 'Connection timeout - unable to reach Gatewise API',
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
