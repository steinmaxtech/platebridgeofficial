import { NextRequest, NextResponse } from 'next/server';
import { createClient } from '@supabase/supabase-js';

export async function GET(request: NextRequest) {
  try {
    // Create Supabase client with anon key (will use RLS)
    const supabase = createClient(
      process.env.NEXT_PUBLIC_SUPABASE_URL!,
      process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY!
    );

    // Extract auth token from cookie
    const authCookie = request.cookies.get('sb-access-token')?.value ||
                      request.cookies.get('supabase-auth-token')?.value;

    if (!authCookie) {
      // Try all possible cookie names
      const allCookies = request.cookies.getAll();
      const authCookieAlt = allCookies.find(c => c.name.includes('auth-token'));
      if (!authCookieAlt) {
        return NextResponse.json({ error: 'No auth cookie found' }, { status: 401 });
      }
    }

    // Set auth header if we have a token
    const authHeader = request.headers.get('cookie');
    const { data: { user }, error: authError } = await supabase.auth.getUser();

    if (authError || !user) {
      return NextResponse.json(
        { error: 'Unauthorized - invalid session' },
        { status: 401 }
      );
    }

    // Get user's communities
    const { data: memberships } = await supabase
      .from('memberships')
      .select('company_id')
      .eq('user_id', user.id);

    if (!memberships || memberships.length === 0) {
      return NextResponse.json({ pods: [] });
    }

    const companyIds = memberships.map(m => m.company_id);

    // Get all pods for user's communities
    const { data: pods, error: podsError } = await supabase
      .from('pods')
      .select(`
        *,
        site:sites(
          id,
          name,
          community:communities(
            id,
            name,
            company_id
          )
        ),
        cameras(
          id,
          name,
          status
        )
      `)
      .in('sites.communities.company_id', companyIds)
      .order('created_at', { ascending: false });

    if (podsError) {
      console.error('Error fetching pods:', podsError);
      return NextResponse.json(
        { error: 'Failed to fetch pods' },
        { status: 500 }
      );
    }

    // Calculate uptime and enrich data
    const enrichedPods = pods.map(pod => {
      const lastSeen = pod.last_heartbeat ? new Date(pod.last_heartbeat) : null;
      const now = new Date();
      const isOnline = lastSeen && (now.getTime() - lastSeen.getTime()) < 5 * 60 * 1000; // 5 minutes

      return {
        ...pod,
        isOnline,
        lastSeenMinutes: lastSeen ? Math.floor((now.getTime() - lastSeen.getTime()) / 60000) : null,
        cameraCount: pod.cameras?.length || 0,
        communityName: pod.site?.community?.name || 'Unknown',
        siteName: pod.site?.name || 'Unknown',
      };
    });

    return NextResponse.json({ pods: enrichedPods });
  } catch (error) {
    console.error('Error in pods list:', error);
    return NextResponse.json(
      { error: 'Internal server error' },
      { status: 500 }
    );
  }
}
