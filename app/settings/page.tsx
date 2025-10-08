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
import { Tabs, TabsContent, TabsList, TabsTrigger } from '@/components/ui/tabs';
import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from '@/components/ui/select';
import { Switch } from '@/components/ui/switch';
import { Dialog, DialogContent, DialogDescription, DialogHeader, DialogTitle, DialogFooter } from '@/components/ui/dialog';
import { supabase } from '@/lib/supabase';
import { toast } from 'sonner';
import { Key, Building2, Link as LinkIcon, Shield, Trash2, Copy, Plus, CheckCircle2 } from 'lucide-react';

interface Community {
  id: string;
  name: string;
  gatewise_enabled: boolean;
}

interface GatewiseConfig {
  id?: string;
  community_id: string;
  api_key: string;
  api_endpoint: string;
  gatewise_community_id: string;
  gatewise_access_point_id: string;
  enabled: boolean;
  last_sync: string | null;
  sync_status: string;
}

interface Site {
  id: string;
  name: string;
  community_id: string;
}

interface PodApiKey {
  id: string;
  name: string;
  site_id: string;
  pod_id: string;
  created_at: string;
  last_used_at: string | null;
}

export default function SettingsPage() {
  const { user, profile, loading, effectiveRole } = useAuth();
  const { activeCompanyId } = useCompany();
  const router = useRouter();
  const [communities, setCommunities] = useState<Community[]>([]);
  const [selectedCommunity, setSelectedCommunity] = useState<string>('');
  const [gatewiseConfig, setGatewiseConfig] = useState<GatewiseConfig>({
    community_id: '',
    api_key: '',
    api_endpoint: 'https://partners-api.gatewise.com',
    gatewise_community_id: '',
    gatewise_access_point_id: '',
    enabled: true,
    last_sync: null,
    sync_status: 'pending',
  });
  const [loadingConfig, setLoadingConfig] = useState(false);
  const [saving, setSaving] = useState(false);
  const [testing, setTesting] = useState(false);
  const [fetchingAccessPoints, setFetchingAccessPoints] = useState(false);
  const [accessPoints, setAccessPoints] = useState<Array<{id: string, name: string}>>([]);
  const [podApiKeys, setPodApiKeys] = useState<PodApiKey[]>([]);
  const [sites, setSites] = useState<Site[]>([]);
  const [showCreateKeyDialog, setShowCreateKeyDialog] = useState(false);
  const [newKeyName, setNewKeyName] = useState('');
  const [newKeySiteId, setNewKeySiteId] = useState('');
  const [newKeyPodId, setNewKeyPodId] = useState('');
  const [creatingKey, setCreatingKey] = useState(false);
  const [generatedApiKey, setGeneratedApiKey] = useState<string | null>(null);

  useEffect(() => {
    if (!loading && !user) {
      router.push('/login');
    }
  }, [user, loading, router]);

  useEffect(() => {
    if (user && profile && activeCompanyId) {
      fetchCommunities();
      fetchSites();
      fetchPodApiKeys();
    }
  }, [user, profile, activeCompanyId]);

  useEffect(() => {
    if (selectedCommunity) {
      fetchGatewiseConfig(selectedCommunity);
    }
  }, [selectedCommunity]);

  const fetchCommunities = async () => {
    if (!activeCompanyId) return;
    const { data } = await supabase
      .from('communities')
      .select('id, name, gatewise_enabled')
      .eq('company_id', activeCompanyId)
      .order('name');

    if (data) {
      setCommunities(data);
      if (data.length > 0 && !selectedCommunity) {
        setSelectedCommunity(data[0].id);
      }
    }
  };

  const fetchSites = async () => {
    if (!activeCompanyId) return;
    const { data } = await supabase
      .from('sites')
      .select('id, name, community_id')
      .order('name');

    if (data) {
      setSites(data);
    }
  };

  const fetchPodApiKeys = async () => {
    try {
      const { data: { session } } = await supabase.auth.getSession();
      if (!session) return;

      const response = await fetch('/api/pod/api-keys', {
        headers: {
          'Authorization': `Bearer ${session.access_token}`,
        },
      });

      if (response.ok) {
        const result = await response.json();
        setPodApiKeys(result.keys || []);
      }
    } catch (error) {
      console.error('Error fetching API keys:', error);
    }
  };

  const handleCreateApiKey = async () => {
    if (!newKeyName.trim() || !newKeySiteId || !newKeyPodId.trim()) {
      toast.error('Please fill in all fields');
      return;
    }

    setCreatingKey(true);

    try {
      const { data: { session } } = await supabase.auth.getSession();
      if (!session) {
        toast.error('Not authenticated');
        return;
      }

      const response = await fetch('/api/pod/api-keys', {
        method: 'POST',
        headers: {
          'Authorization': `Bearer ${session.access_token}`,
          'Content-Type': 'application/json',
        },
        body: JSON.stringify({
          name: newKeyName,
          site_id: newKeySiteId,
          pod_id: newKeyPodId,
        }),
      });

      if (response.ok) {
        const result = await response.json();
        setGeneratedApiKey(result.api_key);
        toast.success('API key created successfully!');
        fetchPodApiKeys();
        setNewKeyName('');
        setNewKeySiteId('');
        setNewKeyPodId('');
      } else {
        const error = await response.json();
        toast.error(error.error || 'Failed to create API key');
      }
    } catch (error) {
      toast.error('Failed to create API key');
      console.error(error);
    } finally {
      setCreatingKey(false);
    }
  };

  const handleDeleteApiKey = async (keyId: string) => {
    if (!confirm('Are you sure you want to delete this API key? This cannot be undone.')) {
      return;
    }

    try {
      const { data: { session } } = await supabase.auth.getSession();
      if (!session) {
        toast.error('Not authenticated');
        return;
      }

      const response = await fetch(`/api/pod/api-keys?id=${keyId}`, {
        method: 'DELETE',
        headers: {
          'Authorization': `Bearer ${session.access_token}`,
        },
      });

      if (response.ok) {
        toast.success('API key deleted successfully');
        fetchPodApiKeys();
      } else {
        toast.error('Failed to delete API key');
      }
    } catch (error) {
      toast.error('Failed to delete API key');
      console.error(error);
    }
  };

  const copyToClipboard = (text: string) => {
    navigator.clipboard.writeText(text);
    toast.success('Copied to clipboard');
  };

  const closeCreateDialog = () => {
    setShowCreateKeyDialog(false);
    setGeneratedApiKey(null);
    setNewKeyName('');
    setNewKeySiteId('');
    setNewKeyPodId('');
  };

  const fetchGatewiseConfig = async (communityId: string) => {
    setLoadingConfig(true);
    const { data } = await supabase
      .from('gatewise_config')
      .select('*')
      .eq('community_id', communityId)
      .maybeSingle();

    if (data) {
      setGatewiseConfig(data);
    } else {
      setGatewiseConfig({
        community_id: communityId,
        api_key: '',
        api_endpoint: 'https://partners-api.gatewise.com',
        gatewise_community_id: '',
        gatewise_access_point_id: '',
        enabled: true,
        last_sync: null,
        sync_status: 'pending',
      });
    }
    setLoadingConfig(false);
  };

  const handleSaveGatewiseConfig = async () => {
    if (!selectedCommunity) {
      toast.error('Please select a community');
      return;
    }

    if (!gatewiseConfig.api_key.trim()) {
      toast.error('API key is required');
      return;
    }

    setSaving(true);

    const configData = {
      community_id: selectedCommunity,
      api_key: gatewiseConfig.api_key,
      api_endpoint: gatewiseConfig.api_endpoint,
      enabled: gatewiseConfig.enabled,
    };

    if (gatewiseConfig.id) {
      const { error } = await supabase
        .from('gatewise_config')
        .update(configData)
        .eq('id', gatewiseConfig.id);

      if (error) {
        toast.error('Failed to update Gatewise configuration');
        setSaving(false);
        return;
      }
    } else {
      const { error } = await supabase
        .from('gatewise_config')
        .insert(configData);

      if (error) {
        toast.error('Failed to save Gatewise configuration');
        setSaving(false);
        return;
      }
    }

    await supabase
      .from('communities')
      .update({ gatewise_enabled: gatewiseConfig.enabled })
      .eq('id', selectedCommunity);

    toast.success('Gatewise configuration saved successfully');
    setSaving(false);
    fetchGatewiseConfig(selectedCommunity);
    fetchCommunities();
  };

  const handleFetchAccessPoints = async () => {
    if (!gatewiseConfig.api_key.trim()) {
      toast.error('Please enter an API key first');
      return;
    }

    if (!gatewiseConfig.api_endpoint.trim()) {
      toast.error('Please enter an API endpoint');
      return;
    }

    if (!gatewiseConfig.gatewise_community_id.trim()) {
      toast.error('Please enter a Gatewise Community ID');
      return;
    }

    setFetchingAccessPoints(true);
    toast.info('Fetching available access points...');

    try {
      const response = await fetch('/api/gatewise/access-points', {
        method: 'POST',
        headers: {
          'Content-Type': 'application/json',
        },
        body: JSON.stringify({
          api_key: gatewiseConfig.api_key,
          api_endpoint: gatewiseConfig.api_endpoint,
          community_id: gatewiseConfig.gatewise_community_id,
        }),
      });

      const result = await response.json();

      if (result.success && result.access_points) {
        setAccessPoints(result.access_points);
        toast.success(`Found ${result.access_points.length} access point(s)`);
      } else {
        toast.error(result.message || 'Failed to fetch access points');
      }
    } catch (error: any) {
      toast.error(`Failed to fetch access points: ${error.message}`);
    } finally {
      setFetchingAccessPoints(false);
    }
  };

  const handleTestConnection = async () => {
    if (!gatewiseConfig.api_key.trim()) {
      toast.error('Please enter an API key first');
      return;
    }

    if (!gatewiseConfig.api_endpoint.trim()) {
      toast.error('Please enter an API endpoint');
      return;
    }

    if (!gatewiseConfig.gatewise_community_id.trim()) {
      toast.error('Please enter a Gatewise Community ID');
      return;
    }

    if (!gatewiseConfig.gatewise_access_point_id.trim()) {
      toast.error('Please select an access point to test');
      return;
    }

    setTesting(true);
    toast.info('Testing gate open command...');

    try {
      const response = await fetch('/api/gatewise/test', {
        method: 'POST',
        headers: {
          'Content-Type': 'application/json',
        },
        body: JSON.stringify({
          api_key: gatewiseConfig.api_key,
          api_endpoint: gatewiseConfig.api_endpoint,
          community_id: gatewiseConfig.gatewise_community_id,
          access_point_id: gatewiseConfig.gatewise_access_point_id,
        }),
      });

      const result = await response.json();

      if (result.success) {
        toast.success('Gate opened successfully!');
      } else {
        toast.error(result.message || 'Failed to open gate');
      }
    } catch (error: any) {
      toast.error(`Test failed: ${error.message}`);
    } finally {
      setTesting(false);
    }
  };

  if (loading || !user || !profile) {
    return (
      <div className="min-h-screen flex items-center justify-center bg-white dark:bg-[#1E293B]">
        <div className="text-lg">Loading...</div>
      </div>
    );
  }

  if (effectiveRole === 'viewer' || effectiveRole === 'resident') {
    return (
      <DashboardLayout>
        <div className="max-w-4xl mx-auto">
          <Card className="p-8 text-center">
            <Shield className="w-12 h-12 mx-auto mb-4 text-muted-foreground" />
            <h3 className="text-xl font-semibold mb-2">Access Restricted</h3>
            <p className="text-muted-foreground">
              You don't have permission to access settings. Contact your administrator.
            </p>
          </Card>
        </div>
      </DashboardLayout>
    );
  }

  return (
    <DashboardLayout>
      <div className="max-w-5xl mx-auto">
        <div className="mb-8">
          <h2 className="text-3xl font-bold mb-2">Settings</h2>
          <p className="text-muted-foreground">
            Manage your integrations and system configuration
          </p>
        </div>

        <Tabs defaultValue="gatewise" className="space-y-6">
          <TabsList className="grid w-full grid-cols-3">
            <TabsTrigger value="gatewise">
              <LinkIcon className="w-4 h-4 mr-2" />
              Gatewise Integration
            </TabsTrigger>
            <TabsTrigger value="company">
              <Building2 className="w-4 h-4 mr-2" />
              Company Settings
            </TabsTrigger>
            <TabsTrigger value="api">
              <Key className="w-4 h-4 mr-2" />
              API Keys
            </TabsTrigger>
          </TabsList>

          <TabsContent value="gatewise" className="space-y-6">
            <Card className="p-6 bg-white dark:bg-[#2D3748]">
              <div className="flex items-start gap-4 mb-6">
                <div className="p-3 rounded-lg bg-blue-100 dark:bg-blue-900/20">
                  <LinkIcon className="w-6 h-6 text-blue-600 dark:text-blue-400" />
                </div>
                <div className="flex-1">
                  <h3 className="text-xl font-bold mb-1">Gatewise Integration</h3>
                  <p className="text-sm text-muted-foreground">
                    Connect your communities to Gatewise for automated gate control.
                    Each community can have its own API configuration.
                  </p>
                </div>
              </div>

              <div className="space-y-6">
                <div>
                  <Label>Select Community</Label>
                  <Select value={selectedCommunity} onValueChange={setSelectedCommunity}>
                    <SelectTrigger className="mt-2">
                      <SelectValue placeholder="Choose a community" />
                    </SelectTrigger>
                    <SelectContent>
                      {communities.map((community) => (
                        <SelectItem key={community.id} value={community.id}>
                          {community.name}
                          {community.gatewise_enabled && (
                            <span className="ml-2 text-xs text-green-600 dark:text-green-400">
                              ● Connected
                            </span>
                          )}
                        </SelectItem>
                      ))}
                    </SelectContent>
                  </Select>
                </div>

                {selectedCommunity && !loadingConfig && (
                  <>
                    <div className="flex items-center justify-between p-4 rounded-lg bg-muted/50">
                      <div>
                        <Label className="font-semibold">Enable Gatewise Integration</Label>
                        <p className="text-sm text-muted-foreground mt-1">
                          Automatically sync plates to Gatewise gates
                        </p>
                      </div>
                      <Switch
                        checked={gatewiseConfig.enabled}
                        onCheckedChange={(checked) =>
                          setGatewiseConfig({ ...gatewiseConfig, enabled: checked })
                        }
                      />
                    </div>

                    <div>
                      <Label>Gatewise API Key</Label>
                      <Input
                        type="password"
                        value={gatewiseConfig.api_key}
                        onChange={(e) =>
                          setGatewiseConfig({ ...gatewiseConfig, api_key: e.target.value })
                        }
                        placeholder="gw_live_••••••••••••••••"
                        className="mt-2 font-mono"
                      />
                      <p className="text-xs text-muted-foreground mt-1">
                        Your API key will be encrypted and stored securely
                      </p>
                    </div>

                    <div>
                      <Label>API Endpoint</Label>
                      <Input
                        value={gatewiseConfig.api_endpoint}
                        onChange={(e) =>
                          setGatewiseConfig({ ...gatewiseConfig, api_endpoint: e.target.value })
                        }
                        placeholder="https://partners-api.gatewise.com"
                        className="mt-2"
                      />
                      <p className="text-xs text-muted-foreground mt-1">
                        Enter the base URL only (e.g., https://partners-api.gatewise.com)
                      </p>
                    </div>

                    <div>
                      <Label>Gatewise Community ID</Label>
                      <Input
                        value={gatewiseConfig.gatewise_community_id}
                        onChange={(e) => {
                          setGatewiseConfig({ ...gatewiseConfig, gatewise_community_id: e.target.value });
                          setAccessPoints([]);
                        }}
                        placeholder="3714"
                        className="mt-2"
                      />
                      <p className="text-xs text-muted-foreground mt-1">
                        From the Gatewise API URL
                      </p>
                    </div>

                    <div className="flex gap-2">
                      <Button
                        onClick={handleFetchAccessPoints}
                        disabled={fetchingAccessPoints || !gatewiseConfig.api_key || !gatewiseConfig.gatewise_community_id}
                        variant="outline"
                        className="flex-1"
                      >
                        {fetchingAccessPoints ? 'Fetching...' : 'Fetch Available Access Points'}
                      </Button>
                    </div>

                    {accessPoints.length > 0 && (
                      <div>
                        <Label>Select Access Point</Label>
                        <Select
                          value={gatewiseConfig.gatewise_access_point_id}
                          onValueChange={(value) =>
                            setGatewiseConfig({ ...gatewiseConfig, gatewise_access_point_id: value })
                          }
                        >
                          <SelectTrigger className="mt-2">
                            <SelectValue placeholder="Choose an access point" />
                          </SelectTrigger>
                          <SelectContent>
                            {accessPoints.map((ap) => (
                              <SelectItem key={ap.id} value={ap.id}>
                                {ap.name} (ID: {ap.id})
                              </SelectItem>
                            ))}
                          </SelectContent>
                        </Select>
                        <p className="text-xs text-muted-foreground mt-1">
                          Select the gate/access point to control
                        </p>
                      </div>
                    )}

                    {gatewiseConfig.last_sync && (
                      <div className="p-4 rounded-lg bg-muted/50">
                        <div className="flex items-center justify-between">
                          <div>
                            <p className="text-sm font-medium">Last Sync</p>
                            <p className="text-sm text-muted-foreground">
                              {new Date(gatewiseConfig.last_sync).toLocaleString()}
                            </p>
                          </div>
                          <div className={`px-3 py-1 rounded-full text-xs font-medium ${
                            gatewiseConfig.sync_status === 'success'
                              ? 'bg-green-100 text-green-700 dark:bg-green-900/20 dark:text-green-400'
                              : gatewiseConfig.sync_status === 'error'
                              ? 'bg-red-100 text-red-700 dark:bg-red-900/20 dark:text-red-400'
                              : 'bg-yellow-100 text-yellow-700 dark:bg-yellow-900/20 dark:text-yellow-400'
                          }`}>
                            {gatewiseConfig.sync_status}
                          </div>
                        </div>
                      </div>
                    )}

                    <div className="flex gap-3">
                      <Button
                        onClick={handleSaveGatewiseConfig}
                        disabled={saving || testing}
                        className="flex-1 rounded-xl bg-[#0A84FF] hover:bg-[#0869CC]"
                      >
                        {saving ? 'Saving...' : 'Save Configuration'}
                      </Button>
                      <Button
                        onClick={handleTestConnection}
                        disabled={testing || saving || !gatewiseConfig.gatewise_access_point_id}
                        variant="outline"
                        className="rounded-xl"
                      >
                        {testing ? 'Testing...' : 'Test Gate Open'}
                      </Button>
                    </div>
                  </>
                )}
              </div>
            </Card>
          </TabsContent>

          <TabsContent value="company" className="space-y-6">
            <Card className="p-6 bg-white dark:bg-[#2D3748]">
              <div className="flex items-start gap-4 mb-6">
                <div className="p-3 rounded-lg bg-purple-100 dark:bg-purple-900/20">
                  <Building2 className="w-6 h-6 text-purple-600 dark:text-purple-400" />
                </div>
                <div className="flex-1">
                  <h3 className="text-xl font-bold mb-1">Company Settings</h3>
                  <p className="text-sm text-muted-foreground">
                    Manage your company profile and branding
                  </p>
                </div>
              </div>

              <p className="text-muted-foreground">
                Company settings coming soon. Configure logo, SLA targets, and more.
              </p>
            </Card>
          </TabsContent>

          <TabsContent value="api" className="space-y-6">
            <Card className="p-6 bg-white dark:bg-[#2D3748]">
              <div className="flex items-start gap-4 mb-6">
                <div className="p-3 rounded-lg bg-cyan-100 dark:bg-cyan-900/20">
                  <Key className="w-6 h-6 text-cyan-600 dark:text-cyan-400" />
                </div>
                <div className="flex-1">
                  <h3 className="text-xl font-bold mb-1">Pod API Keys</h3>
                  <p className="text-sm text-muted-foreground">
                    Generate API keys for pod authentication. Each pod needs its own API key.
                  </p>
                </div>
                <Button
                  onClick={() => setShowCreateKeyDialog(true)}
                  className="rounded-xl bg-[#0A84FF] hover:bg-[#0869CC]"
                >
                  <Plus className="w-4 h-4 mr-2" />
                  Create API Key
                </Button>
              </div>

              {podApiKeys.length === 0 ? (
                <div className="text-center py-12">
                  <Key className="w-12 h-12 mx-auto mb-4 text-muted-foreground opacity-50" />
                  <h3 className="text-lg font-semibold mb-2">No API Keys</h3>
                  <p className="text-muted-foreground mb-4">
                    Create your first API key to authenticate your pods
                  </p>
                  <Button
                    onClick={() => setShowCreateKeyDialog(true)}
                    variant="outline"
                    className="rounded-xl"
                  >
                    <Plus className="w-4 h-4 mr-2" />
                    Create API Key
                  </Button>
                </div>
              ) : (
                <div className="space-y-3">
                  {podApiKeys.map((key) => {
                    const site = sites.find(s => s.id === key.site_id);
                    return (
                      <div
                        key={key.id}
                        className="flex items-center justify-between p-4 rounded-lg border border-border bg-muted/30"
                      >
                        <div className="flex-1">
                          <div className="flex items-center gap-3 mb-1">
                            <h4 className="font-semibold">{key.name}</h4>
                            <span className="text-xs px-2 py-1 rounded-full bg-blue-100 dark:bg-blue-900/20 text-blue-700 dark:text-blue-400">
                              {key.pod_id}
                            </span>
                          </div>
                          <div className="text-sm text-muted-foreground space-y-1">
                            <p>Site: {site?.name || key.site_id}</p>
                            <p>Created: {new Date(key.created_at).toLocaleDateString()}</p>
                            {key.last_used_at && (
                              <p>Last used: {new Date(key.last_used_at).toLocaleString()}</p>
                            )}
                          </div>
                        </div>
                        <Button
                          onClick={() => handleDeleteApiKey(key.id)}
                          variant="ghost"
                          size="sm"
                          className="text-red-600 hover:text-red-700 hover:bg-red-100 dark:hover:bg-red-900/20"
                        >
                          <Trash2 className="w-4 h-4" />
                        </Button>
                      </div>
                    );
                  })}
                </div>
              )}
            </Card>
          </TabsContent>
        </Tabs>

        <Dialog open={showCreateKeyDialog} onOpenChange={closeCreateDialog}>
          <DialogContent className="sm:max-w-md">
            <DialogHeader>
              <DialogTitle>
                {generatedApiKey ? 'API Key Created' : 'Create Pod API Key'}
              </DialogTitle>
              <DialogDescription>
                {generatedApiKey
                  ? 'Save this API key now. You will not be able to see it again.'
                  : 'Generate a new API key for pod authentication'}
              </DialogDescription>
            </DialogHeader>

            {generatedApiKey ? (
              <div className="space-y-4">
                <div className="p-4 rounded-lg bg-green-50 dark:bg-green-900/20 border border-green-200 dark:border-green-800">
                  <div className="flex items-start gap-3 mb-3">
                    <CheckCircle2 className="w-5 h-5 text-green-600 dark:text-green-400 mt-0.5" />
                    <div>
                      <p className="font-semibold text-green-900 dark:text-green-100">
                        API Key Created Successfully
                      </p>
                      <p className="text-sm text-green-700 dark:text-green-300 mt-1">
                        Copy this key and save it securely. This is the only time it will be shown.
                      </p>
                    </div>
                  </div>
                </div>

                <div>
                  <Label>Your API Key</Label>
                  <div className="flex gap-2 mt-2">
                    <Input
                      value={generatedApiKey}
                      readOnly
                      className="font-mono text-sm"
                    />
                    <Button
                      onClick={() => copyToClipboard(generatedApiKey)}
                      variant="outline"
                      size="sm"
                    >
                      <Copy className="w-4 h-4" />
                    </Button>
                  </div>
                </div>

                <div className="p-3 rounded-lg bg-amber-50 dark:bg-amber-900/20 border border-amber-200 dark:border-amber-800">
                  <p className="text-sm text-amber-800 dark:text-amber-200">
                    Add this key to your pod's <code className="px-1 py-0.5 rounded bg-amber-100 dark:bg-amber-900/40">config.yaml</code> file
                  </p>
                </div>
              </div>
            ) : (
              <div className="space-y-4">
                <div>
                  <Label>Key Name</Label>
                  <Input
                    value={newKeyName}
                    onChange={(e) => setNewKeyName(e.target.value)}
                    placeholder="Front Gate Pod"
                    className="mt-2"
                  />
                  <p className="text-xs text-muted-foreground mt-1">
                    A friendly name to identify this key
                  </p>
                </div>

                <div>
                  <Label>Site</Label>
                  <Select value={newKeySiteId} onValueChange={setNewKeySiteId}>
                    <SelectTrigger className="mt-2">
                      <SelectValue placeholder="Select a site" />
                    </SelectTrigger>
                    <SelectContent>
                      {sites.map((site) => (
                        <SelectItem key={site.id} value={site.id}>
                          {site.name}
                        </SelectItem>
                      ))}
                    </SelectContent>
                  </Select>
                  <p className="text-xs text-muted-foreground mt-1">
                    Which site/property this pod is located at
                  </p>
                </div>

                <div>
                  <Label>Pod ID</Label>
                  <Input
                    value={newKeyPodId}
                    onChange={(e) => setNewKeyPodId(e.target.value)}
                    placeholder="front-gate"
                    className="mt-2"
                  />
                  <p className="text-xs text-muted-foreground mt-1">
                    A unique identifier for this pod (e.g., front-gate, back-entrance)
                  </p>
                </div>
              </div>
            )}

            <DialogFooter>
              {generatedApiKey ? (
                <Button onClick={closeCreateDialog} className="w-full rounded-xl">
                  Done
                </Button>
              ) : (
                <>
                  <Button
                    onClick={closeCreateDialog}
                    variant="outline"
                    disabled={creatingKey}
                    className="rounded-xl"
                  >
                    Cancel
                  </Button>
                  <Button
                    onClick={handleCreateApiKey}
                    disabled={creatingKey}
                    className="rounded-xl bg-[#0A84FF] hover:bg-[#0869CC]"
                  >
                    {creatingKey ? 'Creating...' : 'Create API Key'}
                  </Button>
                </>
              )}
            </DialogFooter>
          </DialogContent>
        </Dialog>
      </div>
    </DashboardLayout>
  );
}
