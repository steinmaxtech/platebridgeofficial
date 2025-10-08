import { NextRequest, NextResponse } from 'next/server';
import { supabaseServer } from '@/lib/supabase-server';

export const dynamic = 'force-dynamic';

export async function GET(request: NextRequest) {
  const searchParams = request.nextUrl.searchParams;
  const siteName = searchParams.get('site');
  const companyId = searchParams.get('company_id');

  if (!siteName) {
    return NextResponse.json(
      { error: 'Site parameter is required' },
      { status: 400 }
    );
  }

  if (!companyId) {
    return NextResponse.json(
      { error: 'Company ID parameter is required' },
      { status: 400 }
    );
  }

  try {
    const { data: site, error: siteError } = await supabaseServer
      .from('sites')
      .select('id, config_version, community_id')
      .eq('site_id', siteName)
      .maybeSingle();

    if (siteError || !site) {
      return NextResponse.json(
        { error: 'Site not found' },
        { status: 404 }
      );
    }

    const { data: community, error: communityError } = await supabaseServer
      .from('communities')
      .select('company_id')
      .eq('id', site.community_id)
      .maybeSingle();

    if (communityError || !community || community.company_id !== companyId) {
      return NextResponse.json(
        { error: 'Site not found or company mismatch' },
        { status: 404 }
      );
    }

    const { data: plates, error: platesError } = await supabaseServer
      .from('plates')
      .select('*')
      .eq('community_id', site.community_id)
      .contains('site_ids', [siteName])
      .eq('enabled', true);

    if (platesError) {
      return NextResponse.json(
        { error: 'Failed to fetch plates' },
        { status: 500 }
      );
    }

    return NextResponse.json({
      config_version: site.config_version,
      site: siteName,
      company_id: companyId,
      entries: plates || [],
      timestamp: new Date().toISOString()
    });
  } catch (error) {
    console.error('Plates API error:', error);
    return NextResponse.json(
      { error: 'Internal server error' },
      { status: 500 }
    );
  }
}
