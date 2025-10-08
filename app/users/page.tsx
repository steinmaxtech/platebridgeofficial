'use client';

import { useEffect, useState } from 'react';
import { useAuth } from '@/lib/auth-context';
import { useCompany } from '@/lib/community-context';
import { useRouter } from 'next/navigation';
import { DashboardLayout } from '@/components/dashboard-layout';
import { Button } from '@/components/ui/button';
import { Input } from '@/components/ui/input';
import { Label } from '@/components/ui/label';
import { Card } from '@/components/ui/card';
import { Table, TableBody, TableCell, TableHead, TableHeader, TableRow } from '@/components/ui/table';
import { Dialog, DialogContent, DialogHeader, DialogTitle, DialogTrigger } from '@/components/ui/dialog';
import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from '@/components/ui/select';
import { supabase } from '@/lib/supabase';
import { Plus, Pencil, Trash2, Mail, Shield } from 'lucide-react';
import { toast } from 'sonner';

interface UserMembership {
  id: string;
  user_id: string;
  role: 'owner' | 'admin' | 'manager' | 'viewer' | 'resident';
  created_at: string;
  user_profiles: {
    id: string;
  } | null;
  auth_users?: {
    email: string;
  };
}

export default function UsersPage() {
  const { user, profile, loading, effectiveRole } = useAuth();
  const { activeCompanyId } = useCompany();
  const router = useRouter();
  const [users, setUsers] = useState<UserMembership[]>([]);
  const [loadingUsers, setLoadingUsers] = useState(true);
  const [isDialogOpen, setIsDialogOpen] = useState(false);
  const [editingUser, setEditingUser] = useState<UserMembership | null>(null);
  const [inviteEmail, setInviteEmail] = useState('');
  const [inviteRole, setInviteRole] = useState<'admin' | 'manager' | 'viewer' | 'resident'>('viewer');

  useEffect(() => {
    if (!loading && !user) {
      router.push('/login');
    }
  }, [user, loading, router]);

  useEffect(() => {
    if (user && profile && activeCompanyId) {
      fetchUsers();
    }
  }, [user, profile, activeCompanyId]);

  const fetchUsers = async () => {
    if (!activeCompanyId) return;
    setLoadingUsers(true);

    try {
      const { data: { session } } = await supabase.auth.getSession();
      if (!session) {
        toast.error('Not authenticated');
        setLoadingUsers(false);
        return;
      }

      const response = await fetch(`/api/users?companyId=${activeCompanyId}`, {
        headers: {
          'Authorization': `Bearer ${session.access_token}`,
        },
      });

      if (!response.ok) {
        const error = await response.json();
        toast.error(error.error || 'Failed to fetch users');
        setLoadingUsers(false);
        return;
      }

      const { users } = await response.json();
      setUsers(users);
    } catch (error) {
      console.error('Error fetching users:', error);
      toast.error('Failed to fetch users');
    }

    setLoadingUsers(false);
  };

  const handleInviteUser = async () => {
    if (!inviteEmail.trim()) {
      toast.error('Please enter an email address');
      return;
    }

    if (!activeCompanyId) {
      toast.error('No active company selected');
      return;
    }

    toast.info('User invitation feature coming soon. For now, users can sign up and be assigned roles.');
    setIsDialogOpen(false);
    resetForm();
  };

  const handleUpdateRole = async (membershipId: string, newRole: string) => {
    const { error } = await supabase
      .from('memberships')
      .update({ role: newRole })
      .eq('id', membershipId);

    if (error) {
      toast.error('Failed to update user role');
      return;
    }

    toast.success('User role updated successfully');
    fetchUsers();
  };

  const handleRemoveUser = async (membershipId: string, userEmail: string) => {
    if (confirm(`Are you sure you want to remove ${userEmail} from this company?`)) {
      const { error } = await supabase
        .from('memberships')
        .delete()
        .eq('id', membershipId);

      if (error) {
        toast.error('Failed to remove user');
        return;
      }

      toast.success('User removed successfully');
      fetchUsers();
    }
  };

  const resetForm = () => {
    setInviteEmail('');
    setInviteRole('viewer');
    setEditingUser(null);
  };

  const getRoleBadgeColor = (role: string) => {
    switch (role) {
      case 'owner':
        return 'bg-purple-100 text-purple-700 dark:bg-purple-900/20 dark:text-purple-400';
      case 'admin':
        return 'bg-blue-100 text-blue-700 dark:bg-blue-900/20 dark:text-blue-400';
      case 'manager':
        return 'bg-green-100 text-green-700 dark:bg-green-900/20 dark:text-green-400';
      case 'viewer':
        return 'bg-gray-100 text-gray-700 dark:bg-gray-800 dark:text-gray-400';
      case 'resident':
        return 'bg-cyan-100 text-cyan-700 dark:bg-cyan-900/20 dark:text-cyan-400';
      default:
        return 'bg-gray-100 text-gray-700 dark:bg-gray-800 dark:text-gray-400';
    }
  };

  if (loading || !user || !profile) {
    return (
      <div className="min-h-screen flex items-center justify-center bg-white dark:bg-[#1E293B]">
        <div className="text-lg">Loading...</div>
      </div>
    );
  }

  if (effectiveRole !== 'owner' && effectiveRole !== 'admin' && effectiveRole !== 'manager') {
    return (
      <DashboardLayout>
        <div className="max-w-4xl mx-auto">
          <Card className="p-8 text-center">
            <Shield className="w-12 h-12 mx-auto mb-4 text-muted-foreground" />
            <h3 className="text-xl font-semibold mb-2">Access Restricted</h3>
            <p className="text-muted-foreground">
              You don't have permission to manage users. Contact your administrator.
            </p>
          </Card>
        </div>
      </DashboardLayout>
    );
  }

  return (
    <DashboardLayout>
      <div className="max-w-6xl mx-auto">
        <div className="flex items-center justify-between mb-6">
          <div>
            <h2 className="text-3xl font-bold mb-2">Users</h2>
            <p className="text-muted-foreground">
              Manage team members and their access levels
            </p>
          </div>
          <Dialog open={isDialogOpen} onOpenChange={(open) => {
            setIsDialogOpen(open);
            if (!open) resetForm();
          }}>
            <DialogTrigger asChild>
              <Button className="rounded-xl bg-[#0A84FF] hover:bg-[#0869CC] font-semibold shadow-lg shadow-blue-500/30">
                <Plus className="w-4 h-4 mr-2" />
                Invite User
              </Button>
            </DialogTrigger>
            <DialogContent className="sm:max-w-md">
              <DialogHeader>
                <DialogTitle>Invite User</DialogTitle>
              </DialogHeader>
              <div className="space-y-4">
                <div>
                  <Label>Email Address</Label>
                  <Input
                    type="email"
                    value={inviteEmail}
                    onChange={(e) => setInviteEmail(e.target.value)}
                    placeholder="user@example.com"
                    className="mt-2"
                  />
                </div>

                <div>
                  <Label>Role</Label>
                  <Select value={inviteRole} onValueChange={(value: any) => setInviteRole(value)}>
                    <SelectTrigger className="mt-2">
                      <SelectValue />
                    </SelectTrigger>
                    <SelectContent>
                      {effectiveRole === 'owner' && (
                        <SelectItem value="admin">Admin</SelectItem>
                      )}
                      <SelectItem value="manager">Manager</SelectItem>
                      <SelectItem value="viewer">Viewer</SelectItem>
                      <SelectItem value="resident">Resident</SelectItem>
                    </SelectContent>
                  </Select>
                  <p className="text-xs text-muted-foreground mt-1">
                    {inviteRole === 'admin' && 'Full access to all features'}
                    {inviteRole === 'manager' && 'Can manage communities and plates'}
                    {inviteRole === 'viewer' && 'Read-only access to assigned properties'}
                    {inviteRole === 'resident' && 'Can view and manage their own vehicles'}
                  </p>
                </div>

                <Button
                  onClick={handleInviteUser}
                  className="w-full rounded-xl bg-[#0A84FF] hover:bg-[#0869CC]"
                >
                  <Mail className="w-4 h-4 mr-2" />
                  Send Invitation
                </Button>
              </div>
            </DialogContent>
          </Dialog>
        </div>

        <Card className="p-6 shadow-lg border-0 bg-white dark:bg-[#2D3748]">
          {loadingUsers ? (
            <div className="text-center py-8">Loading users...</div>
          ) : users.length === 0 ? (
            <div className="text-center py-8 text-muted-foreground">
              No users yet. Invite your first team member.
            </div>
          ) : (
            <Table>
              <TableHeader>
                <TableRow>
                  <TableHead>Email</TableHead>
                  <TableHead>Role</TableHead>
                  <TableHead>Joined</TableHead>
                  <TableHead className="text-right">Actions</TableHead>
                </TableRow>
              </TableHeader>
              <TableBody>
                {users.map((membership) => (
                  <TableRow key={membership.id}>
                    <TableCell className="font-medium">
                      {membership.auth_users?.email || 'Unknown'}
                    </TableCell>
                    <TableCell>
                      {(effectiveRole === 'owner' || effectiveRole === 'admin') && membership.user_id !== user.id ? (
                        <Select
                          value={membership.role}
                          onValueChange={(value) => handleUpdateRole(membership.id, value)}
                        >
                          <SelectTrigger className="w-32">
                            <SelectValue />
                          </SelectTrigger>
                          <SelectContent>
                            {effectiveRole === 'owner' && (
                              <>
                                <SelectItem value="owner">Owner</SelectItem>
                                <SelectItem value="admin">Admin</SelectItem>
                              </>
                            )}
                            <SelectItem value="manager">Manager</SelectItem>
                            <SelectItem value="viewer">Viewer</SelectItem>
                            <SelectItem value="resident">Resident</SelectItem>
                          </SelectContent>
                        </Select>
                      ) : (
                        <span className={`inline-block px-3 py-1 rounded-full text-xs font-medium ${getRoleBadgeColor(membership.role)}`}>
                          {membership.role}
                          {membership.user_id === user.id && ' (You)'}
                        </span>
                      )}
                    </TableCell>
                    <TableCell className="text-muted-foreground">
                      {new Date(membership.created_at).toLocaleDateString()}
                    </TableCell>
                    <TableCell className="text-right">
                      {membership.user_id !== user.id && (effectiveRole === 'owner' || effectiveRole === 'admin') && (
                        <Button
                          variant="outline"
                          size="sm"
                          onClick={() => handleRemoveUser(membership.id, membership.auth_users?.email || 'this user')}
                          className="rounded-lg text-red-600 hover:text-red-700"
                        >
                          <Trash2 className="w-4 h-4" />
                        </Button>
                      )}
                    </TableCell>
                  </TableRow>
                ))}
              </TableBody>
            </Table>
          )}
        </Card>

        <Card className="mt-6 p-6 bg-gradient-to-br from-blue-50 to-cyan-50 dark:from-blue-950/30 dark:to-cyan-950/30">
          <h3 className="font-semibold mb-2">Role Permissions</h3>
          <div className="grid md:grid-cols-2 gap-4 text-sm">
            <div>
              <p className="font-medium text-purple-700 dark:text-purple-400">Owner / Admin</p>
              <p className="text-muted-foreground text-xs">Full system access and user management</p>
            </div>
            <div>
              <p className="font-medium text-green-700 dark:text-green-400">Manager</p>
              <p className="text-muted-foreground text-xs">Manage communities, sites, and plates</p>
            </div>
            <div>
              <p className="font-medium text-gray-700 dark:text-gray-400">Viewer</p>
              <p className="text-muted-foreground text-xs">Read-only access to data</p>
            </div>
            <div>
              <p className="font-medium text-cyan-700 dark:text-cyan-400">Resident</p>
              <p className="text-muted-foreground text-xs">Can view and manage own vehicles only</p>
            </div>
          </div>
        </Card>
      </div>
    </DashboardLayout>
  );
}
