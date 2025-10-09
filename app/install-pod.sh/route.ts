import { NextResponse } from 'next/server';
import fs from 'fs';
import path from 'path';

export const dynamic = 'force-dynamic';

export async function GET() {
  try {
    const filePath = path.join(process.cwd(), 'public', 'install-pod.sh');
    const fileContent = fs.readFileSync(filePath, 'utf-8');

    return new NextResponse(fileContent, {
      headers: {
        'Content-Type': 'text/plain',
        'Content-Disposition': 'inline; filename="install-pod.sh"',
      },
    });
  } catch (error) {
    console.error('Error serving install script:', error);
    return new NextResponse('Script not found', { status: 404 });
  }
}
