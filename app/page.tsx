'use client';

import { useEffect } from 'react';
import { useAuth } from '@/lib/auth-context';
import { useRouter } from 'next/navigation';
import { Button } from '@/components/ui/button';
import { Logo } from '@/components/logo';
import { useTheme } from '@/lib/theme-provider';
import { Moon, Sun } from 'lucide-react';

export default function Home() {
  const { user, loading } = useAuth();
  const router = useRouter();
  const { theme, toggleTheme } = useTheme();

  useEffect(() => {
    if (!loading && user) {
      router.push('/dashboard');
    }
  }, [user, loading, router]);

  if (!loading && !user) {
    return (
      <div className="min-h-screen flex items-center justify-center bg-white dark:bg-[#1E293B] relative">
        <button
          onClick={toggleTheme}
          className="absolute top-6 right-6 p-3 rounded-2xl bg-gray-100 dark:bg-slate-700 hover:bg-gray-200 dark:hover:bg-slate-600 transition-colors"
          aria-label="Toggle theme"
        >
          {theme === 'dark' ? (
            <Sun className="w-5 h-5 text-gray-700 dark:text-gray-200" />
          ) : (
            <Moon className="w-5 h-5 text-gray-700" />
          )}
        </button>

        <div className="text-center space-y-10 max-w-2xl px-4">
          <div className="flex items-center justify-center gap-4">
            <Logo className="w-20 h-20 shadow-lg shadow-blue-500/20" />
            <h1 className="text-6xl font-bold tracking-tight">PlateBridge</h1>
          </div>

          <p className="text-2xl text-muted-foreground font-medium">
            Seamless Plate-to-Gate Access
          </p>

          <div className="flex items-center justify-center gap-4 pt-6">
            <Button
              variant="outline"
              size="lg"
              onClick={() => router.push('/login')}
              className="h-14 px-10 text-base rounded-2xl border-2 font-semibold hover:bg-gray-50 dark:hover:bg-slate-800"
            >
              Sign In
            </Button>
            <Button
              size="lg"
              onClick={() => router.push('/login')}
              className="h-14 px-10 text-base rounded-2xl bg-[#0A84FF] hover:bg-[#0869CC] font-semibold shadow-lg shadow-blue-500/30"
            >
              Start Free Demo
            </Button>
          </div>
        </div>
      </div>
    );
  }

  return (
    <div className="min-h-screen flex items-center justify-center bg-white dark:bg-[#1E293B]">
      <div className="flex items-center gap-3">
        <Logo className="w-10 h-10" />
        <span className="text-lg font-semibold">Loading...</span>
      </div>
    </div>
  );
}
