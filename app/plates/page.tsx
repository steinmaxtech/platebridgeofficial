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
import { supabase } from '@/lib/supabase';
import { Plus, Pencil, Trash2 } from 'lucide-react';
import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from '@/components/ui/select';
import { Checkbox } from '@/components/ui/checkbox';
import { toast } from 'sonner';

interface Community {
  id: string;
  name: string;
}

interface Site {
  id: string;
  name: string;
  site_id: string;
  community_id: string;
}

interface PlateEntry {
  id: string;
  plate: string;
  community_id: string;
  site_ids: string[];
  unit: string | null;
  tenant: string | null;
  vehicle: string | null;
  notes: string | null;
  enabled: boolean;
  created_at: string;
  communities?: Community | Community[];
}

export default function PlatesPage() {
  const { user, profile, loading, effectiveRole } = useAuth();
  const { activeCompanyId } = useCompany();
  const router = useRouter();
  const [entries, setEntries] = useState<PlateEntry[]>([]);
  const [loadingEntries, setLoadingEntries] = useState(true);
  const [isDialogOpen, setIsDialogOpen] = useState(false);
  const [editingEntry, setEditingEntry] = useState<PlateEntry | null>(null);
  const [communities, setCommunities] = useState<Community[]>([]);
  const [sites, setSites] = useState<Site[]>([]);
  const [selectedCommunity, setSelectedCommunity] = useState<string>('');
  const [filterCommunity, setFilterCommunity] = useState<string>('all');
  const [formData, setFormData] = useState({
    community_id: '',
    plate: '',
    unit: '',
    tenant: '',
    vehicle: '',
    notes: '',
    enabled: true,
    site_ids: [] as string[],
  });

  useEffect(() => {
    if (!loading && !user) {
      router.push('/login');
    }
  }, [user, loading, router]);

  useEffect(() => {
    if (user && profile && activeCompanyId) {
      fetchCommunities();
      fetchEntries();
    }
  }, [user, profile, activeCompanyId]);

  useEffect(() => {
    if (activeCompanyId) {
      fetchEntries();
    }
  }, [filterCommunity]);

  useEffect(() => {
    if (selectedCommunity || formData.community_id) {
      fetchSites(formData.community_id || selectedCommunity);
    }
  }, [selectedCommunity, formData.community_id]);

  const fetchCommunities = async () => {
    if (!activeCompanyId) return;
    const { data } = await supabase
      .from('communities')
      .select('id, name')
      .eq('company_id', activeCompanyId)
      .order('name');
    if (data) {
      setCommunities(data);
    }
  };

  const fetchSites = async (communityId: string) => {
    if (!communityId) {
      setSites([]);
      return;
    }
    const { data } = await supabase
      .from('sites')
      .select('id, name, site_id, community_id')
      .eq('community_id', communityId)
      .order('name');
    if (data) {
      setSites(data);
    }
  };

  const fetchEntries = async () => {
    if (!activeCompanyId) return;
    setLoadingEntries(true);

    let query = supabase
      .from('plates')
      .select(`
        *,
        communities!inner (
          id,
          name,
          company_id
        )
      `)
      .eq('communities.company_id', activeCompanyId);

    if (filterCommunity !== 'all') {
      query = query.eq('community_id', filterCommunity);
    }

    if (effectiveRole === 'resident' && user?.email) {
      query = query.eq('tenant', user.email);
    }

    const { data } = await query.order('created_at', { ascending: false });

    if (data) {
      setEntries(data);
    }
    setLoadingEntries(false);
  };

  const handleSubmit = async (e: React.FormEvent) => {
    e.preventDefault();

    if (!formData.community_id) {
      toast.error('Please select a community');
      return;
    }

    const submitData = {
      community_id: formData.community_id,
      plate: formData.plate.toUpperCase(),
      unit: formData.unit || null,
      tenant: formData.tenant || null,
      vehicle: formData.vehicle || null,
      notes: formData.notes || null,
      enabled: formData.enabled,
      site_ids: formData.site_ids,
    };

    if (editingEntry) {
      const { error } = await supabase
        .from('plates')
        .update(submitData)
        .eq('id', editingEntry.id);

      if (error) {
        toast.error('Failed to update entry');
        return;
      }
      toast.success('Entry updated successfully');
    } else {
      const { error } = await supabase
        .from('plates')
        .insert(submitData);

      if (error) {
        toast.error('Failed to create entry');
        return;
      }
      toast.success('Entry created successfully');
    }

    setIsDialogOpen(false);
    resetForm();
    fetchEntries();
  };

  const handleEdit = (entry: PlateEntry) => {
    setEditingEntry(entry);
    setFormData({
      community_id: entry.community_id,
      plate: entry.plate,
      unit: entry.unit || '',
      tenant: entry.tenant || '',
      vehicle: entry.vehicle || '',
      notes: entry.notes || '',
      enabled: entry.enabled,
      site_ids: entry.site_ids || [],
    });
    setSelectedCommunity(entry.community_id);
    setIsDialogOpen(true);
  };

  const handleDelete = async (id: string) => {
    if (confirm('Are you sure you want to delete this entry?')) {
      const { error } = await supabase.from('plates').delete().eq('id', id);
      if (error) {
        toast.error('Failed to delete entry');
        return;
      }
      toast.success('Entry deleted successfully');
      fetchEntries();
    }
  };

  const resetForm = () => {
    setEditingEntry(null);
    setSelectedCommunity('');
    setFormData({
      community_id: '',
      plate: '',
      unit: '',
      tenant: '',
      vehicle: '',
      notes: '',
      enabled: true,
      site_ids: [],
    });
  };

  const toggleSiteSelection = (siteId: string) => {
    setFormData(prev => ({
      ...prev,
      site_ids: prev.site_ids.includes(siteId)
        ? prev.site_ids.filter(id => id !== siteId)
        : [...prev.site_ids, siteId]
    }));
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
        <div className="flex items-center justify-between mb-6">
          <div>
            <h2 className="text-3xl font-bold mb-2">
              {effectiveRole === 'resident' ? 'My Vehicles' : 'License Plates'}
            </h2>
            <p className="text-muted-foreground">
              {effectiveRole === 'resident'
                ? 'View your registered vehicles'
                : 'Manage license plates for community access'}
            </p>
          </div>
          {effectiveRole !== 'resident' && effectiveRole !== 'viewer' && (
            <Dialog open={isDialogOpen} onOpenChange={(open) => {
              setIsDialogOpen(open);
              if (!open) resetForm();
            }}>
              <DialogTrigger asChild>
                <Button className="rounded-xl bg-[#0A84FF] hover:bg-[#0869CC] font-semibold shadow-lg shadow-blue-500/30">
                  <Plus className="w-4 h-4 mr-2" />
                  Add Plate
                </Button>
              </DialogTrigger>
            <DialogContent className="sm:max-w-lg max-h-[90vh] overflow-y-auto">
              <DialogHeader>
                <DialogTitle>{editingEntry ? 'Edit' : 'Add'} License Plate</DialogTitle>
              </DialogHeader>
              <form onSubmit={handleSubmit} className="space-y-4">
                <div>
                  <Label>Community</Label>
                  <Select
                    value={formData.community_id}
                    onValueChange={(value) => {
                      setFormData({ ...formData, community_id: value, site_ids: [] });
                      setSelectedCommunity(value);
                    }}
                    disabled={editingEntry !== null}
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
                  <Label>License Plate</Label>
                  <Input
                    value={formData.plate}
                    onChange={(e) => setFormData({ ...formData, plate: e.target.value })}
                    placeholder="ABC1234"
                    required
                    className="uppercase"
                  />
                </div>

                <div>
                  <Label>Unit/Apartment</Label>
                  <Input
                    value={formData.unit}
                    onChange={(e) => setFormData({ ...formData, unit: e.target.value })}
                    placeholder="101"
                  />
                </div>

                <div>
                  <Label>Tenant Name</Label>
                  <Input
                    value={formData.tenant}
                    onChange={(e) => setFormData({ ...formData, tenant: e.target.value })}
                    placeholder="John Doe"
                  />
                </div>

                <div>
                  <Label>Vehicle Description</Label>
                  <Input
                    value={formData.vehicle}
                    onChange={(e) => setFormData({ ...formData, vehicle: e.target.value })}
                    placeholder="Red Honda Civic"
                  />
                </div>

                {formData.community_id && sites.length > 0 && (
                  <div>
                    <Label>Assign to Sites/Pods (optional)</Label>
                    <div className="border rounded-lg p-3 max-h-48 overflow-y-auto space-y-2 mt-2">
                      {sites.map((site) => (
                        <div key={site.id} className="flex items-center space-x-2">
                          <Checkbox
                            id={`site-${site.id}`}
                            checked={formData.site_ids.includes(site.id)}
                            onCheckedChange={() => toggleSiteSelection(site.id)}
                          />
                          <label
                            htmlFor={`site-${site.id}`}
                            className="text-sm cursor-pointer flex-1"
                          >
                            {site.name} ({site.site_id})
                          </label>
                        </div>
                      ))}
                    </div>
                  </div>
                )}

                <div>
                  <Label>Notes</Label>
                  <Input
                    value={formData.notes}
                    onChange={(e) => setFormData({ ...formData, notes: e.target.value })}
                    placeholder="Additional notes..."
                  />
                </div>

                <Button type="submit" className="w-full rounded-xl bg-[#0A84FF] hover:bg-[#0869CC]">
                  {editingEntry ? 'Update' : 'Add'} Plate
                </Button>
              </form>
            </DialogContent>
          </Dialog>
          )}
        </div>

        {effectiveRole !== 'resident' && (
          <div className="mb-6">
            <Label>Filter by Community</Label>
            <Select value={filterCommunity} onValueChange={(value) => {
              setFilterCommunity(value);
            }}>
              <SelectTrigger className="w-64">
                <SelectValue />
              </SelectTrigger>
              <SelectContent>
                <SelectItem value="all">All Communities</SelectItem>
                {communities.map((community) => (
                  <SelectItem key={community.id} value={community.id}>
                    {community.name}
                  </SelectItem>
                ))}
              </SelectContent>
            </Select>
          </div>
        )}

        <Card className="p-6 shadow-lg border-0 bg-white dark:bg-[#2D3748]">
          {loadingEntries ? (
            <div className="text-center py-8">Loading entries...</div>
          ) : entries.length === 0 ? (
            <div className="text-center py-8 text-muted-foreground">
              No license plate entries yet. Add your first plate.
            </div>
          ) : (
            <Table>
              <TableHeader>
                <TableRow>
                  <TableHead>License Plate</TableHead>
                  <TableHead>Community</TableHead>
                  <TableHead>Unit</TableHead>
                  <TableHead>Tenant</TableHead>
                  <TableHead>Sites</TableHead>
                  <TableHead>Status</TableHead>
                  <TableHead className="text-right">Actions</TableHead>
                </TableRow>
              </TableHeader>
              <TableBody>
                {entries.map((entry) => {
                  const community = Array.isArray(entry.communities) ? entry.communities[0] : entry.communities;
                  return (
                    <TableRow key={entry.id}>
                      <TableCell className="font-mono font-semibold">{entry.plate}</TableCell>
                      <TableCell>{community?.name || '—'}</TableCell>
                      <TableCell>{entry.unit || '—'}</TableCell>
                      <TableCell>{entry.tenant || '—'}</TableCell>
                      <TableCell className="text-sm">
                        {entry.site_ids && entry.site_ids.length > 0
                          ? `${entry.site_ids.length} site${entry.site_ids.length > 1 ? 's' : ''}`
                          : 'All sites'}
                      </TableCell>
                      <TableCell>
                        <span className={`inline-block px-2 py-1 rounded-full text-xs font-medium ${
                          entry.enabled
                            ? 'bg-green-100 dark:bg-green-900/20 text-green-700 dark:text-green-400'
                            : 'bg-gray-100 dark:bg-gray-800 text-gray-700 dark:text-gray-400'
                        }`}>
                          {entry.enabled ? 'Active' : 'Inactive'}
                        </span>
                      </TableCell>
                      <TableCell className="text-right">
                        {effectiveRole !== 'resident' && effectiveRole !== 'viewer' && (
                          <div className="flex gap-2 justify-end">
                            <Button
                              variant="outline"
                              size="sm"
                              onClick={() => handleEdit(entry)}
                              className="rounded-lg"
                            >
                              <Pencil className="w-4 h-4" />
                            </Button>
                            <Button
                              variant="outline"
                              size="sm"
                              onClick={() => handleDelete(entry.id)}
                              className="rounded-lg text-red-600 hover:text-red-700"
                            >
                              <Trash2 className="w-4 h-4" />
                            </Button>
                          </div>
                        )}
                      </TableCell>
                    </TableRow>
                  );
                })}
              </TableBody>
            </Table>
          )}
        </Card>
      </div>
    </DashboardLayout>
  );
}
