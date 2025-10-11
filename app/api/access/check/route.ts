import { createClient } from '@/lib/supabase-server';
import { NextRequest, NextResponse } from 'next/server';

/**
 * POST /api/access/check
 * Called by PODs to check if a detected plate should be granted access
 */
export async function POST(request: NextRequest) {
  try {
    const supabase = createClient();
    const body = await request.json();

    const { plate, community_id, pod_id, confidence = 100 } = body;

    if (!plate || !community_id) {
      return NextResponse.json(
        { error: 'Missing required fields: plate, community_id' },
        { status: 400 }
      );
    }

    // Call the database function to check access
    const { data: accessResult, error: checkError } = await supabase
      .rpc('check_plate_access', {
        p_plate: plate,
        p_community_id: community_id,
        p_confidence: confidence,
      });

    if (checkError) {
      console.error('Error checking plate access:', checkError);
      return NextResponse.json(
        { error: 'Failed to check access' },
        { status: 500 }
      );
    }

    // Log the access decision
    const logData = {
      pod_id: pod_id || null,
      community_id,
      plate,
      decision: accessResult.access === 'granted' ? 'granted' : 'denied',
      reason: accessResult.reason,
      access_type: accessResult.type || null,
      vendor_name: accessResult.vendor || null,
      confidence,
      gate_triggered: accessResult.access === 'granted',
    };

    const { error: logError } = await supabase
      .from('access_logs')
      .insert([logData]);

    if (logError) {
      console.error('Error logging access decision:', logError);
      // Don't fail the request if logging fails
    }

    return NextResponse.json(accessResult);
  } catch (error) {
    console.error('Error in access check:', error);
    return NextResponse.json(
      { error: 'Internal server error' },
      { status: 500 }
    );
  }
}
