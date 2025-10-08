import { NextRequest, NextResponse } from 'next/server';

export const dynamic = 'force-dynamic';

export async function GET(request: NextRequest) {
  try {
    const healthCheckUrl = 'https://partners-api.gatewise.com/healthcheck';

    const controller = new AbortController();
    const timeoutId = setTimeout(() => controller.abort(), 5000);

    const response = await fetch(healthCheckUrl, {
      signal: controller.signal,
    });

    clearTimeout(timeoutId);

    const isHealthy = response.ok;
    const statusCode = response.status;

    return NextResponse.json({
      status: isHealthy ? 'healthy' : 'unhealthy',
      statusCode,
      timestamp: new Date().toISOString(),
    });
  } catch (error) {
    console.error('Gatewise health check failed:', error);

    return NextResponse.json({
      status: 'unhealthy',
      statusCode: 0,
      error: error instanceof Error ? error.message : 'Unknown error',
      timestamp: new Date().toISOString(),
    });
  }
}
