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
import { AlertDialog, AlertDialogAction, AlertDialogCancel, AlertDialogContent, AlertDialogDescription, AlertDialogFooter, AlertDialogHeader, AlertDialogTitle } from '@/components/ui/alert-dialog';
import { Switch } from '@/components/ui/switch';
import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from '@/components/ui/select';
import { Home, Plus, MapPin, Trash2, Key, Copy, Check, RefreshCw } from 'lucide-react';
import { supabase } from '@/lib/supabase';
import { toast } from 'sonner';

interface Community {
  id: string;
  company_id: string;
  name: string;
  timezone: string;
  address: string;
  is_active: boolean;
  created_at: string;
}

interface Company {
  id: string;
  name: string;
  is_active: boolean;
}

export default function CommunitiesPage() {
  const { user, profile, loading: authLoading } = useAuth();
  const { activeCompanyId, activeRole, effectiveRole, memberships } = useCompany();
  const router = useRouter();
  const [communities, setCommunities] = useState<Community[]>([]);
  const [loading, setLoading] = useState(true);
  const [isDialogOpen, setIsDialogOpen] = useState(false);
  const [editingCommunity, setEditingCommunity] = useState<Community | null>(null);
  const [availableCompanies, setAvailableCompanies] = useState<Company[]>([]);
  const [deleteDialogOpen, setDeleteDialogOpen] = useState(false);
  const [communityToDelete, setCommunityToDelete] = useState<Community | null>(null);
  const [deleteConfirmation, setDeleteConfirmation] = useState('');
  const [tokenDialogOpen, setTokenDialogOpen] = useState(false);
  const [selectedCommunityForToken, setSelectedCommunityForToken] = useState<Community | null>(null);
  const [generatedToken, setGeneratedToken] = useState<string | null>(null);
  const [generatingToken, setGeneratingToken] = useState(false);
  const [copiedId, setCopiedId] = useState<string | null>(null);
  const [formData, setFormData] = useState({
    company_id: '',
    name: '',
    timezone: 'America/New_York',
    address: '',
    is_active: true,
  });

  useEffect(() => {
    if (!authLoading && !user) {
      router.push('/login');
    }
  }, [user, authLoading, router]);

  const fetchCompanies = async () => {
    const companies: Company[] = [];
    for (const membership of memberships) {
      const company = Array.isArray(membership.companies)
        ? membership.companies[0]
        : membership.companies;
      if (company) {
        companies.push(company);
      }
    }
    setAvailableCompanies(companies);
  };

  const fetchCommunities = async () => {
    if (!activeCompanyId) {
      setCommunities([]);
      setLoading(false);
      return;
    }

    setLoading(true);
    const { data, error } = await supabase
      .from('communities')
      .select('*')
      .eq('company_id', activeCompanyId)
      .order('name');

    if (!error && data) {
      setCommunities(data);
    }
    setLoading(false);
  };

  useEffect(() => {
    if (memberships.length > 0) {
      fetchCompanies();
    }
  }, [memberships]);

  useEffect(() => {
    if (activeCompanyId) {
      fetchCommunities();
    } else {
      setLoading(false);
    }
  }, [activeCompanyId]);

  const handleSubmit = async (e: React.FormEvent) => {
    e.preventDefault();

    if (!formData.company_id) {
      toast.error('Please select a company');
      return;
    }

    if (editingCommunity) {
      const { error } = await supabase
        .from('communities')
        .update({
          name: formData.name,
          timezone: formData.timezone,
          address: formData.address,
          is_active: formData.is_active,
          updated_at: new Date().toISOString(),
        })
        .eq('id', editingCommunity.id);

      if (error) {
        toast.error('Failed to update community');
        return;
      }
      toast.success('Community updated successfully');
    } else {
      const { error } = await supabase
        .from('communities')
        .insert({
          company_id: formData.company_id,
          name: formData.name,
          timezone: formData.timezone,
          address: formData.address,
          is_active: formData.is_active,
        });

      if (error) {
        toast.error('Failed to create community');
        return;
      }
      toast.success('Community created successfully');
    }

    setIsDialogOpen(false);
    setEditingCommunity(null);
    setFormData({ company_id: '', name: '', timezone: 'America/New_York', address: '', is_active: true });
    fetchCommunities();
  };

  const openEditDialog = (community: Community) => {
    setEditingCommunity(community);
    setFormData({
      company_id: community.company_id,
      name: community.name,
      timezone: community.timezone,
      address: community.address,
      is_active: community.is_active,
    });
    setIsDialogOpen(true);
  };

  const openCreateDialog = () => {
    setEditingCommunity(null);
    setFormData({
      company_id: activeCompanyId || '',
      name: '',
      timezone: 'America/New_York',
      address: '',
      is_active: true
    });
    setIsDialogOpen(true);
  };

  const openDeleteDialog = (community: Community, e: React.MouseEvent) => {
    e.stopPropagation();
    setCommunityToDelete(community);
    setDeleteDialogOpen(true);
  };

  const handleDelete = async () => {
    if (!communityToDelete || deleteConfirmation !== 'DELETE') {
      toast.error('Please type DELETE to confirm');
      return;
    }

    const { error } = await supabase
      .from('communities')
      .delete()
      .eq('id', communityToDelete.id);

    if (error) {
      toast.error('Failed to delete community');
      return;
    }

    toast.success('Community deleted successfully');
    setDeleteDialogOpen(false);
    setCommunityToDelete(null);
    setDeleteConfirmation('');
    fetchCommunities();
  };

  const copyToClipboard = (text: string, id: string) => {
    navigator.clipboard.writeText(text);
    setCopiedId(id);
    toast.success('Copied to clipboard');
    setTimeout(() => setCopiedId(null), 2000);
  };

  const generateRegistrationToken = async (community: Community, e: React.MouseEvent) => {
    e.stopPropagation();
    setSelectedCommunityForToken(community);
    setGeneratedToken(null);
    setTokenDialogOpen(true);
    setGeneratingToken(true);

    try {
      const { data: { session } } = await supabase.auth.getSession();
      if (!session) {
        throw new Error('No active session');
      }

      const response = await fetch('/api/pods/registration-tokens', {
        method: 'POST',
        headers: {
          'Content-Type': 'application/json',
          'Authorization': `Bearer ${session.access_token}`,
        },
        body: JSON.stringify({
          community_id: community.id,
          expires_in_hours: 24,
          max_uses: 1,
          notes: `Token for ${community.name}`,
        }),
      });

      if (!response.ok) {
        const errorData = await response.json();
        throw new Error(errorData.details || errorData.error || 'Failed to generate token');
      }

      const data = await response.json();
      setGeneratedToken(data.token.token);
      toast.success('Registration token generated!');
    } catch (error) {
      console.error('Error generating token:', error);
      toast.error(error instanceof Error ? error.message : 'Failed to generate token');
      setTokenDialogOpen(false);
    } finally {
      setGeneratingToken(false);
    }
  };

  if (authLoading || loading || !user || !profile) {
    return (
      <div className="min-h-screen flex items-center justify-center bg-white dark:bg-[#1E293B]">
        <div className="text-lg">Loading...</div>
      </div>
    );
  }

  if (memberships.length === 0) {
    return (
      <DashboardLayout>
        <Card className="p-12 text-center max-w-2xl mx-auto">
          <Home className="w-16 h-16 mx-auto mb-4 text-muted-foreground" />
          <h3 className="text-xl font-semibold mb-2">No company membership</h3>
          <p className="text-muted-foreground">
            Please create or join a company first to manage communities
          </p>
          <Button onClick={() => router.push('/companies')} className="mt-6 rounded-xl bg-[#0A84FF] hover:bg-[#0869CC]">
            Go to Companies
          </Button>
        </Card>
      </DashboardLayout>
    );
  }

  const canManage = effectiveRole === 'owner' || effectiveRole === 'admin' || effectiveRole === 'manager';

  return (
    <DashboardLayout>
      <div className="max-w-6xl mx-auto">
        <div className="flex items-center justify-between mb-8">
          <div>
            <h2 className="text-3xl font-bold mb-2">Communities</h2>
            <p className="text-muted-foreground">
              Manage communities where gates and pods are located
            </p>
          </div>
          {canManage && (
            <Dialog open={isDialogOpen} onOpenChange={setIsDialogOpen}>
              <DialogTrigger asChild>
                <Button onClick={openCreateDialog} className="rounded-xl bg-[#0A84FF] hover:bg-[#0869CC]">
                  <Plus className="w-4 h-4 mr-2" />
                  New Community
                </Button>
              </DialogTrigger>
              <DialogContent className="sm:max-w-[500px]">
                <DialogHeader>
                  <DialogTitle>
                    {editingCommunity ? 'Edit Community' : 'Create New Community'}
                  </DialogTitle>
                </DialogHeader>
                <form onSubmit={handleSubmit} className="space-y-4 mt-4">
                  <div className="space-y-2">
                    <Label htmlFor="company">Company</Label>
                    <Select
                      value={formData.company_id}
                      onValueChange={(value) => setFormData({ ...formData, company_id: value })}
                      disabled={editingCommunity !== null}
                    >
                      <SelectTrigger>
                        <SelectValue placeholder="Select a company" />
                      </SelectTrigger>
                      <SelectContent>
                        {availableCompanies.map((company) => (
                          <SelectItem key={company.id} value={company.id}>
                            {company.name}
                          </SelectItem>
                        ))}
                      </SelectContent>
                    </Select>
                  </div>

                  <div className="space-y-2">
                    <Label htmlFor="name">Community Name</Label>
                    <Input
                      id="name"
                      value={formData.name}
                      onChange={(e) => setFormData({ ...formData, name: e.target.value })}
                      required
                      placeholder="Sunset Hills Apartments"
                    />
                  </div>

                  <div className="space-y-2">
                    <Label htmlFor="address">Address</Label>
                    <Input
                      id="address"
                      value={formData.address}
                      onChange={(e) => setFormData({ ...formData, address: e.target.value })}
                      placeholder="123 Main Street, City, State"
                    />
                  </div>

                  <div className="space-y-2">
                    <Label htmlFor="timezone">Timezone</Label>
                    <select
                      id="timezone"
                      value={formData.timezone}
                      onChange={(e) => setFormData({ ...formData, timezone: e.target.value })}
                      className="w-full h-10 rounded-xl border-2 px-3 bg-white dark:bg-[#2D3748]"
                    >
                      <option value="America/New_York">Eastern Time</option>
                      <option value="America/Chicago">Central Time</option>
                      <option value="America/Denver">Mountain Time</option>
                      <option value="America/Los_Angeles">Pacific Time</option>
                      <option value="America/Phoenix">Arizona Time</option>
                      <option value="America/Anchorage">Alaska Time</option>
                      <option value="Pacific/Honolulu">Hawaii Time</option>
                    </select>
                  </div>

                  <div className="flex items-center justify-between">
                    <Label htmlFor="is_active">Active</Label>
                    <Switch
                      id="is_active"
                      checked={formData.is_active}
                      onCheckedChange={(checked) => setFormData({ ...formData, is_active: checked })}
                    />
                  </div>

                  <div className="flex gap-3 pt-4">
                    <Button
                      type="button"
                      variant="outline"
                      onClick={() => setIsDialogOpen(false)}
                      className="flex-1"
                    >
                      Cancel
                    </Button>
                    <Button type="submit" className="flex-1 bg-[#0A84FF] hover:bg-[#0869CC]">
                      {editingCommunity ? 'Update' : 'Create'}
                    </Button>
                  </div>
                  {editingCommunity && canManage && (
                    <Button
                      type="button"
                      variant="destructive"
                      onClick={(e) => {
                        e.preventDefault();
                        setIsDialogOpen(false);
                        openDeleteDialog(editingCommunity, e);
                      }}
                      className="w-full"
                    >
                      <Trash2 className="w-4 h-4 mr-2" />
                      Delete Community
                    </Button>
                  )}
                </form>
              </DialogContent>
            </Dialog>
          )}
        </div>

        {communities.length === 0 ? (
          <Card className="p-12 text-center">
            <Home className="w-16 h-16 mx-auto mb-4 text-muted-foreground" />
            <h3 className="text-xl font-semibold mb-2">No communities yet</h3>
            <p className="text-muted-foreground mb-6">
              Create your first community to start managing gates and pods
            </p>
            {canManage && (
              <Button onClick={openCreateDialog} className="rounded-xl bg-[#0A84FF] hover:bg-[#0869CC]">
                <Plus className="w-4 h-4 mr-2" />
                Create Community
              </Button>
            )}
          </Card>
        ) : (
          <div className="grid gap-4 md:grid-cols-2 lg:grid-cols-3">
            {communities.map((community) => (
              <Card
                key={community.id}
                className="p-6 hover:shadow-lg transition-shadow cursor-pointer"
                onClick={() => canManage && openEditDialog(community)}
              >
                <div className="flex items-start justify-between mb-4">
                  <div className="p-3 rounded-2xl bg-green-50 dark:bg-green-900/20">
                    <Home className="w-6 h-6 text-green-600 dark:text-green-400" />
                  </div>
                  <div className={`px-3 py-1 rounded-full text-xs font-medium ${
                    community.is_active
                      ? 'bg-green-100 dark:bg-green-900/20 text-green-700 dark:text-green-400'
                      : 'bg-gray-100 dark:bg-gray-800 text-gray-700 dark:text-gray-400'
                  }`}>
                    {community.is_active ? 'Active' : 'Inactive'}
                  </div>
                </div>
                <h3 className="font-bold text-lg mb-2">{community.name}</h3>
                {community.address && (
                  <div className="flex items-start gap-2 text-sm text-muted-foreground mb-2">
                    <MapPin className="w-4 h-4 mt-0.5 flex-shrink-0" />
                    <span className="line-clamp-2">{community.address}</span>
                  </div>
                )}
                <div className="text-xs text-muted-foreground mb-4">
                  {community.timezone}
                </div>

                {canManage && (
                  <div className="flex gap-2 mt-4">
                    <Button
                      onClick={(e) => {
                        e.stopPropagation();
                        router.push(`/communities/${community.id}/tokens`);
                      }}
                      className="flex-1 rounded-lg"
                      variant="outline"
                      size="sm"
                    >
                      <Key className="w-4 h-4 mr-2" />
                      Manage Tokens
                    </Button>
                    <Button
                      onClick={(e) => generateRegistrationToken(community, e)}
                      className="flex-1 rounded-lg bg-green-600 hover:bg-green-700 text-white"
                      size="sm"
                    >
                      <Plus className="w-4 h-4 mr-2" />
                      Quick Token
                    </Button>
                  </div>
                )}
              </Card>
            ))}
          </div>
        )}

        <AlertDialog open={deleteDialogOpen} onOpenChange={setDeleteDialogOpen}>
          <AlertDialogContent>
            <AlertDialogHeader>
              <AlertDialogTitle>Delete Community</AlertDialogTitle>
              <AlertDialogDescription>
                This will permanently delete <strong>{communityToDelete?.name}</strong> and all associated data.
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
                Delete Community
              </Button>
            </AlertDialogFooter>
          </AlertDialogContent>
        </AlertDialog>

        <Dialog open={tokenDialogOpen} onOpenChange={setTokenDialogOpen}>
          <DialogContent className="sm:max-w-2xl">
            <DialogHeader>
              <DialogTitle>POD Registration Token</DialogTitle>
            </DialogHeader>
            {generatingToken ? (
              <div className="flex items-center justify-center py-8">
                <RefreshCw className="w-6 h-6 animate-spin text-blue-600" />
                <span className="ml-3">Generating token...</span>
              </div>
            ) : generatedToken ? (
              <div className="space-y-4">
                <div className="bg-green-50 dark:bg-green-900/20 border border-green-200 dark:border-green-800 rounded-lg p-4">
                  <div className="flex items-start gap-3">
                    <Key className="w-5 h-5 text-green-600 mt-0.5" />
                    <div className="flex-1">
                      <h4 className="font-semibold text-green-900 dark:text-green-100 mb-1">
                        Registration Token Generated
                      </h4>
                      <p className="text-sm text-green-700 dark:text-green-300">
                        Use this token during POD installation. It expires in 24 hours and can be used once.
                      </p>
                    </div>
                  </div>
                </div>

                <div className="space-y-2">
                  <Label>Token (copy this)</Label>
                  <div className="flex gap-2">
                    <Input
                      value={generatedToken}
                      readOnly
                      className="font-mono text-sm"
                    />
                    <Button
                      onClick={() => copyToClipboard(generatedToken, 'token')}
                      variant="outline"
                    >
                      {copiedId === 'token' ? (
                        <Check className="w-4 h-4 text-green-600" />
                      ) : (
                        <Copy className="w-4 h-4" />
                      )}
                    </Button>
                  </div>
                </div>

                <div className="bg-blue-50 dark:bg-blue-900/20 rounded-lg p-4 space-y-2">
                  <h4 className="font-semibold text-sm">Installation Instructions:</h4>
                  <ol className="text-sm space-y-1 list-decimal list-inside text-muted-foreground">
                    <li>SSH into your POD device</li>
                    <li>Run: <code className="bg-white dark:bg-gray-800 px-2 py-0.5 rounded">sudo ./install-complete.sh</code></li>
                    <li>Enter portal URL when prompted</li>
                    <li>Paste this registration token when prompted</li>
                    <li>POD will automatically register to this community</li>
                  </ol>
                </div>

                <div className="flex gap-2">
                  <Button
                    onClick={() => setTokenDialogOpen(false)}
                    className="flex-1"
                    variant="outline"
                  >
                    Close
                  </Button>
                  <Button
                    onClick={() => {
                      if (selectedCommunityForToken) {
                        generateRegistrationToken(selectedCommunityForToken, {} as React.MouseEvent);
                      }
                    }}
                    className="flex-1"
                  >
                    <RefreshCw className="w-4 h-4 mr-2" />
                    Generate New Token
                  </Button>
                </div>
              </div>
            ) : null}
          </DialogContent>
        </Dialog>
      </div>
    </DashboardLayout>
  );
}
