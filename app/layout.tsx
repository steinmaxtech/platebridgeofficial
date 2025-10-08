import './globals.css';
import type { Metadata } from 'next';
import { AuthProvider } from '@/lib/auth-context';
import { ThemeProvider } from '@/lib/theme-provider';
import { CommunityProvider } from '@/lib/community-context';
import { Inter } from 'next/font/google';

const inter = Inter({ subsets: ['latin'] });

export const metadata: Metadata = {
  title: 'PlateBridge - Seamless Plate-to-Gate Access',
  description: 'Modern license plate recognition and management system for seamless property access control',
};

export default function RootLayout({
  children,
}: {
  children: React.ReactNode;
}) {
  return (
    <html lang="en" suppressHydrationWarning>
      <body className={inter.className}>
        <ThemeProvider>
          <AuthProvider>
            <CommunityProvider>
              {children}
            </CommunityProvider>
          </AuthProvider>
        </ThemeProvider>
      </body>
    </html>
  );
}
