import { NextResponse } from 'next/server';
import { readFile } from 'fs/promises';
import { join } from 'path';

export async function GET() {
  try {
    const scriptPath = join(process.cwd(), 'public', 'install-pod-docker.sh');
    const script = await readFile(scriptPath, 'utf-8');

    return new NextResponse(script, {
      headers: {
        'Content-Type': 'text/plain',
        'Content-Disposition': 'inline; filename="install-pod-docker.sh"',
      },
    });
  } catch (error) {
    return NextResponse.json(
      { error: 'Install script not found' },
      { status: 404 }
    );
  }
}
