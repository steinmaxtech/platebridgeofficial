'use client';

import { useState, useEffect } from 'react';
import { useRouter } from 'next/navigation';
import { DashboardLayout } from '@/components/dashboard-layout';
import { useAuth } from '@/lib/auth-context';
import { Card, CardContent, CardDescription, CardHeader, CardTitle } from '@/components/ui/card';
import { Button } from '@/components/ui/button';
import { Badge } from '@/components/ui/badge';
import { Table, TableBody, TableCell, TableHead, TableHeader, TableRow } from '@/components/ui/table';
import { AlertDialog, AlertDialogAction, AlertDialogCancel, AlertDialogContent, AlertDialogDescription, AlertDialogFooter, AlertDialogHeader, AlertDialogTitle } from '@/components/ui/alert-dialog';
import { toast } from 'sonner';
import { Server, Activity, Clock, AlertCircle, RefreshCw, Eye, Cpu, HardDrive, Thermometer, Trash2 } from 'lucide-react';
import { formatDistanceToNow } from 'date-fns';

interface Pod {
  id: string;
  name: string;
  serial_number: string;
  hardware_model: string;
  software_version: string;
  status: 'online' | 'offline' | 'error';
  last_heartbeat: string;
  ip_address: string | null;
  cpu_usage: number | null;
  memory_usage: number | null;
  disk_usage: number | null;
  temperature: number | null;
  site: {
    name: string;
    community: {
      name: string;
    };
  };
  cameras: any[];
  isOnline: boolean;
  lastSeenMinutes: number | null;
  cameraCount: number;
  communityName: string;
  siteName: string;
}

export default function PodsPage() {
  const router = useRouter();
  const { user, loading, effectiveRole } = useAuth();

  const [pods, setPods] = useState<Pod[]>([]);
  const [loadingPods, setLoadingPods] = useState(true);
  const [refreshing, setRefreshing] = useState(false);
  const [autoRefresh, setAutoRefresh] = useState(true);
  const [lastUpdate, setLastUpdate] = useState<Date | null>(null);
  const [deletingPod, setDeletingPod] = useState<string | null>(null);
  const [showDeleteDialog, setShowDeleteDialog] = useState(false);

  useEffect(() => {
    if (!loading && !user) {
      router.push('/login');
    }
  }, [user, loading, router]);

  useEffect(() => {
    if (user) {
      loadPods();
    }
  }, [user]);

  // Auto-refresh every 30 seconds
  useEffect(() => {
    if (!autoRefresh || !user) return;

    const interval = setInterval(() => {
      loadPods();
    }, 30000); // 30 seconds

    return () => clearInterval(interval);
  }, [autoRefresh, user]);

  const loadPods = async (silent = false) => {
    try {
      if (!silent) setLoadingPods(true);

      // Import supabase client
      const { supabase } = await import('@/lib/supabase');

      // Get user's communities through memberships
      const { data: memberships } = await supabase
        .from('memberships')
        .select('company_id')
        .eq('user_id', user!.id);

      if (!memberships || memberships.length === 0) {
        setPods([]);
        setLastUpdate(new Date());
        return;
      }

      const companyIds = memberships.map(m => m.company_id);

      // Get all pods for user's communities
      const { data: pods, error: podsError } = await supabase
        .from('pods')
        .select(`
          *,
          site:sites(
            id,
            name,
            community:communities(
              id,
              name,
              company_id
            )
          ),
          cameras(
            id,
            name,
            status
          )
        `)
        .order('created_at', { ascending: false });

      if (podsError) {
        throw podsError;
      }

      // Filter pods by company_id and enrich data
      const filteredPods = (pods || []).filter(pod =>
        pod.site?.community?.company_id && companyIds.includes(pod.site.community.company_id)
      );

      const enrichedPods = filteredPods.map(pod => {
        const lastSeen = pod.last_heartbeat ? new Date(pod.last_heartbeat) : null;
        const now = new Date();
        const isOnline = lastSeen && (now.getTime() - lastSeen.getTime()) < 5 * 60 * 1000;

        return {
          ...pod,
          isOnline,
          lastSeenMinutes: lastSeen ? Math.floor((now.getTime() - lastSeen.getTime()) / 60000) : null,
          cameraCount: pod.cameras?.length || 0,
          communityName: pod.site?.community?.name || 'Unknown',
          siteName: pod.site?.name || 'Unknown',
        };
      });

      setPods(enrichedPods);
      setLastUpdate(new Date());
    } catch (error) {
      console.error('Error loading pods:', error);
      if (!silent) toast.error('Failed to load PODs');
    } finally {
      if (!silent) setLoadingPods(false);
    }
  };

  const handleRefresh = async () => {
    setRefreshing(true);
    await loadPods();
    setRefreshing(false);
    toast.success('PODs refreshed');
  };

  const toggleAutoRefresh = () => {
    setAutoRefresh(!autoRefresh);
    toast.success(autoRefresh ? 'Auto-refresh disabled' : 'Auto-refresh enabled');
  };

  const handleViewPod = (podId: string) => {
    router.push(`/pods/${podId}`);
  };

  const handleDeletePod = (podId: string) => {
    setDeletingPod(podId);
    setShowDeleteDialog(true);
  };

  const confirmDeletePod = async () => {
    if (!deletingPod) return;

    try {
      const { supabase } = await import('@/lib/supabase');

      // Find the token used to register this pod
      const { data: tokens } = await supabase
        .from('pod_registration_tokens')
        .select('id')
        .eq('pod_id', deletingPod);

      // Delete the pod
      const { error } = await supabase
        .from('pods')
        .delete()
        .eq('id', deletingPod);

      if (error) throw error;

      // Revoke the associated token(s) if any
      if (tokens && tokens.length > 0) {
        await supabase
          .from('pod_registration_tokens')
          .delete()
          .eq('pod_id', deletingPod);

        toast.success(`POD and ${tokens.length} associated token(s) deleted`);
      } else {
        toast.success('POD deleted successfully');
      }

      setShowDeleteDialog(false);
      setDeletingPod(null);

      // Reload pods
      await loadPods();
    } catch (error) {
      console.error('Error deleting pod:', error);
      toast.error('Failed to delete POD');
    }
  };

  const getStatusColor = (status: string, isOnline: boolean) => {
    if (!isOnline) return 'bg-gray-500';
    if (status === 'online') return 'bg-green-500';
    if (status === 'error') return 'bg-red-500';
    return 'bg-yellow-500';
  };

  const getStatusText = (status: string, isOnline: boolean) => {
    if (!isOnline) return 'Offline';
    if (status === 'online') return 'Online';
    if (status === 'error') return 'Error';
    return 'Unknown';
  };

  if (loading || loadingPods) {
    return (
      <DashboardLayout>
        <div className="flex items-center justify-center h-64">
          <div className="animate-spin rounded-full h-8 w-8 border-b-2 border-gray-900" />
        </div>
      </DashboardLayout>
    );
  }

  const onlinePods = pods.filter(p => p.isOnline).length;
  const totalCameras = pods.reduce((sum, p) => sum + p.cameraCount, 0);
  const avgCpu = pods.filter(p => p.cpu_usage !== null).reduce((sum, p) => sum + (p.cpu_usage || 0), 0) / (pods.filter(p => p.cpu_usage !== null).length || 1);

  return (
    <DashboardLayout>
      <div className="space-y-6">
        <div className="flex justify-between items-center">
          <div>
            <h1 className="text-3xl font-bold">POD Management</h1>
            <p className="text-muted-foreground">
              Monitor and manage your edge devices
              {lastUpdate && (
                <span className="ml-2 text-xs">
                  • Last updated {formatDistanceToNow(lastUpdate, { addSuffix: true })}
                </span>
              )}
            </p>
          </div>
          <div className="flex gap-2">
            <Button
              variant={autoRefresh ? "default" : "outline"}
              onClick={toggleAutoRefresh}
              size="sm"
            >
              <Activity className={`mr-2 h-4 w-4 ${autoRefresh ? 'animate-pulse' : ''}`} />
              Auto-refresh {autoRefresh ? 'ON' : 'OFF'}
            </Button>
            <Button
              variant="outline"
              onClick={handleRefresh}
              disabled={refreshing}
            >
              <RefreshCw className={`mr-2 h-4 w-4 ${refreshing ? 'animate-spin' : ''}`} />
              Refresh
            </Button>
          </div>
        </div>

        <div className="grid gap-4 md:grid-cols-4">
          <Card>
            <CardHeader className="flex flex-row items-center justify-between space-y-0 pb-2">
              <CardTitle className="text-sm font-medium">Total PODs</CardTitle>
              <Server className="h-4 w-4 text-muted-foreground" />
            </CardHeader>
            <CardContent>
              <div className="text-2xl font-bold">{pods.length}</div>
              <p className="text-xs text-muted-foreground">
                {onlinePods} online
              </p>
            </CardContent>
          </Card>

          <Card>
            <CardHeader className="flex flex-row items-center justify-between space-y-0 pb-2">
              <CardTitle className="text-sm font-medium">Online Status</CardTitle>
              <Activity className="h-4 w-4 text-muted-foreground" />
            </CardHeader>
            <CardContent>
              <div className="text-2xl font-bold">{Math.round((onlinePods / (pods.length || 1)) * 100)}%</div>
              <p className="text-xs text-muted-foreground">
                Uptime percentage
              </p>
            </CardContent>
          </Card>

          <Card>
            <CardHeader className="flex flex-row items-center justify-between space-y-0 pb-2">
              <CardTitle className="text-sm font-medium">Total Cameras</CardTitle>
              <Eye className="h-4 w-4 text-muted-foreground" />
            </CardHeader>
            <CardContent>
              <div className="text-2xl font-bold">{totalCameras}</div>
              <p className="text-xs text-muted-foreground">
                Across all PODs
              </p>
            </CardContent>
          </Card>

          <Card>
            <CardHeader className="flex flex-row items-center justify-between space-y-0 pb-2">
              <CardTitle className="text-sm font-medium">Avg CPU Usage</CardTitle>
              <Cpu className="h-4 w-4 text-muted-foreground" />
            </CardHeader>
            <CardContent>
              <div className="text-2xl font-bold">{Math.round(avgCpu)}%</div>
              <p className="text-xs text-muted-foreground">
                System performance
              </p>
            </CardContent>
          </Card>
        </div>

        <Card>
          <CardHeader>
            <CardTitle>All PODs</CardTitle>
            <CardDescription>
              Monitor status and health of all connected PODs
            </CardDescription>
          </CardHeader>
          <CardContent>
            {pods.length === 0 ? (
              <div className="text-center py-12">
                <Server className="mx-auto h-12 w-12 text-gray-400" />
                <h3 className="mt-2 text-sm font-medium">No PODs registered</h3>
                <p className="mt-1 text-sm text-muted-foreground">
                  Register your first POD to get started
                </p>
              </div>
            ) : (
              <div className="overflow-x-auto">
                <Table>
                  <TableHeader>
                    <TableRow>
                      <TableHead>Status</TableHead>
                      <TableHead>POD Name</TableHead>
                      <TableHead>Community</TableHead>
                      <TableHead>Site</TableHead>
                      <TableHead>Cameras</TableHead>
                      <TableHead>CPU</TableHead>
                      <TableHead>Memory</TableHead>
                      <TableHead>Disk</TableHead>
                      <TableHead>Temp</TableHead>
                      <TableHead>Last Seen</TableHead>
                      <TableHead>Version</TableHead>
                      <TableHead className="text-right">Actions</TableHead>
                    </TableRow>
                  </TableHeader>
                  <TableBody>
                    {pods.map((pod) => (
                      <TableRow key={pod.id} className="hover:bg-muted/50">
                        <TableCell>
                          <div className="flex items-center gap-2">
                            <div className={`h-2 w-2 rounded-full ${getStatusColor(pod.status, pod.isOnline)}`} />
                            <span className="text-sm">{getStatusText(pod.status, pod.isOnline)}</span>
                          </div>
                        </TableCell>
                        <TableCell className="font-medium">
                          <div>
                            <div>{pod.name}</div>
                            <div className="text-xs text-muted-foreground">{pod.serial_number}</div>
                          </div>
                        </TableCell>
                        <TableCell>{pod.communityName}</TableCell>
                        <TableCell>{pod.siteName}</TableCell>
                        <TableCell>
                          <Badge variant="outline">{pod.cameraCount}</Badge>
                        </TableCell>
                        <TableCell>
                          {pod.cpu_usage !== null ? (
                            <div className="flex items-center gap-1">
                              <Cpu className="h-3 w-3 text-muted-foreground" />
                              <span>{Math.round(pod.cpu_usage)}%</span>
                            </div>
                          ) : (
                            <span className="text-muted-foreground">-</span>
                          )}
                        </TableCell>
                        <TableCell>
                          {pod.memory_usage !== null ? `${Math.round(pod.memory_usage)}%` : '-'}
                        </TableCell>
                        <TableCell>
                          {pod.disk_usage !== null ? (
                            <div className="flex items-center gap-1">
                              <HardDrive className="h-3 w-3 text-muted-foreground" />
                              <span>{Math.round(pod.disk_usage)}%</span>
                            </div>
                          ) : (
                            <span className="text-muted-foreground">-</span>
                          )}
                        </TableCell>
                        <TableCell>
                          {pod.temperature !== null ? (
                            <div className="flex items-center gap-1">
                              <Thermometer className="h-3 w-3 text-muted-foreground" />
                              <span>{Math.round(pod.temperature)}°C</span>
                            </div>
                          ) : (
                            <span className="text-muted-foreground">-</span>
                          )}
                        </TableCell>
                        <TableCell>
                          <div className="flex items-center gap-1 text-sm">
                            <Clock className="h-3 w-3 text-muted-foreground" />
                            {pod.lastSeenMinutes !== null ? (
                              pod.lastSeenMinutes < 5 ? (
                                <span className="text-green-600">Just now</span>
                              ) : (
                                <span>{formatDistanceToNow(new Date(pod.last_heartbeat), { addSuffix: true })}</span>
                              )
                            ) : (
                              <span className="text-muted-foreground">Never</span>
                            )}
                          </div>
                        </TableCell>
                        <TableCell>
                          <Badge variant="secondary">{pod.software_version}</Badge>
                        </TableCell>
                        <TableCell className="text-right">
                          <div className="flex justify-end gap-2">
                            <Button
                              variant="ghost"
                              size="sm"
                              onClick={() => handleViewPod(pod.id)}
                            >
                              View Details
                            </Button>
                            <Button
                              variant="ghost"
                              size="sm"
                              onClick={() => handleDeletePod(pod.id)}
                              className="text-red-600 hover:text-red-700 hover:bg-red-50"
                            >
                              <Trash2 className="h-4 w-4" />
                            </Button>
                          </div>
                        </TableCell>
                      </TableRow>
                    ))}
                  </TableBody>
                </Table>
              </div>
            )}
          </CardContent>
        </Card>
      </div>

      <AlertDialog open={showDeleteDialog} onOpenChange={setShowDeleteDialog}>
        <AlertDialogContent>
          <AlertDialogHeader>
            <AlertDialogTitle>Delete POD</AlertDialogTitle>
            <AlertDialogDescription>
              Are you sure you want to delete this POD? This action cannot be undone.
              All associated cameras, recordings, and registration tokens will be removed.
            </AlertDialogDescription>
          </AlertDialogHeader>
          <AlertDialogFooter>
            <AlertDialogCancel onClick={() => setDeletingPod(null)}>
              Cancel
            </AlertDialogCancel>
            <AlertDialogAction
              onClick={confirmDeletePod}
              className="bg-red-600 hover:bg-red-700"
            >
              Delete POD
            </AlertDialogAction>
          </AlertDialogFooter>
        </AlertDialogContent>
      </AlertDialog>
    </DashboardLayout>
  );
}
