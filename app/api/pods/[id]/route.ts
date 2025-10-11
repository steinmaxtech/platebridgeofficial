import { NextRequest, NextResponse } from 'next/server';
import { supabaseServer } from '@/lib/supabase-server';

export async function GET(
  request: NextRequest,
  { params }: { params: { id: string } }
) {
  try {
    const supabase = supabaseServer;
    const podId = params.id;

    // Get current user
    const { data: { user }, error: authError } = await supabase.auth.getUser();

    if (authError || !user) {
      return NextResponse.json(
        { error: 'Unauthorized' },
        { status: 401 }
      );
    }

    // Get pod details with relationships
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
            company_id,
            address,
            timezone
          )
        ),
        cameras(
          id,
          name,
          status,
          position,
          stream_url,
          created_at,
          last_recording_at
        )
      `)
      .eq('id', podId)
      .maybeSingle();

    if (podError) {
      console.error('Error fetching pod:', podError);
      return NextResponse.json(
        { error: 'Failed to fetch pod' },
        { status: 500 }
      );
    }

    if (!pod) {
      return NextResponse.json(
        { error: 'POD not found' },
        { status: 404 }
      );
    }

    // Check user has access to this pod's community
    const { data: membership } = await supabase
      .from('memberships')
      .select('role')
      .eq('user_id', user.id)
      .eq('company_id', pod.site.community.company_id)
      .maybeSingle();

    if (!membership) {
      return NextResponse.json(
        { error: 'Access denied' },
        { status: 403 }
      );
    }

    // Get recent detections (last 24 hours)
    const yesterday = new Date();
    yesterday.setDate(yesterday.getDate() - 1);

    const { data: detections, error: detectionsError } = await supabase
      .from('pod_detections')
      .select('*')
      .eq('pod_id', podId)
      .gte('detected_at', yesterday.toISOString())
      .order('detected_at', { ascending: false })
      .limit(50);

    // Get recent commands
    const { data: commands, error: commandsError } = await supabase
      .from('pod_commands')
      .select('*, created_by_user:auth.users!created_by(email)')
      .eq('pod_id', podId)
      .order('created_at', { ascending: false })
      .limit(20);

    // Calculate stats
    const lastSeen = pod.last_heartbeat ? new Date(pod.last_heartbeat) : null;
    const now = new Date();
    const isOnline = lastSeen && (now.getTime() - lastSeen.getTime()) < 5 * 60 * 1000;

    const stats = {
      isOnline,
      lastSeenMinutes: lastSeen ? Math.floor((now.getTime() - lastSeen.getTime()) / 60000) : null,
      cameraCount: pod.cameras?.length || 0,
      activeCameras: pod.cameras?.filter((c: any) => c.status === 'active').length || 0,
      detections24h: detections?.length || 0,
      pendingCommands: commands?.filter((c: any) => c.status === 'queued' || c.status === 'sent').length || 0,
    };

    return NextResponse.json({
      pod,
      stats,
      detections: detections || [],
      commands: commands || [],
      userRole: membership.role,
    });
  } catch (error) {
    console.error('Error in pod detail:', error);
    return NextResponse.json(
      { error: 'Internal server error' },
      { status: 500 }
    );
  }
}
