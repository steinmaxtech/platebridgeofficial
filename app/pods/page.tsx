'use client';

import { useState, useEffect } from 'react';
import { useRouter } from 'next/navigation';
import { DashboardLayout } from '@/components/dashboard-layout';
import { useAuth } from '@/lib/auth-context';
import { useCompany } from '@/lib/community-context';
import { Card, CardContent, CardDescription, CardHeader, CardTitle } from '@/components/ui/card';
import { Button } from '@/components/ui/button';
import { Input } from '@/components/ui/input';
import { Label } from '@/components/ui/label';
import { Badge } from '@/components/ui/badge';
import { Dialog, DialogContent, DialogDescription, DialogHeader, DialogTitle, DialogFooter } from '@/components/ui/dialog';
import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from '@/components/ui/select';
import { supabase } from '@/lib/supabase';
import { toast } from 'sonner';
import { Plus, Server, Activity, Clock, Copy, CheckCircle2, AlertCircle, Trash2 } from 'lucide-react';
import { formatDistanceToNow } from 'date-fns';

interface Pod {
  id: string;
  name: string;
  community_id: string;
  pod_id: string;
  created_at: string;
  last_used_at: string | null;
  revoked_at: string | null;
  community_name?: string;
}

interface Community {
  id: string;
  name: string;
  address: string;
}

export default function PodsPage() {
  const router = useRouter();
  const { user, profile, loading, effectiveRole } = useAuth();
  const { activeCompanyId } = useCompany();

  const [pods, setPods] = useState<Pod[]>([]);
  const [communities, setCommunities] = useState<Community[]>([]);
  const [loadingPods, setLoadingPods] = useState(true);
  const [showAddDialog, setShowAddDialog] = useState(false);
  const [showSetupDialog, setShowSetupDialog] = useState(false);
  const [selectedCommunityId, setSelectedCommunityId] = useState('');
  const [podName, setPodName] = useState('');
  const [podId, setPodId] = useState('');
  const [creating, setCreating] = useState(false);
  const [generatedApiKey, setGeneratedApiKey] = useState('');
  const [setupCommand, setSetupCommand] = useState('');
  const [copiedCommand, setCopiedCommand] = useState(false);

  useEffect(() => {
    if (!loading && !user) {
      router.push('/login');
    }
  }, [user, loading, router]);

  useEffect(() => {
    if (user && activeCompanyId) {
      fetchCommunities();
      fetchPods();
    }
  }, [user, activeCompanyId]);

  const fetchCommunities = async () => {
    try {
      const { data, error } = await supabase
        .from('communities')
        .select('id, name, address')
        .eq('company_id', activeCompanyId)
        .order('name');

      if (error) throw error;
      setCommunities(data || []);
    } catch (error: any) {
      console.error('Error fetching communities:', error);
      toast.error('Failed to load communities');
    }
  };

  const fetchPods = async () => {
    try {
      setLoadingPods(true);
      const { data, error } = await supabase
        .from('pod_api_keys')
        .select(`
          id,
          name,
          community_id,
          pod_id,
          created_at,
          last_used_at,
          revoked_at,
          communities(name)
        `)
        .order('created_at', { ascending: false });

      if (error) throw error;

      const podsWithCommunityNames = (data || []).map((pod: any) => ({
        ...pod,
        community_name: pod.communities?.name || 'Unknown Community',
      }));

      setPods(podsWithCommunityNames);
    } catch (error: any) {
      console.error('Error fetching pods:', error);
      toast.error('Failed to load PODs');
    } finally {
      setLoadingPods(false);
    }
  };

  const generateApiKey = () => {
    const prefix = 'pbk_';
    const randomBytes = new Uint8Array(32);
    crypto.getRandomValues(randomBytes);
    const key = Array.from(randomBytes, byte => byte.toString(16).padStart(2, '0')).join('');
    return prefix + key;
  };

  const hashApiKey = async (apiKey: string): Promise<string> => {
    const encoder = new TextEncoder();
    const data = encoder.encode(apiKey);
    const hashBuffer = await crypto.subtle.digest('SHA-256', data);
    const hashArray = Array.from(new Uint8Array(hashBuffer));
    const hashHex = hashArray.map(b => b.toString(16).padStart(2, '0')).join('');
    return hashHex;
  };

  const handleCreatePod = async () => {
    if (!selectedCommunityId || !podName || !podId) {
      toast.error('Please fill in all fields');
      return;
    }

    try {
      setCreating(true);

      const apiKey = generateApiKey();
      const keyHash = await hashApiKey(apiKey);

      const { error } = await supabase
        .from('pod_api_keys')
        .insert({
          name: podName,
          community_id: selectedCommunityId,
          pod_id: podId,
          key_hash: keyHash,
          created_by: user?.id,
        });

      if (error) throw error;

      setGeneratedApiKey(apiKey);

      const portalUrl = window.location.origin;
      const command = `curl -fsSL ${portalUrl}/install-pod.sh | bash -s -- "${apiKey}"`;
      setSetupCommand(command);

      setShowAddDialog(false);
      setShowSetupDialog(true);

      toast.success('POD created successfully!');
      fetchPods();

      setPodName('');
      setPodId('');
      setSelectedCommunityId('');
    } catch (error: any) {
      console.error('Error creating POD:', error);
      toast.error('Failed to create POD: ' + error.message);
    } finally {
      setCreating(false);
    }
  };

  const handleCopyCommand = () => {
    navigator.clipboard.writeText(setupCommand);
    setCopiedCommand(true);
    toast.success('Command copied to clipboard');
    setTimeout(() => setCopiedCommand(false), 2000);
  };

  const handleCopyApiKey = () => {
    navigator.clipboard.writeText(generatedApiKey);
    toast.success('API key copied to clipboard');
  };

  const handleRevokePod = async (podId: string) => {
    if (!confirm('Are you sure you want to revoke this POD? It will stop working immediately.')) {
      return;
    }

    try {
      const { error } = await supabase
        .from('pod_api_keys')
        .update({ revoked_at: new Date().toISOString() })
        .eq('id', podId);

      if (error) throw error;

      toast.success('POD revoked successfully');
      fetchPods();
    } catch (error: any) {
      console.error('Error revoking POD:', error);
      toast.error('Failed to revoke POD');
    }
  };

  const getPodStatus = (pod: Pod) => {
    if (pod.revoked_at) {
      return { label: 'Revoked', variant: 'destructive' as const, icon: AlertCircle };
    }

    if (!pod.last_used_at) {
      return { label: 'Never Connected', variant: 'secondary' as const, icon: Server };
    }

    const lastUsed = new Date(pod.last_used_at);
    const minutesAgo = (Date.now() - lastUsed.getTime()) / 1000 / 60;

    if (minutesAgo < 10) {
      return { label: 'Online', variant: 'default' as const, icon: Activity };
    } else if (minutesAgo < 60) {
      return { label: 'Recently Active', variant: 'secondary' as const, icon: Clock };
    } else {
      return { label: 'Offline', variant: 'secondary' as const, icon: AlertCircle };
    }
  };

  if (loading || !user || !profile) {
    return null;
  }

  return (
    <DashboardLayout>
      <div className="space-y-6">
        <div className="flex justify-between items-center">
          <div>
            <h1 className="text-3xl font-bold">POD Management</h1>
            <p className="text-muted-foreground mt-1">
              Manage license plate detection devices at your communities
            </p>
          </div>
          <Button onClick={() => setShowAddDialog(true)}>
            <Plus className="w-4 h-4 mr-2" />
            Add POD
          </Button>
        </div>

        {loadingPods ? (
          <div className="text-center py-12">
            <p className="text-muted-foreground">Loading PODs...</p>
          </div>
        ) : pods.length === 0 ? (
          <Card>
            <CardContent className="py-12 text-center">
              <Server className="w-12 h-12 mx-auto mb-4 text-muted-foreground" />
              <h3 className="text-lg font-semibold mb-2">No PODs Yet</h3>
              <p className="text-muted-foreground mb-6">
                Get started by adding your first POD device
              </p>
              <Button onClick={() => setShowAddDialog(true)}>
                <Plus className="w-4 h-4 mr-2" />
                Add Your First POD
              </Button>
            </CardContent>
          </Card>
        ) : (
          <div className="grid gap-4 md:grid-cols-2 lg:grid-cols-3">
            {pods.map((pod) => {
              const status = getPodStatus(pod);
              const StatusIcon = status.icon;

              return (
                <Card key={pod.id}>
                  <CardHeader>
                    <div className="flex items-start justify-between">
                      <div className="flex-1">
                        <CardTitle className="flex items-center gap-2">
                          <Server className="w-5 h-5" />
                          {pod.name}
                        </CardTitle>
                        <CardDescription className="mt-1">
                          {pod.community_name}
                        </CardDescription>
                      </div>
                      <Badge variant={status.variant}>
                        <StatusIcon className="w-3 h-3 mr-1" />
                        {status.label}
                      </Badge>
                    </div>
                  </CardHeader>
                  <CardContent>
                    <div className="space-y-3">
                      <div>
                        <p className="text-xs text-muted-foreground">POD ID</p>
                        <p className="text-sm font-mono">{pod.pod_id}</p>
                      </div>

                      {pod.last_used_at && (
                        <div>
                          <p className="text-xs text-muted-foreground">Last Active</p>
                          <p className="text-sm">
                            {formatDistanceToNow(new Date(pod.last_used_at), { addSuffix: true })}
                          </p>
                        </div>
                      )}

                      <div>
                        <p className="text-xs text-muted-foreground">Created</p>
                        <p className="text-sm">
                          {formatDistanceToNow(new Date(pod.created_at), { addSuffix: true })}
                        </p>
                      </div>

                      {!pod.revoked_at && (
                        <Button
                          variant="destructive"
                          size="sm"
                          className="w-full mt-4"
                          onClick={() => handleRevokePod(pod.id)}
                        >
                          <Trash2 className="w-4 h-4 mr-2" />
                          Revoke Access
                        </Button>
                      )}
                    </div>
                  </CardContent>
                </Card>
              );
            })}
          </div>
        )}
      </div>

      <Dialog open={showAddDialog} onOpenChange={setShowAddDialog}>
        <DialogContent>
          <DialogHeader>
            <DialogTitle>Add New POD</DialogTitle>
            <DialogDescription>
              Register a new license plate detection device
            </DialogDescription>
          </DialogHeader>

          <div className="space-y-4">
            <div>
              <Label htmlFor="community">Community Location</Label>
              <Select value={selectedCommunityId} onValueChange={setSelectedCommunityId}>
                <SelectTrigger id="community">
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
              <Label htmlFor="podName">POD Name</Label>
              <Input
                id="podName"
                placeholder="e.g., Main Gate, North Entrance"
                value={podName}
                onChange={(e) => setPodName(e.target.value)}
              />
              <p className="text-xs text-muted-foreground mt-1">
                A friendly name to identify this POD
              </p>
            </div>

            <div>
              <Label htmlFor="podId">POD ID</Label>
              <Input
                id="podId"
                placeholder="e.g., main-gate, north-entrance"
                value={podId}
                onChange={(e) => setPodId(e.target.value.toLowerCase().replace(/\s+/g, '-'))}
              />
              <p className="text-xs text-muted-foreground mt-1">
                Unique identifier (lowercase, hyphens only)
              </p>
            </div>
          </div>

          <DialogFooter>
            <Button variant="outline" onClick={() => setShowAddDialog(false)}>
              Cancel
            </Button>
            <Button onClick={handleCreatePod} disabled={creating}>
              {creating ? 'Creating...' : 'Create POD'}
            </Button>
          </DialogFooter>
        </DialogContent>
      </Dialog>

      <Dialog open={showSetupDialog} onOpenChange={setShowSetupDialog}>
        <DialogContent className="max-w-2xl">
          <DialogHeader>
            <DialogTitle className="flex items-center gap-2">
              <CheckCircle2 className="w-5 h-5 text-green-600" />
              POD Created Successfully
            </DialogTitle>
            <DialogDescription>
              Run this command on your Ubuntu server to install and configure the POD
            </DialogDescription>
          </DialogHeader>

          <div className="space-y-4">
            <div>
              <Label>API Key</Label>
              <div className="flex gap-2 mt-1">
                <Input
                  value={generatedApiKey}
                  readOnly
                  className="font-mono text-sm"
                />
                <Button variant="outline" size="icon" onClick={handleCopyApiKey}>
                  <Copy className="w-4 h-4" />
                </Button>
              </div>
              <p className="text-xs text-destructive mt-1">
                Save this key! You won't be able to see it again.
              </p>
            </div>

            <div>
              <Label>Installation Command</Label>
              <div className="bg-slate-950 text-slate-50 p-4 rounded-lg mt-2 relative">
                <code className="text-sm break-all">{setupCommand}</code>
                <Button
                  variant="ghost"
                  size="sm"
                  className="absolute top-2 right-2"
                  onClick={handleCopyCommand}
                >
                  {copiedCommand ? (
                    <CheckCircle2 className="w-4 h-4" />
                  ) : (
                    <Copy className="w-4 h-4" />
                  )}
                </Button>
              </div>
              <p className="text-xs text-muted-foreground mt-2">
                SSH into your Ubuntu server and run this command as root or with sudo
              </p>
            </div>

            <div className="bg-blue-50 border border-blue-200 rounded-lg p-4">
              <h4 className="font-semibold text-sm mb-2">Next Steps:</h4>
              <ol className="text-sm space-y-1 list-decimal list-inside">
                <li>Copy the installation command above</li>
                <li>SSH into your Ubuntu server</li>
                <li>Run the command</li>
                <li>The POD will auto-configure and start monitoring</li>
              </ol>
            </div>
          </div>

          <DialogFooter>
            <Button onClick={() => setShowSetupDialog(false)}>
              Done
            </Button>
          </DialogFooter>
        </DialogContent>
      </Dialog>
    </DashboardLayout>
  );
}
