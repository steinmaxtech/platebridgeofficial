import { NextRequest, NextResponse } from 'next/server';
import { supabaseServer } from '@/lib/supabase-server';

const VALID_COMMANDS = ['restart', 'update', 'reboot', 'refresh_config', 'test_camera', 'clear_cache'];

export async function POST(
  request: NextRequest,
  { params }: { params: { id: string } }
) {
  try {
    const supabase = supabaseServer;
    const podId = params.id;
    const body = await request.json();
    const { command, parameters } = body;

    if (!command || !VALID_COMMANDS.includes(command)) {
      return NextResponse.json(
        { error: 'Invalid command. Valid commands: ' + VALID_COMMANDS.join(', ') },
        { status: 400 }
      );
    }

    // Get current user
    const { data: { user }, error: authError } = await supabase.auth.getUser();

    if (authError || !user) {
      return NextResponse.json(
        { error: 'Unauthorized' },
        { status: 401 }
      );
    }

    // Check if pod exists and get community
    const { data: pod } = await supabase
      .from('pods')
      .select('id, site_id, sites(community_id, communities(company_id))')
      .eq('id', podId)
      .maybeSingle();

    if (!pod || !pod.sites) {
      return NextResponse.json(
        { error: 'POD not found' },
        { status: 404 }
      );
    }

    const companyId = (pod.sites as any).communities?.company_id;

    if (!companyId) {
      return NextResponse.json(
        { error: 'Could not determine community' },
        { status: 500 }
      );
    }

    // Check user has admin/manager role
    const { data: membership } = await supabase
      .from('memberships')
      .select('role')
      .eq('user_id', user.id)
      .eq('company_id', companyId)
      .maybeSingle();

    if (!membership || !['owner', 'admin', 'manager'].includes(membership.role)) {
      return NextResponse.json(
        { error: 'Insufficient permissions. Admin or Manager role required.' },
        { status: 403 }
      );
    }

    // Create command
    const { data: newCommand, error: commandError } = await supabase
      .from('pod_commands')
      .insert({
        pod_id: podId,
        command,
        parameters: parameters || {},
        status: 'queued',
        created_by: user.id,
      })
      .select('*')
      .single();

    if (commandError) {
      console.error('Error creating command:', commandError);
      return NextResponse.json(
        { error: 'Failed to create command' },
        { status: 500 }
      );
    }

    return NextResponse.json({
      command: newCommand,
      message: `Command '${command}' queued successfully`,
    });
  } catch (error) {
    console.error('Error in pod command:', error);
    return NextResponse.json(
      { error: 'Internal server error' },
      { status: 500 }
    );
  }
}

// GET endpoint for POD to fetch pending commands
export async function GET(
  request: NextRequest,
  { params }: { params: { id: string } }
) {
  try {
    const supabase = supabaseServer;
    const podId = params.id;

    // TODO: Authenticate POD via API key from Authorization header

    // Get pending commands
    const { data: commands, error } = await supabase
      .from('pod_commands')
      .select('*')
      .eq('pod_id', podId)
      .in('status', ['queued', 'sent'])
      .order('created_at', { ascending: true });

    if (error) {
      console.error('Error fetching commands:', error);
      return NextResponse.json(
        { error: 'Failed to fetch commands' },
        { status: 500 }
      );
    }

    // Mark commands as sent
    if (commands && commands.length > 0) {
      const commandIds = commands.map(c => c.id);
      await supabase
        .from('pod_commands')
        .update({ status: 'sent', sent_at: new Date().toISOString() })
        .in('id', commandIds)
        .eq('status', 'queued');
    }

    return NextResponse.json({ commands: commands || [] });
  } catch (error) {
    console.error('Error in pod command fetch:', error);
    return NextResponse.json(
      { error: 'Internal server error' },
      { status: 500 }
    );
  }
}

// PATCH endpoint for POD to update command status
export async function PATCH(
  request: NextRequest,
  { params }: { params: { id: string } }
) {
  try {
    const supabase = supabaseServer;
    const body = await request.json();
    const { command_id, status, result, error_message } = body;

    if (!command_id || !status) {
      return NextResponse.json(
        { error: 'command_id and status are required' },
        { status: 400 }
      );
    }

    const updateData: any = {
      status,
      executed_at: new Date().toISOString(),
    };

    if (status === 'completed') {
      updateData.completed_at = new Date().toISOString();
      updateData.result = result || {};
    }

    if (status === 'failed' && error_message) {
      updateData.error_message = error_message;
    }

    const { error } = await supabase
      .from('pod_commands')
      .update(updateData)
      .eq('id', command_id);

    if (error) {
      console.error('Error updating command:', error);
      return NextResponse.json(
        { error: 'Failed to update command' },
        { status: 500 }
      );
    }

    return NextResponse.json({ success: true });
  } catch (error) {
    console.error('Error in pod command update:', error);
    return NextResponse.json(
      { error: 'Internal server error' },
      { status: 500 }
    );
  }
}
