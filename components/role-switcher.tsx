'use client';

import { useAuth } from '@/lib/auth-context';
import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from '@/components/ui/select';
import { Label } from '@/components/ui/label';
import { Eye, UserCircle } from 'lucide-react';
import { Card } from '@/components/ui/card';

export function RoleSwitcher() {
  const { profile, effectiveRole, setViewAsRole } = useAuth();

  if (!profile || (profile.role !== 'owner' && profile.role !== 'admin')) {
    return null;
  }

  const roles = [
    { value: null, label: `${profile.role.charAt(0).toUpperCase() + profile.role.slice(1)} (Your Role)` },
    { value: 'admin', label: 'Admin View' },
    { value: 'manager', label: 'Property Manager View' },
    { value: 'viewer', label: 'Viewer View' },
    { value: 'resident', label: 'Resident View' },
  ];

  return (
    <Card className="p-4 mb-4 border-amber-200 bg-amber-50 dark:bg-amber-950/20 dark:border-amber-900">
      <div className="flex items-start gap-3">
        <div className="p-2 rounded-lg bg-amber-100 dark:bg-amber-900/30">
          <Eye className="w-5 h-5 text-amber-600 dark:text-amber-400" />
        </div>
        <div className="flex-1">
          <div className="flex items-center gap-2 mb-2">
            <Label className="text-sm font-semibold text-amber-900 dark:text-amber-100">
              View As (Testing Mode)
            </Label>
          </div>
          <p className="text-xs text-amber-700 dark:text-amber-300 mb-3">
            Switch between different role views to test the interface. This only affects the UI, not database permissions.
          </p>
          <Select
            value={profile.view_as_role || 'actual'}
            onValueChange={(value) => setViewAsRole(value === 'actual' ? null : value)}
          >
            <SelectTrigger className="w-full bg-white dark:bg-slate-800">
              <div className="flex items-center gap-2">
                <UserCircle className="w-4 h-4" />
                <SelectValue />
              </div>
            </SelectTrigger>
            <SelectContent>
              <SelectItem value="actual">
                {profile.role.charAt(0).toUpperCase() + profile.role.slice(1)} (Your Actual Role)
              </SelectItem>
              {profile.role !== 'admin' && <SelectItem value="admin">Admin View</SelectItem>}
              <SelectItem value="manager">Property Manager View</SelectItem>
              <SelectItem value="viewer">Viewer View</SelectItem>
              <SelectItem value="resident">Resident View</SelectItem>
            </SelectContent>
          </Select>
          {profile.view_as_role && (
            <p className="text-xs text-amber-600 dark:text-amber-400 mt-2 font-medium">
              Currently viewing as: {profile.view_as_role.charAt(0).toUpperCase() + profile.view_as_role.slice(1)}
            </p>
          )}
        </div>
      </div>
    </Card>
  );
}
