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
import { Dialog, DialogContent, DialogHeader, DialogTitle, DialogTrigger, DialogDescription, DialogFooter } from '@/components/ui/dialog';
import { AlertDialog, AlertDialogAction, AlertDialogCancel, AlertDialogContent, AlertDialogDescription, AlertDialogFooter, AlertDialogHeader, AlertDialogTitle } from '@/components/ui/alert-dialog';
import { Switch } from '@/components/ui/switch';
import { Building2, Plus, Users, Trash2 } from 'lucide-react';
import { supabase } from '@/lib/supabase';
import { toast } from 'sonner';

interface Company {
  id: string;
  name: string;
  is_active: boolean;
  created_at: string;
}

export default function CompaniesPage() {
  const { user, profile, loading: authLoading, effectiveRole } = useAuth();
  const { activeCompanyId, activeRole, effectiveRole: contextEffectiveRole, refreshMemberships } = useCompany();
  const router = useRouter();
  const [companies, setCompanies] = useState<Company[]>([]);
  const [loading, setLoading] = useState(true);
  const [isDialogOpen, setIsDialogOpen] = useState(false);
  const [editingCompany, setEditingCompany] = useState<Company | null>(null);
  const [formData, setFormData] = useState({ name: '', is_active: true });
  const [deleteDialogOpen, setDeleteDialogOpen] = useState(false);
  const [companyToDelete, setCompanyToDelete] = useState<Company | null>(null);
  const [deleteConfirmation, setDeleteConfirmation] = useState('');

  useEffect(() => {
    if (!authLoading && !user) {
      router.push('/login');
    }
  }, [user, authLoading, router]);

  const fetchCompanies = async () => {
    setLoading(true);
    const { data, error } = await supabase
      .from('companies')
      .select('*')
      .order('name');

    if (!error && data) {
      setCompanies(data);
    }
    setLoading(false);
  };

  useEffect(() => {
    if (user && (effectiveRole === 'owner' || effectiveRole === 'admin')) {
      fetchCompanies();
    }
  }, [user, effectiveRole]);

  if (effectiveRole && effectiveRole !== 'owner' && effectiveRole !== 'admin') {
    return (
      <DashboardLayout>
        <Card className="p-12 text-center max-w-2xl mx-auto">
          <Building2 className="w-16 h-16 mx-auto mb-4 text-muted-foreground" />
          <h3 className="text-xl font-semibold mb-2">Access Restricted</h3>
          <p className="text-muted-foreground">
            Only administrators can manage companies.
          </p>
        </Card>
      </DashboardLayout>
    );
  }

  const handleSubmit = async (e: React.FormEvent) => {
    e.preventDefault();

    const { data: { session } } = await supabase.auth.getSession();
    console.log('Current session:', session);
    console.log('User ID:', user?.id);

    if (editingCompany) {
      const { error } = await supabase
        .from('companies')
        .update({
          name: formData.name,
          is_active: formData.is_active,
          updated_at: new Date().toISOString(),
        })
        .eq('id', editingCompany.id);

      if (error) {
        console.error('Update company error:', error);
        toast.error(`Failed to update company: ${error.message}`);
        return;
      }
      toast.success('Company updated successfully');
    } else {
      const companyId = crypto.randomUUID();

      const { error: insertError } = await supabase
        .from('companies')
        .insert({
          id: companyId,
          name: formData.name,
          is_active: formData.is_active,
        });

      if (insertError) {
        console.error('Create company error:', insertError);
        toast.error(`Failed to create company: ${insertError.message}`);
        return;
      }

      if (user) {
        const { error: membershipError } = await supabase
          .from('memberships')
          .insert({
            user_id: user.id,
            company_id: companyId,
            role: 'owner',
          });

        if (membershipError) {
          console.error('Create membership error:', membershipError);
          toast.error(`Failed to create membership: ${membershipError.message}`);
          return;
        }
      }

      toast.success('Company created successfully');
    }

    setIsDialogOpen(false);
    setEditingCompany(null);
    setFormData({ name: '', is_active: true });
    fetchCompanies();
    refreshMemberships();
  };

  const openEditDialog = (company: Company) => {
    setEditingCompany(company);
    setFormData({
      name: company.name,
      is_active: company.is_active,
    });
    setIsDialogOpen(true);
  };

  const openCreateDialog = () => {
    setEditingCompany(null);
    setFormData({ name: '', is_active: true });
    setIsDialogOpen(true);
  };

  const openDeleteDialog = (company: Company, e: React.MouseEvent) => {
    e.stopPropagation();
    setCompanyToDelete(company);
    setDeleteConfirmation('');
    setDeleteDialogOpen(true);
  };

  const handleDelete = async () => {
    if (!companyToDelete || deleteConfirmation !== 'DELETE') {
      toast.error('Please type DELETE to confirm');
      return;
    }

    const { error } = await supabase
      .from('companies')
      .delete()
      .eq('id', companyToDelete.id);

    if (error) {
      console.error('Delete company error:', error);
      toast.error(`Failed to delete company: ${error.message}`);
      return;
    }

    toast.success('Company deleted successfully');
    setDeleteDialogOpen(false);
    setCompanyToDelete(null);
    setDeleteConfirmation('');
    fetchCompanies();
    refreshMemberships();
  };

  if (authLoading || loading || !user || !profile) {
    return (
      <div className="min-h-screen flex items-center justify-center bg-white dark:bg-[#1E293B]">
        <div className="text-lg">Loading...</div>
      </div>
    );
  }

  const canManage = activeRole === 'owner' || activeRole === 'admin';

  return (
    <DashboardLayout>
      <div className="max-w-6xl mx-auto">
        <div className="flex items-center justify-between mb-8">
          <div>
            <h2 className="text-3xl font-bold mb-2">Companies</h2>
            <p className="text-muted-foreground">
              Manage your companies and their settings
            </p>
          </div>
          <Dialog open={isDialogOpen} onOpenChange={setIsDialogOpen}>
            <DialogTrigger asChild>
              <Button onClick={openCreateDialog} className="rounded-xl bg-[#0A84FF] hover:bg-[#0869CC]">
                <Plus className="w-4 h-4 mr-2" />
                New Company
              </Button>
            </DialogTrigger>
            <DialogContent className="sm:max-w-[500px]">
              <DialogHeader>
                <DialogTitle>
                  {editingCompany ? 'Edit Company' : 'Create New Company'}
                </DialogTitle>
              </DialogHeader>
              <form onSubmit={handleSubmit} className="space-y-4 mt-4">
                <div className="space-y-2">
                  <Label htmlFor="name">Company Name</Label>
                  <Input
                    id="name"
                    value={formData.name}
                    onChange={(e) => setFormData({ ...formData, name: e.target.value })}
                    required
                    placeholder="Acme Property Management"
                  />
                </div>

                <div className="flex items-center justify-between">
                  <Label htmlFor="is_active">Active</Label>
                  <Switch
                    id="is_active"
                    checked={formData.is_active}
                    onCheckedChange={(checked) => setFormData({ ...formData, is_active: checked })}
                  />
                </div>

                <div className="flex flex-col gap-3 pt-4">
                  <div className="flex gap-3">
                    <Button
                      type="button"
                      variant="outline"
                      onClick={() => setIsDialogOpen(false)}
                      className="flex-1"
                    >
                      Cancel
                    </Button>
                    <Button type="submit" className="flex-1 bg-[#0A84FF] hover:bg-[#0869CC]">
                      {editingCompany ? 'Update' : 'Create'}
                    </Button>
                  </div>
                  {editingCompany && canManage && (
                    <Button
                      type="button"
                      variant="destructive"
                      onClick={(e) => {
                        e.preventDefault();
                        setIsDialogOpen(false);
                        openDeleteDialog(editingCompany, e);
                      }}
                      className="w-full"
                    >
                      <Trash2 className="w-4 h-4 mr-2" />
                      Delete Company
                    </Button>
                  )}
                </div>
              </form>
            </DialogContent>
          </Dialog>
        </div>

        {companies.length === 0 ? (
          <Card className="p-12 text-center">
            <Building2 className="w-16 h-16 mx-auto mb-4 text-muted-foreground" />
            <h3 className="text-xl font-semibold mb-2">No companies yet</h3>
            <p className="text-muted-foreground mb-6">
              Get started by creating your first company
            </p>
            <Button onClick={openCreateDialog} className="rounded-xl bg-[#0A84FF] hover:bg-[#0869CC]">
              <Plus className="w-4 h-4 mr-2" />
              Create Company
            </Button>
          </Card>
        ) : (
          <div className="grid gap-4 md:grid-cols-2 lg:grid-cols-3">
            {companies.map((company) => (
              <Card
                key={company.id}
                className="p-6 hover:shadow-lg transition-shadow"
              >
                <div
                  className="cursor-pointer"
                  onClick={() => canManage && openEditDialog(company)}
                >
                  <div className="flex items-start justify-between mb-4">
                    <div className="p-3 rounded-2xl bg-blue-50 dark:bg-blue-900/20">
                      <Building2 className="w-6 h-6 text-blue-600 dark:text-blue-400" />
                    </div>
                    <div className={`px-3 py-1 rounded-full text-xs font-medium ${
                      company.is_active
                        ? 'bg-green-100 dark:bg-green-900/20 text-green-700 dark:text-green-400'
                        : 'bg-gray-100 dark:bg-gray-800 text-gray-700 dark:text-gray-400'
                    }`}>
                      {company.is_active ? 'Active' : 'Inactive'}
                    </div>
                  </div>
                  <h3 className="font-bold text-lg mb-2">{company.name}</h3>
                </div>
                <Button
                  variant="ghost"
                  className="w-full justify-start p-0 h-auto text-sm text-muted-foreground hover:text-foreground mt-2"
                  onClick={() => router.push(`/communities?company_id=${company.id}`)}
                >
                  <Users className="w-4 h-4 mr-2" />
                  <span>View communities</span>
                </Button>
              </Card>
            ))}
          </div>
        )}

        <AlertDialog open={deleteDialogOpen} onOpenChange={setDeleteDialogOpen}>
          <AlertDialogContent>
            <AlertDialogHeader>
              <AlertDialogTitle>Delete Company</AlertDialogTitle>
              <AlertDialogDescription>
                This will permanently delete <strong>{companyToDelete?.name}</strong> and all associated data.
                This action cannot be undone.
              </AlertDialogDescription>
            </AlertDialogHeader>
            <div className="my-4">
              <Label htmlFor="delete-confirm">Type DELETE to confirm</Label>
              <Input
                id="delete-confirm"
                value={deleteConfirmation}
                onChange={(e) => setDeleteConfirmation(e.target.value)}
                placeholder="DELETE"
                className="mt-2"
              />
            </div>
            <AlertDialogFooter>
              <AlertDialogCancel onClick={() => {
                setDeleteDialogOpen(false);
                setDeleteConfirmation('');
              }}>
                Cancel
              </AlertDialogCancel>
              <Button
                variant="destructive"
                onClick={handleDelete}
                disabled={deleteConfirmation !== 'DELETE'}
              >
                Delete Company
              </Button>
            </AlertDialogFooter>
          </AlertDialogContent>
        </AlertDialog>
      </div>
    </DashboardLayout>
  );
}
