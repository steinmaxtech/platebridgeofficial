'use client';

import { useState, useEffect } from 'react';
import { useRouter, useParams } from 'next/navigation';
import { DashboardLayout } from '@/components/dashboard-layout';
import { useAuth } from '@/lib/auth-context';
import { Card, CardContent, CardDescription, CardHeader, CardTitle } from '@/components/ui/card';
import { Button } from '@/components/ui/button';
import { Badge } from '@/components/ui/badge';
import { Tabs, TabsContent, TabsList, TabsTrigger } from '@/components/ui/tabs';
import { Table, TableBody, TableCell, TableHead, TableHeader, TableRow } from '@/components/ui/table';
import { Alert, AlertDescription } from '@/components/ui/alert';
import { toast } from 'sonner';
import {
  ArrowLeft, Server, Activity, Clock, Download, RotateCw,
  Power, RefreshCcw, AlertCircle, CheckCircle2, Eye,
  Cpu, HardDrive, Thermometer, Network, Terminal
} from 'lucide-react';
import { formatDistanceToNow, format } from 'date-fns';

interface Command {
  id: string;
  command: string;
  status: string;
  parameters: any;
  result: any;
  error_message: string | null;
  created_at: string;
  executed_at: string | null;
  completed_at: string | null;
}

interface Detection {
  id: string;
  plate: string;
  confidence: number;
  detected_at: string;
  camera_id: string;
  image_url: string | null;
}

export default function PodDetailPage() {
  const router = useRouter();
  const params = useParams();
  const podId = params?.id as string;
  const { user, loading } = useAuth();

  const [pod, setPod] = useState<any>(null);
  const [stats, setStats] = useState<any>(null);
  const [detections, setDetections] = useState<Detection[]>([]);
  const [commands, setCommands] = useState<Command[]>([]);
  const [loadingPod, setLoadingPod] = useState(true);
  const [sendingCommand, setSendingCommand] = useState(false);

  useEffect(() => {
    if (!loading && !user) {
      router.push('/login');
    }
  }, [user, loading, router]);

  useEffect(() => {
    if (user && podId) {
      loadPodDetails();
    }
  }, [user, podId]);

  const loadPodDetails = async () => {
    try {
      setLoadingPod(true);
      const response = await fetch(`/api/pods/${podId}`);

      if (!response.ok) {
        throw new Error('Failed to fetch POD details');
      }

      const data = await response.json();
      setPod(data.pod);
      setStats(data.stats);
      setDetections(data.detections);
      setCommands(data.commands);
    } catch (error) {
      console.error('Error loading POD:', error);
      toast.error('Failed to load POD details');
    } finally {
      setLoadingPod(false);
    }
  };

  const sendCommand = async (command: string, parameters = {}) => {
    try {
      setSendingCommand(true);

      const response = await fetch(`/api/pods/${podId}/command`, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ command, parameters }),
      });

      if (!response.ok) {
        const error = await response.json();
        throw new Error(error.error || 'Failed to send command');
      }

      toast.success(`Command '${command}' sent successfully`);
      await loadPodDetails();
    } catch (error: any) {
      console.error('Error sending command:', error);
      toast.error(error.message || 'Failed to send command');
    } finally {
      setSendingCommand(false);
    }
  };

  const downloadConfig = async (format: 'compose' | 'env') => {
    try {
      const response = await fetch(`/api/pods/config/${podId}?format=${format}`);
      const blob = await response.blob();
      const url = window.URL.createObjectURL(blob);
      const a = document.createElement('a');
      a.href = url;
      a.download = format === 'compose' ? 'docker-compose.yml' : '.env';
      document.body.appendChild(a);
      a.click();
      window.URL.revokeObjectURL(url);
      document.body.removeChild(a);
      toast.success(`Downloaded ${format === 'compose' ? 'docker-compose.yml' : '.env'}`);
    } catch (error) {
      toast.error('Failed to download configuration');
    }
  };

  if (loading || loadingPod) {
    return (
      <DashboardLayout>
        <div className="flex items-center justify-center h-64">
          <div className="animate-spin rounded-full h-8 w-8 border-b-2 border-gray-900" />
        </div>
      </DashboardLayout>
    );
  }

  if (!pod) {
    return (
      <DashboardLayout>
        <Alert>
          <AlertCircle className="h-4 w-4" />
          <AlertDescription>POD not found</AlertDescription>
        </Alert>
      </DashboardLayout>
    );
  }

  const isOnline = stats?.isOnline;

  return (
    <DashboardLayout>
      <div className="space-y-6">
        <div className="flex items-center justify-between">
          <div className="flex items-center gap-4">
            <Button variant="ghost" size="sm" onClick={() => router.push('/pods')}>
              <ArrowLeft className="mr-2 h-4 w-4" />
              Back
            </Button>
            <div>
              <div className="flex items-center gap-2">
                <h1 className="text-3xl font-bold">{pod.name}</h1>
                <Badge variant={isOnline ? 'default' : 'secondary'}>
                  {isOnline ? 'Online' : 'Offline'}
                </Badge>
              </div>
              <p className="text-muted-foreground">{pod.serial_number}</p>
            </div>
          </div>
          <div className="flex gap-2">
            <Button variant="outline" onClick={loadPodDetails}>
              <RefreshCcw className="mr-2 h-4 w-4" />
              Refresh
            </Button>
          </div>
        </div>

        <div className="grid gap-4 md:grid-cols-4">
          <Card>
            <CardHeader className="flex flex-row items-center justify-between space-y-0 pb-2">
              <CardTitle className="text-sm font-medium">Status</CardTitle>
              <Activity className="h-4 w-4 text-muted-foreground" />
            </CardHeader>
            <CardContent>
              <div className="text-2xl font-bold">{isOnline ? 'Online' : 'Offline'}</div>
              <p className="text-xs text-muted-foreground">
                {stats?.lastSeenMinutes !== null
                  ? `Last seen ${formatDistanceToNow(new Date(pod.last_heartbeat), { addSuffix: true })}`
                  : 'Never seen'}
              </p>
            </CardContent>
          </Card>

          <Card>
            <CardHeader className="flex flex-row items-center justify-between space-y-0 pb-2">
              <CardTitle className="text-sm font-medium">Cameras</CardTitle>
              <Eye className="h-4 w-4 text-muted-foreground" />
            </CardHeader>
            <CardContent>
              <div className="text-2xl font-bold">{stats?.cameraCount || 0}</div>
              <p className="text-xs text-muted-foreground">
                {stats?.activeCameras || 0} active
              </p>
            </CardContent>
          </Card>

          <Card>
            <CardHeader className="flex flex-row items-center justify-between space-y-0 pb-2">
              <CardTitle className="text-sm font-medium">Detections (24h)</CardTitle>
              <Activity className="h-4 w-4 text-muted-foreground" />
            </CardHeader>
            <CardContent>
              <div className="text-2xl font-bold">{stats?.detections24h || 0}</div>
              <p className="text-xs text-muted-foreground">
                Plates detected today
              </p>
            </CardContent>
          </Card>

          <Card>
            <CardHeader className="flex flex-row items-center justify-between space-y-0 pb-2">
              <CardTitle className="text-sm font-medium">Commands</CardTitle>
              <Terminal className="h-4 w-4 text-muted-foreground" />
            </CardHeader>
            <CardContent>
              <div className="text-2xl font-bold">{stats?.pendingCommands || 0}</div>
              <p className="text-xs text-muted-foreground">
                Pending execution
              </p>
            </CardContent>
          </Card>
        </div>

        <div className="grid gap-4 md:grid-cols-2">
          <Card>
            <CardHeader>
              <CardTitle>Hardware Info</CardTitle>
            </CardHeader>
            <CardContent className="space-y-2">
              <div className="flex justify-between">
                <span className="text-sm text-muted-foreground">Model:</span>
                <span className="font-medium">{pod.hardware_model || 'Unknown'}</span>
              </div>
              <div className="flex justify-between">
                <span className="text-sm text-muted-foreground">Software:</span>
                <span className="font-medium">{pod.software_version}</span>
              </div>
              <div className="flex justify-between">
                <span className="text-sm text-muted-foreground">IP Address:</span>
                <span className="font-medium">{pod.ip_address || 'N/A'}</span>
              </div>
              <div className="flex justify-between">
                <span className="text-sm text-muted-foreground">MAC:</span>
                <span className="font-medium">{pod.mac_address || 'N/A'}</span>
              </div>
            </CardContent>
          </Card>

          <Card>
            <CardHeader>
              <CardTitle>System Metrics</CardTitle>
            </CardHeader>
            <CardContent className="space-y-2">
              <div className="flex justify-between items-center">
                <span className="text-sm text-muted-foreground flex items-center gap-2">
                  <Cpu className="h-4 w-4" />
                  CPU Usage:
                </span>
                <span className="font-medium">{pod.cpu_usage ? `${Math.round(pod.cpu_usage)}%` : 'N/A'}</span>
              </div>
              <div className="flex justify-between">
                <span className="text-sm text-muted-foreground">Memory:</span>
                <span className="font-medium">{pod.memory_usage ? `${Math.round(pod.memory_usage)}%` : 'N/A'}</span>
              </div>
              <div className="flex justify-between items-center">
                <span className="text-sm text-muted-foreground flex items-center gap-2">
                  <HardDrive className="h-4 w-4" />
                  Disk Usage:
                </span>
                <span className="font-medium">{pod.disk_usage ? `${Math.round(pod.disk_usage)}%` : 'N/A'}</span>
              </div>
              <div className="flex justify-between items-center">
                <span className="text-sm text-muted-foreground flex items-center gap-2">
                  <Thermometer className="h-4 w-4" />
                  Temperature:
                </span>
                <span className="font-medium">{pod.temperature ? `${Math.round(pod.temperature)}°C` : 'N/A'}</span>
              </div>
            </CardContent>
          </Card>
        </div>

        <Card>
          <CardHeader>
            <CardTitle>Quick Actions</CardTitle>
            <CardDescription>Remote control commands for this POD</CardDescription>
          </CardHeader>
          <CardContent>
            <div className="grid gap-2 md:grid-cols-3">
              <Button
                variant="outline"
                onClick={() => sendCommand('restart')}
                disabled={sendingCommand}
              >
                <RotateCw className="mr-2 h-4 w-4" />
                Restart Services
              </Button>
              <Button
                variant="outline"
                onClick={() => sendCommand('reboot')}
                disabled={sendingCommand}
              >
                <Power className="mr-2 h-4 w-4" />
                Reboot Device
              </Button>
              <Button
                variant="outline"
                onClick={() => sendCommand('refresh_config')}
                disabled={sendingCommand}
              >
                <RefreshCcw className="mr-2 h-4 w-4" />
                Refresh Config
              </Button>
              <Button
                variant="outline"
                onClick={() => downloadConfig('compose')}
              >
                <Download className="mr-2 h-4 w-4" />
                Download Compose
              </Button>
              <Button
                variant="outline"
                onClick={() => downloadConfig('env')}
              >
                <Download className="mr-2 h-4 w-4" />
                Download .env
              </Button>
            </div>
          </CardContent>
        </Card>

        <Tabs defaultValue="cameras" className="space-y-4">
          <TabsList>
            <TabsTrigger value="cameras">Cameras</TabsTrigger>
            <TabsTrigger value="detections">Recent Detections</TabsTrigger>
            <TabsTrigger value="commands">Command History</TabsTrigger>
          </TabsList>

          <TabsContent value="cameras" className="space-y-4">
            <Card>
              <CardHeader>
                <CardTitle>Connected Cameras</CardTitle>
                <CardDescription>Cameras configured on this POD</CardDescription>
              </CardHeader>
              <CardContent>
                {pod.cameras && pod.cameras.length > 0 ? (
                  <Table>
                    <TableHeader>
                      <TableRow>
                        <TableHead>Name</TableHead>
                        <TableHead>Status</TableHead>
                        <TableHead>Position</TableHead>
                        <TableHead>Last Recording</TableHead>
                      </TableRow>
                    </TableHeader>
                    <TableBody>
                      {pod.cameras.map((camera: any) => (
                        <TableRow key={camera.id}>
                          <TableCell className="font-medium">{camera.name}</TableCell>
                          <TableCell>
                            <Badge variant={camera.status === 'active' ? 'default' : 'secondary'}>
                              {camera.status}
                            </Badge>
                          </TableCell>
                          <TableCell>{camera.position || 'N/A'}</TableCell>
                          <TableCell>
                            {camera.last_recording_at
                              ? formatDistanceToNow(new Date(camera.last_recording_at), { addSuffix: true })
                              : 'Never'}
                          </TableCell>
                        </TableRow>
                      ))}
                    </TableBody>
                  </Table>
                ) : (
                  <div className="text-center py-8 text-muted-foreground">
                    No cameras configured
                  </div>
                )}
              </CardContent>
            </Card>
          </TabsContent>

          <TabsContent value="detections" className="space-y-4">
            <Card>
              <CardHeader>
                <CardTitle>Recent Detections</CardTitle>
                <CardDescription>Last 50 plate detections (24 hours)</CardDescription>
              </CardHeader>
              <CardContent>
                {detections.length > 0 ? (
                  <Table>
                    <TableHeader>
                      <TableRow>
                        <TableHead>Plate</TableHead>
                        <TableHead>Confidence</TableHead>
                        <TableHead>Detected At</TableHead>
                      </TableRow>
                    </TableHeader>
                    <TableBody>
                      {detections.map((detection) => (
                        <TableRow key={detection.id}>
                          <TableCell className="font-medium">{detection.plate}</TableCell>
                          <TableCell>
                            <Badge variant={detection.confidence > 0.9 ? 'default' : 'secondary'}>
                              {Math.round(detection.confidence * 100)}%
                            </Badge>
                          </TableCell>
                          <TableCell>
                            {format(new Date(detection.detected_at), 'MMM d, yyyy h:mm a')}
                          </TableCell>
                        </TableRow>
                      ))}
                    </TableBody>
                  </Table>
                ) : (
                  <div className="text-center py-8 text-muted-foreground">
                    No detections in last 24 hours
                  </div>
                )}
              </CardContent>
            </Card>
          </TabsContent>

          <TabsContent value="commands" className="space-y-4">
            <Card>
              <CardHeader>
                <CardTitle>Command History</CardTitle>
                <CardDescription>Recent commands sent to this POD</CardDescription>
              </CardHeader>
              <CardContent>
                {commands.length > 0 ? (
                  <Table>
                    <TableHeader>
                      <TableRow>
                        <TableHead>Command</TableHead>
                        <TableHead>Status</TableHead>
                        <TableHead>Created</TableHead>
                        <TableHead>Executed</TableHead>
                      </TableRow>
                    </TableHeader>
                    <TableBody>
                      {commands.map((cmd) => (
                        <TableRow key={cmd.id}>
                          <TableCell className="font-medium">{cmd.command}</TableCell>
                          <TableCell>
                            <Badge
                              variant={
                                cmd.status === 'completed' ? 'default' :
                                cmd.status === 'failed' ? 'destructive' :
                                'secondary'
                              }
                            >
                              {cmd.status}
                            </Badge>
                          </TableCell>
                          <TableCell>
                            {format(new Date(cmd.created_at), 'MMM d, h:mm a')}
                          </TableCell>
                          <TableCell>
                            {cmd.executed_at
                              ? format(new Date(cmd.executed_at), 'MMM d, h:mm a')
                              : '-'}
                          </TableCell>
                        </TableRow>
                      ))}
                    </TableBody>
                  </Table>
                ) : (
                  <div className="text-center py-8 text-muted-foreground">
                    No command history
                  </div>
                )}
              </CardContent>
            </Card>
          </TabsContent>
        </Tabs>
      </div>
    </DashboardLayout>
  );
}
