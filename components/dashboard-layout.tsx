'use client';

import { useAuth } from '@/lib/auth-context';
import { useTheme } from '@/lib/theme-provider';
import { useCompany } from '@/lib/community-context';
import { Logo } from '@/components/logo';
import { Button } from '@/components/ui/button';
import { RoleSwitcher } from '@/components/role-switcher';
import { Moon, Sun, LayoutDashboard, List, Building2, Users, FileText, Settings, Building, Home, MapPin, Camera, Server } from 'lucide-react';
import Link from 'next/link';
import { usePathname } from 'next/navigation';
import { cn } from '@/lib/utils';

interface DashboardLayoutProps {
  children: React.ReactNode;
}

export function DashboardLayout({ children }: DashboardLayoutProps) {
  const { user, profile, signOut, effectiveRole } = useAuth();
  const { theme, toggleTheme } = useTheme();
  const { activeCompany, memberships, setActiveCompanyId, activeRole } = useCompany();
  const pathname = usePathname();

  const isOwnerOrAdmin = profile?.role === 'owner' || profile?.role === 'admin';
  const effectiveIsAdmin = effectiveRole === 'owner' || effectiveRole === 'admin';
  const effectiveIsManager = effectiveRole === 'manager';
  const effectiveIsResident = effectiveRole === 'resident';

  const allNavItems = [
    { href: '/dashboard', label: 'Dashboard', icon: LayoutDashboard, roles: ['owner', 'admin', 'manager', 'viewer', 'resident'] },
    { href: '/companies', label: 'Companies', icon: Building, roles: ['owner', 'admin'] },
    { href: '/communities', label: 'Communities', icon: Home, roles: ['owner', 'admin', 'manager'] },
    { href: '/pods', label: 'PODs', icon: Server, roles: ['owner', 'admin', 'manager'] },
    { href: '/cameras', label: 'Cameras', icon: Camera, roles: ['owner', 'admin', 'manager', 'viewer'] },
    { href: '/users', label: 'Users', icon: Users, roles: ['owner', 'admin', 'manager'] },
    { href: '/plates', label: 'Plates', icon: List, roles: ['owner', 'admin', 'manager', 'resident'] },
    { href: '/audit', label: 'Audit', icon: FileText, roles: ['owner', 'admin', 'manager'] },
    { href: '/settings', label: 'Settings', icon: Settings, roles: ['owner', 'admin', 'manager', 'viewer', 'resident'] },
  ];

  const navItems = allNavItems.filter(item =>
    effectiveRole && item.roles.includes(effectiveRole)
  );

  return (
    <div className="min-h-screen bg-[#F7F9FC] dark:bg-[#1E293B]">
      <header className="border-b border-gray-200 dark:border-gray-700 bg-white dark:bg-[#2D3748] shadow-sm sticky top-0 z-50">
        <div className="container mx-auto px-6 h-20 flex items-center justify-between">
          <div className="flex items-center gap-3">
            <Logo className="w-11 h-11 shadow-md shadow-blue-500/20" />
            <h1 className="text-2xl font-bold tracking-tight">PlateBridge</h1>
          </div>
          <div className="flex items-center gap-4">
            {memberships.length > 0 && (
              <div className="flex items-center gap-2">
                <Building className="w-4 h-4 text-gray-500" />
                <select
                  value={activeCompany?.id || ''}
                  onChange={(e) => setActiveCompanyId(e.target.value)}
                  className="h-9 rounded-xl border-2 px-3 text-sm font-medium bg-white dark:bg-[#2D3748] cursor-pointer"
                >
                  {memberships.map((m) => {
                    const company = Array.isArray(m.companies) ? m.companies[0] : m.companies;
                    return (
                      <option key={m.id} value={m.company_id}>
                        {company.name}
                      </option>
                    );
                  })}
                </select>
                {effectiveRole && (
                  <span className={cn(
                    "text-xs px-2 py-1 rounded-lg font-medium capitalize",
                    profile?.view_as_role
                      ? "bg-amber-100 dark:bg-amber-900/20 text-amber-700 dark:text-amber-400"
                      : "bg-blue-100 dark:bg-blue-900/20 text-blue-700 dark:text-blue-400"
                  )}>
                    {effectiveRole} {profile?.view_as_role && '(View As)'}
                  </span>
                )}
              </div>
            )}
            <button
              onClick={toggleTheme}
              className="p-2 rounded-xl bg-gray-100 dark:bg-slate-600 hover:bg-gray-200 dark:hover:bg-slate-500 transition-colors"
              aria-label="Toggle theme"
            >
              {theme === 'dark' ? (
                <Sun className="w-4 h-4 text-gray-700 dark:text-gray-200" />
              ) : (
                <Moon className="w-4 h-4 text-gray-700" />
              )}
            </button>
            <div className="text-sm">
              <div className="font-semibold">{user?.email}</div>
              <div className="text-xs text-muted-foreground capitalize">{profile?.role}</div>
            </div>
            <Button variant="outline" onClick={signOut} className="rounded-xl border-2 font-semibold hover:bg-gray-50 dark:hover:bg-slate-700">
              Sign Out
            </Button>
          </div>
        </div>
      </header>

      <div className="flex">
        <aside className="w-64 bg-white dark:bg-[#2D3748] border-r border-gray-200 dark:border-gray-700 min-h-[calc(100vh-5rem)] sticky top-20">
          <nav className="p-4 space-y-2">
            {isOwnerOrAdmin && (
              <div className="mb-4">
                <RoleSwitcher />
              </div>
            )}
            {navItems.map((item) => {
              const Icon = item.icon;
              const isActive = pathname === item.href;

              return (
                <Link
                  key={item.href}
                  href={item.href}
                  className={cn(
                    "flex items-center gap-3 px-4 py-3 rounded-xl font-medium transition-colors",
                    isActive
                      ? "bg-blue-50 dark:bg-blue-900/20 text-blue-600 dark:text-blue-400"
                      : "text-gray-700 dark:text-gray-300 hover:bg-gray-100 dark:hover:bg-slate-700"
                  )}
                >
                  <Icon className="w-5 h-5" />
                  <span>{item.label}</span>
                </Link>
              );
            })}
          </nav>
        </aside>

        <main className="flex-1 p-8">
          {children}
        </main>
      </div>
    </div>
  );
}
