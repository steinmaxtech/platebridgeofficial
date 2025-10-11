'use client';

import { useState, useEffect } from 'react';
import { useRouter, useParams } from 'next/navigation';
import { DashboardLayout } from '@/components/dashboard-layout';
import { useAuth } from '@/lib/auth-context';
import { Card, CardContent, CardDescription, CardHeader, CardTitle } from '@/components/ui/card';
import { Button } from '@/components/ui/button';
import { Badge } from '@/components/ui/badge';
import { Table, TableBody, TableCell, TableHead, TableHeader, TableRow } from '@/components/ui/table';
import { Dialog, DialogContent, DialogDescription, DialogFooter, DialogHeader, DialogTitle, DialogTrigger } from '@/components/ui/dialog';
import { Input } from '@/components/ui/input';
import { Label } from '@/components/ui/label';
import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from '@/components/ui/select';
import { Switch } from '@/components/ui/switch';
import { Tabs, TabsContent, TabsList, TabsTrigger } from '@/components/ui/tabs';
import { toast } from 'sonner';
import {
  ArrowLeft, Plus, Trash2, Edit, Shield, AlertCircle,
  Truck, Siren, Wrench, User, Clock, Calendar
} from 'lucide-react';
import { formatDistanceToNow } from 'date-fns';

interface AccessEntry {
  id: string;
  plate: string;
  type: string;
  vendor_name: string | null;
  schedule_start: string | null;
  schedule_end: string | null;
  days_active: string;
  expires_at: string | null;
  notes: string | null;
  is_active: boolean;
  created_at: string;
}

interface AccessSettings {
  auto_grant_enabled: boolean;
  lockdown_mode: boolean;
  require_confidence: number;
  notification_on_grant: boolean;
  notification_emails: string[];
}

interface AccessLog {
  id: string;
  plate: string;
  decision: string;
  reason: string;
  access_type: string | null;
  vendor_name: string | null;
  gate_triggered: boolean;
  confidence: number | null;
  timestamp: string;
}

export default function CommunityAccessPage() {
  const router = useRouter();
  const params = useParams();
  const communityId = params?.id as string;
  const { user, loading } = useAuth();

  const [accessList, setAccessList] = useState<AccessEntry[]>([]);
  const [settings, setSettings] = useState<AccessSettings | null>(null);
  const [logs, setLogs] = useState<AccessLog[]>([]);
  const [loadingData, setLoadingData] = useState(true);
  const [showAddDialog, setShowAddDialog] = useState(false);
  const [editingEntry, setEditingEntry] = useState<AccessEntry | null>(null);

  const [newEntry, setNewEntry] = useState({
    plate: '',
    type: 'delivery',
    vendor_name: '',
    schedule_start: '',
    schedule_end: '',
    days_active: 'Mon-Sun',
    expires_at: '',
    notes: '',
  });

  useEffect(() => {
    if (!loading && !user) {
      router.push('/login');
    }
  }, [user, loading, router]);

  useEffect(() => {
    if (user && communityId) {
      loadData();
    }
  }, [user, communityId]);

  const loadData = async () => {
    try {
      setLoadingData(true);

      // Load access list
      const listRes = await fetch(`/api/access/manage?community_id=${communityId}`);
      const listData = await listRes.json();
      setAccessList(listData.access_list || []);

      // Load settings
      const settingsRes = await fetch(`/api/access/settings/${communityId}`);
      const settingsData = await settingsRes.json();
      setSettings(settingsData.settings);

      // Load logs
      const logsRes = await fetch(`/api/access/log?community_id=${communityId}&limit=50`);
      const logsData = await logsRes.json();
      setLogs(logsData.logs || []);
    } catch (error) {
      console.error('Error loading data:', error);
      toast.error('Failed to load access control data');
    } finally {
      setLoadingData(false);
    }
  };

  const handleAddEntry = async () => {
    try {
      const response = await fetch('/api/access/manage', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({
          community_id: communityId,
          ...newEntry,
        }),
      });

      if (!response.ok) {
        throw new Error('Failed to add entry');
      }

      toast.success('Access entry added successfully');
      setShowAddDialog(false);
      setNewEntry({
        plate: '',
        type: 'delivery',
        vendor_name: '',
        schedule_start: '',
        schedule_end: '',
        days_active: 'Mon-Sun',
        expires_at: '',
        notes: '',
      });
      loadData();
    } catch (error) {
      console.error('Error adding entry:', error);
      toast.error('Failed to add access entry');
    }
  };

  const handleDeleteEntry = async (id: string) => {
    if (!confirm('Are you sure you want to delete this access entry?')) {
      return;
    }

    try {
      const response = await fetch(`/api/access/manage?id=${id}`, {
        method: 'DELETE',
      });

      if (!response.ok) {
        throw new Error('Failed to delete entry');
      }

      toast.success('Access entry deleted');
      loadData();
    } catch (error) {
      console.error('Error deleting entry:', error);
      toast.error('Failed to delete access entry');
    }
  };

  const handleToggleActive = async (entry: AccessEntry) => {
    try {
      const response = await fetch('/api/access/manage', {
        method: 'PATCH',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({
          id: entry.id,
          is_active: !entry.is_active,
        }),
      });

      if (!response.ok) {
        throw new Error('Failed to update entry');
      }

      toast.success(`Access entry ${entry.is_active ? 'disabled' : 'enabled'}`);
      loadData();
    } catch (error) {
      console.error('Error updating entry:', error);
      toast.error('Failed to update access entry');
    }
  };

  const handleUpdateSettings = async (updates: Partial<AccessSettings>) => {
    if (!settings) return;

    try {
      const response = await fetch(`/api/access/settings/${communityId}`, {
        method: 'PATCH',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ ...settings, ...updates }),
      });

      if (!response.ok) {
        throw new Error('Failed to update settings');
      }

      toast.success('Settings updated');
      loadData();
    } catch (error) {
      console.error('Error updating settings:', error);
      toast.error('Failed to update settings');
    }
  };

  const getTypeIcon = (type: string) => {
    switch (type) {
      case 'emergency':
        return <Siren className="h-4 w-4 text-red-500" />;
      case 'delivery':
        return <Truck className="h-4 w-4 text-blue-500" />;
      case 'service':
        return <Wrench className="h-4 w-4 text-yellow-500" />;
      case 'resident':
        return <User className="h-4 w-4 text-green-500" />;
      default:
        return <User className="h-4 w-4 text-gray-500" />;
    }
  };

  const getDecisionBadge = (decision: string) => {
    const colors = {
      granted: 'bg-green-500',
      denied: 'bg-red-500',
      manual: 'bg-yellow-500',
      override: 'bg-blue-500',
    };
    return <Badge className={colors[decision as keyof typeof colors] || 'bg-gray-500'}>{decision}</Badge>;
  };

  if (loading || loadingData) {
    return (
      <DashboardLayout>
        <div className="flex items-center justify-center h-64">
          <div className="animate-spin rounded-full h-8 w-8 border-b-2 border-gray-900" />
        </div>
      </DashboardLayout>
    );
  }

  return (
    <DashboardLayout>
      <div className="space-y-6">
        <div className="flex items-center justify-between">
          <div className="flex items-center gap-4">
            <Button variant="ghost" size="sm" onClick={() => router.push('/communities')}>
              <ArrowLeft className="mr-2 h-4 w-4" />
              Back
            </Button>
            <div>
              <h1 className="text-3xl font-bold">Access Control</h1>
              <p className="text-muted-foreground">Manage trusted vehicle access</p>
            </div>
          </div>
          <Button onClick={() => setShowAddDialog(true)}>
            <Plus className="mr-2 h-4 w-4" />
            Add Vehicle
          </Button>
        </div>

        {settings && (
          <div className="grid gap-4 md:grid-cols-4">
            <Card>
              <CardHeader className="flex flex-row items-center justify-between space-y-0 pb-2">
                <CardTitle className="text-sm font-medium">Auto-Grant</CardTitle>
                <Shield className="h-4 w-4 text-muted-foreground" />
              </CardHeader>
              <CardContent>
                <div className="flex items-center space-x-2">
                  <Switch
                    checked={settings.auto_grant_enabled}
                    onCheckedChange={(checked) =>
                      handleUpdateSettings({ auto_grant_enabled: checked })
                    }
                  />
                  <Label>{settings.auto_grant_enabled ? 'Enabled' : 'Disabled'}</Label>
                </div>
              </CardContent>
            </Card>

            <Card>
              <CardHeader className="flex flex-row items-center justify-between space-y-0 pb-2">
                <CardTitle className="text-sm font-medium">Lockdown Mode</CardTitle>
                <AlertCircle className="h-4 w-4 text-muted-foreground" />
              </CardHeader>
              <CardContent>
                <div className="flex items-center space-x-2">
                  <Switch
                    checked={settings.lockdown_mode}
                    onCheckedChange={(checked) =>
                      handleUpdateSettings({ lockdown_mode: checked })
                    }
                  />
                  <Label className={settings.lockdown_mode ? 'text-red-600' : ''}>
                    {settings.lockdown_mode ? 'Active' : 'Inactive'}
                  </Label>
                </div>
              </CardContent>
            </Card>

            <Card>
              <CardHeader className="flex flex-row items-center justify-between space-y-0 pb-2">
                <CardTitle className="text-sm font-medium">Total Entries</CardTitle>
              </CardHeader>
              <CardContent>
                <div className="text-2xl font-bold">{accessList.length}</div>
                <p className="text-xs text-muted-foreground">
                  {accessList.filter((e) => e.is_active).length} active
                </p>
              </CardContent>
            </Card>

            <Card>
              <CardHeader className="flex flex-row items-center justify-between space-y-0 pb-2">
                <CardTitle className="text-sm font-medium">Min Confidence</CardTitle>
              </CardHeader>
              <CardContent>
                <div className="text-2xl font-bold">{settings.require_confidence}%</div>
                <p className="text-xs text-muted-foreground">Plate detection threshold</p>
              </CardContent>
            </Card>
          </div>
        )}

        <Tabs defaultValue="access-list" className="space-y-4">
          <TabsList>
            <TabsTrigger value="access-list">Access List</TabsTrigger>
            <TabsTrigger value="logs">Access Logs</TabsTrigger>
            <TabsTrigger value="settings">Settings</TabsTrigger>
          </TabsList>

          <TabsContent value="access-list" className="space-y-4">
            <Card>
              <CardHeader>
                <CardTitle>Authorized Vehicles</CardTitle>
                <CardDescription>
                  Manage vehicles with automatic gate access
                </CardDescription>
              </CardHeader>
              <CardContent>
                {accessList.length === 0 ? (
                  <div className="text-center py-12">
                    <Shield className="mx-auto h-12 w-12 text-gray-400" />
                    <h3 className="mt-2 text-sm font-medium">No access entries</h3>
                    <p className="mt-1 text-sm text-muted-foreground">
                      Add vehicles to grant automatic access
                    </p>
                    <Button className="mt-4" onClick={() => setShowAddDialog(true)}>
                      <Plus className="mr-2 h-4 w-4" />
                      Add Vehicle
                    </Button>
                  </div>
                ) : (
                  <Table>
                    <TableHeader>
                      <TableRow>
                        <TableHead>Type</TableHead>
                        <TableHead>Plate</TableHead>
                        <TableHead>Vendor</TableHead>
                        <TableHead>Schedule</TableHead>
                        <TableHead>Days</TableHead>
                        <TableHead>Expires</TableHead>
                        <TableHead>Status</TableHead>
                        <TableHead className="text-right">Actions</TableHead>
                      </TableRow>
                    </TableHeader>
                    <TableBody>
                      {accessList.map((entry) => (
                        <TableRow key={entry.id}>
                          <TableCell>
                            <div className="flex items-center gap-2">
                              {getTypeIcon(entry.type)}
                              <span className="capitalize">{entry.type}</span>
                            </div>
                          </TableCell>
                          <TableCell className="font-mono font-bold">{entry.plate}</TableCell>
                          <TableCell>{entry.vendor_name || '-'}</TableCell>
                          <TableCell>
                            {entry.schedule_start && entry.schedule_end ? (
                              <div className="flex items-center gap-1 text-sm">
                                <Clock className="h-3 w-3" />
                                {entry.schedule_start} - {entry.schedule_end}
                              </div>
                            ) : (
                              '24/7'
                            )}
                          </TableCell>
                          <TableCell>{entry.days_active}</TableCell>
                          <TableCell>
                            {entry.expires_at ? (
                              <div className="flex items-center gap-1 text-sm">
                                <Calendar className="h-3 w-3" />
                                {formatDistanceToNow(new Date(entry.expires_at), {
                                  addSuffix: true,
                                })}
                              </div>
                            ) : (
                              'Never'
                            )}
                          </TableCell>
                          <TableCell>
                            <Switch
                              checked={entry.is_active}
                              onCheckedChange={() => handleToggleActive(entry)}
                            />
                          </TableCell>
                          <TableCell className="text-right">
                            <Button
                              variant="ghost"
                              size="sm"
                              onClick={() => handleDeleteEntry(entry.id)}
                            >
                              <Trash2 className="h-4 w-4" />
                            </Button>
                          </TableCell>
                        </TableRow>
                      ))}
                    </TableBody>
                  </Table>
                )}
              </CardContent>
            </Card>
          </TabsContent>

          <TabsContent value="logs" className="space-y-4">
            <Card>
              <CardHeader>
                <CardTitle>Access Logs</CardTitle>
                <CardDescription>
                  Recent access decisions and gate triggers
                </CardDescription>
              </CardHeader>
              <CardContent>
                <Table>
                  <TableHeader>
                    <TableRow>
                      <TableHead>Time</TableHead>
                      <TableHead>Plate</TableHead>
                      <TableHead>Decision</TableHead>
                      <TableHead>Type</TableHead>
                      <TableHead>Vendor</TableHead>
                      <TableHead>Reason</TableHead>
                      <TableHead>Gate</TableHead>
                    </TableRow>
                  </TableHeader>
                  <TableBody>
                    {logs.map((log) => (
                      <TableRow key={log.id}>
                        <TableCell>
                          {formatDistanceToNow(new Date(log.timestamp), {
                            addSuffix: true,
                          })}
                        </TableCell>
                        <TableCell className="font-mono">{log.plate}</TableCell>
                        <TableCell>{getDecisionBadge(log.decision)}</TableCell>
                        <TableCell className="capitalize">{log.access_type || '-'}</TableCell>
                        <TableCell>{log.vendor_name || '-'}</TableCell>
                        <TableCell className="text-sm text-muted-foreground">
                          {log.reason}
                        </TableCell>
                        <TableCell>
                          {log.gate_triggered ? (
                            <Badge className="bg-green-500">Opened</Badge>
                          ) : (
                            <Badge variant="outline">No</Badge>
                          )}
                        </TableCell>
                      </TableRow>
                    ))}
                  </TableBody>
                </Table>
              </CardContent>
            </Card>
          </TabsContent>

          <TabsContent value="settings" className="space-y-4">
            <Card>
              <CardHeader>
                <CardTitle>Access Control Settings</CardTitle>
                <CardDescription>
                  Configure community-wide access control behavior
                </CardDescription>
              </CardHeader>
              <CardContent className="space-y-4">
                {settings && (
                  <>
                    <div className="space-y-2">
                      <Label>Minimum Plate Confidence (%)</Label>
                      <Input
                        type="number"
                        min="0"
                        max="100"
                        value={settings.require_confidence}
                        onChange={(e) =>
                          handleUpdateSettings({
                            require_confidence: parseFloat(e.target.value),
                          })
                        }
                      />
                      <p className="text-sm text-muted-foreground">
                        Plates below this confidence require manual approval
                      </p>
                    </div>

                    <div className="flex items-center space-x-2">
                      <Switch
                        checked={settings.notification_on_grant}
                        onCheckedChange={(checked) =>
                          handleUpdateSettings({ notification_on_grant: checked })
                        }
                      />
                      <Label>Notify on auto-grant</Label>
                    </div>
                  </>
                )}
              </CardContent>
            </Card>
          </TabsContent>
        </Tabs>

        <Dialog open={showAddDialog} onOpenChange={setShowAddDialog}>
          <DialogContent>
            <DialogHeader>
              <DialogTitle>Add Access Entry</DialogTitle>
              <DialogDescription>
                Add a vehicle to the automatic access list
              </DialogDescription>
            </DialogHeader>
            <div className="space-y-4">
              <div className="space-y-2">
                <Label>License Plate *</Label>
                <Input
                  placeholder="ABC123"
                  value={newEntry.plate}
                  onChange={(e) => setNewEntry({ ...newEntry, plate: e.target.value.toUpperCase() })}
                />
              </div>

              <div className="space-y-2">
                <Label>Type *</Label>
                <Select value={newEntry.type} onValueChange={(value) => setNewEntry({ ...newEntry, type: value })}>
                  <SelectTrigger>
                    <SelectValue />
                  </SelectTrigger>
                  <SelectContent>
                    <SelectItem value="emergency">Emergency</SelectItem>
                    <SelectItem value="delivery">Delivery</SelectItem>
                    <SelectItem value="service">Service</SelectItem>
                    <SelectItem value="contractor">Contractor</SelectItem>
                    <SelectItem value="resident">Resident</SelectItem>
                    <SelectItem value="visitor">Visitor</SelectItem>
                  </SelectContent>
                </Select>
              </div>

              <div className="space-y-2">
                <Label>Vendor Name</Label>
                <Input
                  placeholder="FedEx, Fire Department, etc."
                  value={newEntry.vendor_name}
                  onChange={(e) => setNewEntry({ ...newEntry, vendor_name: e.target.value })}
                />
              </div>

              <div className="grid grid-cols-2 gap-4">
                <div className="space-y-2">
                  <Label>Schedule Start</Label>
                  <Input
                    type="time"
                    value={newEntry.schedule_start}
                    onChange={(e) => setNewEntry({ ...newEntry, schedule_start: e.target.value })}
                  />
                </div>
                <div className="space-y-2">
                  <Label>Schedule End</Label>
                  <Input
                    type="time"
                    value={newEntry.schedule_end}
                    onChange={(e) => setNewEntry({ ...newEntry, schedule_end: e.target.value })}
                  />
                </div>
              </div>

              <div className="space-y-2">
                <Label>Days Active</Label>
                <Input
                  placeholder="Mon-Sun"
                  value={newEntry.days_active}
                  onChange={(e) => setNewEntry({ ...newEntry, days_active: e.target.value })}
                />
              </div>

              <div className="space-y-2">
                <Label>Expires At</Label>
                <Input
                  type="date"
                  value={newEntry.expires_at}
                  onChange={(e) => setNewEntry({ ...newEntry, expires_at: e.target.value })}
                />
              </div>

              <div className="space-y-2">
                <Label>Notes</Label>
                <Input
                  placeholder="Additional notes"
                  value={newEntry.notes}
                  onChange={(e) => setNewEntry({ ...newEntry, notes: e.target.value })}
                />
              </div>
            </div>
            <DialogFooter>
              <Button variant="outline" onClick={() => setShowAddDialog(false)}>
                Cancel
              </Button>
              <Button onClick={handleAddEntry}>Add Entry</Button>
            </DialogFooter>
          </DialogContent>
        </Dialog>
      </div>
    </DashboardLayout>
  );
}
