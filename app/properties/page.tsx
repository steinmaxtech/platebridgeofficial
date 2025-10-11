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
import { Dialog, DialogContent, DialogHeader, DialogTitle, DialogTrigger } from '@/components/ui/dialog';
import { supabase } from '@/lib/supabase';
import { Plus, Pencil, Building2, Trash2, Copy, Check } from 'lucide-react';
import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from '@/components/ui/select';
import { AlertDialog, AlertDialogAction, AlertDialogCancel, AlertDialogContent, AlertDialogDescription, AlertDialogFooter, AlertDialogHeader, AlertDialogTitle } from '@/components/ui/alert-dialog';
import { toast } from 'sonner';

interface Community {
  id: string;
  name: string;
  company_id: string;
}

interface Site {
  id: string;
  community_id: string;
  name: string;
  site_id: string;
  camera_ids: string[];
  is_active: boolean;
  created_at: string;
  communities?: Community | Community[];
}

export default function SitesPage() {
  const { user, profile, loading, effectiveRole } = useAuth();
  const { activeCompanyId, activeRole, effectiveRole: contextEffectiveRole } = useCompany();
  const router = useRouter();
  const [sites, setSites] = useState<Site[]>([]);
  const [communities, setCommunities] = useState<Community[]>([]);
  const [loadingSites, setLoadingSites] = useState(true);
  const [isDialogOpen, setIsDialogOpen] = useState(false);
  const [editingSite, setEditingSite] = useState<Site | null>(null);
  const [deleteDialogOpen, setDeleteDialogOpen] = useState(false);
  const [siteToDelete, setSiteToDelete] = useState<Site | null>(null);
  const [deleteConfirmation, setDeleteConfirmation] = useState('');
  const [copiedId, setCopiedId] = useState<string | null>(null);
  const [formData, setFormData] = useState({
    community_id: '',
    name: '',
    site_id: '',
    camera_ids: '',
    is_active: true,
  });

  useEffect(() => {
    if (!loading && !user) {
      router.push('/login');
    }
  }, [user, loading, router]);

  useEffect(() => {
    if (!loading && profile && activeCompanyId) {
      if (effectiveRole === 'resident' || effectiveRole === 'viewer') {
        router.push('/dashboard');
      } else {
        fetchCommunities();
        fetchSites();
      }
    }
  }, [loading, profile, activeCompanyId, effectiveRole, router]);

  const fetchCommunities = async () => {
    if (!activeCompanyId) return;
    const { data } = await supabase
      .from('communities')
      .select('id, name, company_id')
      .eq('company_id', activeCompanyId)
      .order('name');
    if (data) {
      setCommunities(data);
    }
  };

  const fetchSites = async () => {
    if (!activeCompanyId) return;
    setLoadingSites(true);
    const { data } = await supabase
      .from('sites')
      .select(`
        *,
        communities!inner (
          id,
          name,
          company_id
        )
      `)
      .eq('communities.company_id', activeCompanyId)
      .order('created_at', { ascending: false });

    if (data) {
      setSites(data);
    }
    setLoadingSites(false);
  };

  const handleSubmit = async (e: React.FormEvent) => {
    e.preventDefault();

    if (!formData.community_id) {
      toast.error('Please select a community');
      return;
    }

    const cameraIds = formData.camera_ids
      .split(',')
      .map(id => id.trim())
      .filter(id => id.length > 0);

    if (editingSite) {
      const { error } = await supabase
        .from('sites')
        .update({
          name: formData.name,
          site_id: formData.site_id,
          camera_ids: cameraIds,
          is_active: formData.is_active,
          updated_at: new Date().toISOString(),
        })
        .eq('id', editingSite.id);

      if (error) {
        toast.error('Failed to update site');
        return;
      }
      toast.success('Site updated successfully');
    } else {
      const { error } = await supabase
        .from('sites')
        .insert({
          community_id: formData.community_id,
          name: formData.name,
          site_id: formData.site_id,
          camera_ids: cameraIds,
          is_active: formData.is_active,
        });

      if (error) {
        toast.error('Failed to create site');
        return;
      }
      toast.success('Site created successfully');
    }

    setIsDialogOpen(false);
    resetForm();
    fetchSites();
  };

  const handleEdit = (site: Site) => {
    setEditingSite(site);
    setFormData({
      community_id: site.community_id,
      name: site.name,
      site_id: site.site_id,
      camera_ids: site.camera_ids.join(', '),
      is_active: site.is_active,
    });
    setIsDialogOpen(true);
  };

  const resetForm = () => {
    setEditingSite(null);
    setFormData({
      community_id: communities.length > 0 ? communities[0].id : '',
      name: '',
      site_id: '',
      camera_ids: '',
      is_active: true,
    });
  };

  const openDeleteDialog = (site: Site, e: React.MouseEvent) => {
    e.stopPropagation();
    setSiteToDelete(site);
    setDeleteDialogOpen(true);
  };

  const handleDelete = async () => {
    if (!siteToDelete || deleteConfirmation !== 'DELETE') {
      toast.error('Please type DELETE to confirm');
      return;
    }

    const { error } = await supabase
      .from('sites')
      .delete()
      .eq('id', siteToDelete.id);

    if (error) {
      toast.error('Failed to delete site');
      return;
    }

    toast.success('Site deleted successfully');
    setDeleteDialogOpen(false);
    setSiteToDelete(null);
    setDeleteConfirmation('');
    fetchSites();
  };

  const copyToClipboard = (text: string, id: string) => {
    navigator.clipboard.writeText(text);
    setCopiedId(id);
    toast.success('Copied to clipboard');
    setTimeout(() => setCopiedId(null), 2000);
  };

  if (loading || !user || !profile) {
    return (
      <div className="min-h-screen flex items-center justify-center bg-white dark:bg-[#1E293B]">
        <div className="text-lg">Loading...</div>
      </div>
    );
  }

  return (
    <DashboardLayout>
      <div className="max-w-6xl mx-auto">
        <div className="flex items-center justify-between mb-8">
          <div>
            <h2 className="text-3xl font-bold mb-2">Sites (Pods)</h2>
            <p className="text-muted-foreground">Manage pods and gates within your communities (up to 100 per community)</p>
          </div>
          {(effectiveRole === 'owner' || effectiveRole === 'admin' || effectiveRole === 'manager') && (
            <Dialog open={isDialogOpen} onOpenChange={(open) => {
              setIsDialogOpen(open);
              if (!open) resetForm();
            }}>
              <DialogTrigger asChild>
                <Button className="rounded-xl bg-[#0A84FF] hover:bg-[#0869CC] font-semibold shadow-lg shadow-blue-500/30">
                  <Plus className="w-4 h-4 mr-2" />
                  Add Site
                </Button>
              </DialogTrigger>
            <DialogContent className="sm:max-w-md">
              <DialogHeader>
                <DialogTitle>{editingSite ? 'Edit' : 'Add'} Site</DialogTitle>
              </DialogHeader>
              <form onSubmit={handleSubmit} className="space-y-4">
                <div className="space-y-2">
                  <Label htmlFor="community">Community</Label>
                  <Select
                    value={formData.community_id}
                    onValueChange={(value) => setFormData({ ...formData, community_id: value })}
                    disabled={editingSite !== null}
                  >
                    <SelectTrigger>
                      <SelectValue placeholder="Select a community" />
                    </SelectTrigger>
                    <SelectContent>
                      {communities.map((community) => (
                        <SelectItem key={community.id} value={community.id}>
                          {community.name}
                        </SelectItem>
                      ))}
                    </SelectContent>
                  </Select>
                </div>

                <div>
                  <Label>Pod/Gate Name</Label>
                  <Input
                    value={formData.name}
                    onChange={(e) => setFormData({ ...formData, name: e.target.value })}
                    placeholder="North Gate"
                    required
                  />
                </div>

                <div>
                  <Label>Site ID (for edge pods)</Label>
                  <Input
                    value={formData.site_id}
                    onChange={(e) => setFormData({ ...formData, site_id: e.target.value })}
                    placeholder="site-001"
                    required
                  />
                </div>

                <div>
                  <Label>Camera IDs (comma-separated)</Label>
                  <Input
                    value={formData.camera_ids}
                    onChange={(e) => setFormData({ ...formData, camera_ids: e.target.value })}
                    placeholder="cam-1, cam-2"
                  />
                </div>

                <div className="flex gap-3">
                  <Button
                    type="button"
                    variant="outline"
                    onClick={() => setIsDialogOpen(false)}
                    className="flex-1"
                  >
                    Cancel
                  </Button>
                  <Button type="submit" className="flex-1 rounded-xl bg-[#0A84FF] hover:bg-[#0869CC]">
                    {editingSite ? 'Update' : 'Add'} Site
                  </Button>
                </div>

                {editingSite && (effectiveRole === 'owner' || effectiveRole === 'admin') && (
                  <Button
                    type="button"
                    variant="destructive"
                    onClick={(e) => {
                      e.preventDefault();
                      setIsDialogOpen(false);
                      openDeleteDialog(editingSite, e);
                    }}
                    className="w-full"
                  >
                    <Trash2 className="w-4 h-4 mr-2" />
                    Delete Site
                  </Button>
                )}
              </form>
            </DialogContent>
          </Dialog>
          )}
        </div>

        <div className="grid gap-6 md:grid-cols-2 lg:grid-cols-3">
          {loadingSites ? (
            <div className="col-span-full text-center py-8">Loading sites...</div>
          ) : sites.length === 0 ? (
            <div className="col-span-full text-center py-8 text-muted-foreground">
              No sites yet. Add your first site location.
            </div>
          ) : (
            sites.map((site) => {
              const community = Array.isArray(site.communities) ? site.communities[0] : site.communities;
              return (
                <Card key={site.id} className="p-6 shadow-lg border-0 bg-white dark:bg-[#2D3748] hover:shadow-xl transition-shadow">
                  <div className="flex items-start justify-between mb-4">
                    <div className="p-3 rounded-2xl bg-blue-50 dark:bg-blue-900/20">
                      <Building2 className="w-6 h-6 text-blue-600 dark:text-blue-400" />
                    </div>
                    <div className="flex gap-2">
                      <Button
                        variant="outline"
                        size="sm"
                        onClick={() => handleEdit(site)}
                        className="rounded-lg"
                      >
                        <Pencil className="w-4 h-4" />
                      </Button>
                    </div>
                  </div>
                  <div className={`inline-block px-2 py-1 rounded-full text-xs font-medium mb-2 ${
                    site.is_active
                      ? 'bg-green-100 dark:bg-green-900/20 text-green-700 dark:text-green-400'
                      : 'bg-gray-100 dark:bg-gray-800 text-gray-700 dark:text-gray-400'
                  }`}>
                    {site.is_active ? 'Active' : 'Inactive'}
                  </div>
                  <h3 className="font-bold text-lg mb-1">{site.name}</h3>
                  {community && (
                    <p className="text-sm text-muted-foreground mb-2">{community.name}</p>
                  )}
                  {site.camera_ids.length > 0 && (
                    <p className="text-xs text-muted-foreground mb-2">
                      Cameras: {site.camera_ids.join(', ')}
                    </p>
                  )}
                  <p className="text-xs text-muted-foreground mb-4">
                    Added {new Date(site.created_at).toLocaleDateString()}
                  </p>

                  <div className="border-t pt-4 space-y-2">
                    <div className="flex items-center justify-between bg-blue-50 dark:bg-blue-900/10 p-3 rounded-lg">
                      <div className="flex-1 min-w-0">
                        <p className="text-xs font-medium text-blue-900 dark:text-blue-300 mb-1">Site ID (for POD setup)</p>
                        <p className="text-sm font-mono text-blue-700 dark:text-blue-400 truncate">{site.id}</p>
                      </div>
                      <Button
                        variant="ghost"
                        size="sm"
                        onClick={() => copyToClipboard(site.id, site.id)}
                        className="ml-2 shrink-0"
                      >
                        {copiedId === site.id ? (
                          <Check className="w-4 h-4 text-green-600" />
                        ) : (
                          <Copy className="w-4 h-4 text-blue-600" />
                        )}
                      </Button>
                    </div>
                  </div>
                </Card>
              );
            })
          )}
        </div>

        <AlertDialog open={deleteDialogOpen} onOpenChange={setDeleteDialogOpen}>
          <AlertDialogContent>
            <AlertDialogHeader>
              <AlertDialogTitle>Delete Site</AlertDialogTitle>
              <AlertDialogDescription>
                This will permanently delete <strong>{siteToDelete?.name}</strong> and all associated data.
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
                Delete Site
              </Button>
            </AlertDialogFooter>
          </AlertDialogContent>
        </AlertDialog>
      </div>
    </DashboardLayout>
  );
}
