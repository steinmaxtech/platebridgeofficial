import { NextRequest, NextResponse } from 'next/server';

export async function POST(request: NextRequest) {
  try {
    const { api_key, api_endpoint, community_id } = await request.json();

    if (!api_key || !api_endpoint || !community_id) {
      return NextResponse.json(
        { success: false, message: 'API key, endpoint, and community ID are required' },
        { status: 400 }
      );
    }

    const baseUrl = api_endpoint.trim().replace(/\/+$/, '');
    const accessPointsEndpoint = `${baseUrl}/community/${community_id}/access-point`;

    console.log('Fetching access points from:', accessPointsEndpoint);

    const response = await fetch(accessPointsEndpoint, {
      method: 'GET',
      headers: {
        'Authorization': `Bearer ${api_key}`,
        'Accept': 'application/json',
        'Content-Type': 'application/json',
      },
      signal: AbortSignal.timeout(10000),
    });

    console.log('Access points response status:', response.status);

    if (response.ok) {
      const data = await response.json();

      let accessPoints = [];
      if (Array.isArray(data)) {
        accessPoints = data.map((ap: any) => ({
          id: ap.id?.toString() || ap.access_point_id?.toString(),
          name: ap.name || ap.description || `Access Point ${ap.id || ap.access_point_id}`,
        }));
      } else if (data.access_points && Array.isArray(data.access_points)) {
        accessPoints = data.access_points.map((ap: any) => ({
          id: ap.id?.toString() || ap.access_point_id?.toString(),
          name: ap.name || ap.description || `Access Point ${ap.id || ap.access_point_id}`,
        }));
      } else if (data.data && Array.isArray(data.data)) {
        accessPoints = data.data.map((ap: any) => ({
          id: ap.id?.toString() || ap.access_point_id?.toString(),
          name: ap.name || ap.description || `Access Point ${ap.id || ap.access_point_id}`,
        }));
      }

      return NextResponse.json({
        success: true,
        access_points: accessPoints,
      });
    } else if (response.status === 401 || response.status === 403) {
      return NextResponse.json(
        {
          success: false,
          message: 'Authentication failed. Please check your API key.',
        },
        { status: 200 }
      );
    } else {
      const errorText = await response.text().catch(() => 'No error details available');
      return NextResponse.json(
        {
          success: false,
          message: `Failed to fetch access points: ${response.status} ${response.statusText}`,
          details: errorText,
        },
        { status: 200 }
      );
    }
  } catch (error: any) {
    console.error('Fetch access points error:', error);

    if (error.name === 'TimeoutError' || error.code === 'ETIMEDOUT') {
      return NextResponse.json(
        {
          success: false,
          message: 'Connection timeout - unable to reach Gatewise API within 10 seconds',
        },
        { status: 200 }
      );
    }

    return NextResponse.json(
      {
        success: false,
        message: `Error fetching access points: ${error.message || 'Unknown error'}`,
      },
      { status: 200 }
    );
  }
}
