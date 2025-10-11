import { NextRequest, NextResponse } from 'next/server';
import { supabaseServer } from '@/lib/supabase-server';

export async function GET(
  request: NextRequest,
  { params }: { params: { id: string } }
) {
  try {
    const supabase = supabaseServer;
    const podId = params.id;

    // Get pod configuration
    const { data: pod, error: podError } = await supabase
      .from('pods')
      .select(`
        *,
        site:sites(
          id,
          name,
          site_id,
          community:communities(
            id,
            name,
            timezone
          )
        ),
        cameras(
          id,
          name,
          stream_url,
          position
        )
      `)
      .eq('id', podId)
      .maybeSingle();

    if (podError || !pod) {
      return NextResponse.json(
        { error: 'POD not found' },
        { status: 404 }
      );
    }

    // Generate docker-compose.yml
    const dockerCompose = `version: '3.8'

services:
  platebridge-agent:
    image: platebridge/agent:latest
    container_name: platebridge-agent
    restart: unless-stopped
    environment:
      - POD_ID=${pod.id}
      - PORTAL_URL=${process.env.NEXT_PUBLIC_SITE_URL}
      - SITE_ID=${pod.site.id}
      - COMMUNITY_ID=${pod.site.community.id}
      - COMMUNITY_NAME=${pod.site.community.name}
      - SITE_NAME=${pod.site.name}
      - TIMEZONE=${pod.site.community.timezone || 'America/New_York'}
    volumes:
      - /var/run/docker.sock:/var/run/docker.sock
      - ./config:/config
      - ./recordings:/recordings
    network_mode: host
    privileged: true

  # Camera streams (configured via portal)
${pod.cameras?.map((cam: any, idx: number) => `
  camera-${idx + 1}:
    image: platebridge/camera-processor:latest
    container_name: camera-${cam.name.toLowerCase().replace(/\\s+/g, '-')}
    restart: unless-stopped
    environment:
      - CAMERA_ID=${cam.id}
      - CAMERA_NAME=${cam.name}
      - STREAM_URL=${cam.stream_url}
      - POD_ID=${pod.id}
    depends_on:
      - platebridge-agent
`).join('') || '  # No cameras configured yet'}
`;

    // Generate .env file
    const envFile = `# PlateBridge POD Configuration
# Generated: ${new Date().toISOString()}

# POD Identity
POD_ID=${pod.id}
POD_NAME=${pod.name}
SERIAL_NUMBER=${pod.serial_number || ''}
HARDWARE_MODEL=${pod.hardware_model || 'PB-M1'}

# Portal Connection
PORTAL_URL=${process.env.NEXT_PUBLIC_SITE_URL}
PORTAL_API=${process.env.NEXT_PUBLIC_SITE_URL}/api

# Site Configuration
SITE_ID=${pod.site.id}
SITE_NAME=${pod.site.name}
COMMUNITY_ID=${pod.site.community.id}
COMMUNITY_NAME=${pod.site.community.name}
TIMEZONE=${pod.site.community.timezone || 'America/New_York'}

# Cameras
CAMERA_COUNT=${pod.cameras?.length || 0}

# Feature Flags
ENABLE_RECORDING=true
ENABLE_DETECTION=true
ENABLE_STREAMING=true

# Storage
RECORDING_PATH=/recordings
MAX_STORAGE_GB=100
RETENTION_DAYS=30
`;

    const format = request.nextUrl.searchParams.get('format') || 'json';

    if (format === 'compose') {
      return new NextResponse(dockerCompose, {
        headers: {
          'Content-Type': 'text/plain',
          'Content-Disposition': `attachment; filename="docker-compose-${pod.serial_number || podId}.yml"`,
        },
      });
    }

    if (format === 'env') {
      return new NextResponse(envFile, {
        headers: {
          'Content-Type': 'text/plain',
          'Content-Disposition': `attachment; filename=".env-${pod.serial_number || podId}"`,
        },
      });
    }

    // Default JSON response
    return NextResponse.json({
      pod_id: pod.id,
      pod_name: pod.name,
      serial_number: pod.serial_number,
      docker_compose: dockerCompose,
      env: envFile,
      download_urls: {
        compose: `${process.env.NEXT_PUBLIC_SITE_URL}/api/pods/config/${podId}?format=compose`,
        env: `${process.env.NEXT_PUBLIC_SITE_URL}/api/pods/config/${podId}?format=env`,
      },
    });
  } catch (error) {
    console.error('Error generating pod config:', error);
    return NextResponse.json(
      { error: 'Internal server error' },
      { status: 500 }
    );
  }
}
