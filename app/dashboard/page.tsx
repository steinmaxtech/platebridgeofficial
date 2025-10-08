'use client';

import { useEffect, useState } from 'react';
import { useAuth } from '@/lib/auth-context';
import { useCompany } from '@/lib/community-context';
import { useRouter } from 'next/navigation';
import { DashboardLayout } from '@/components/dashboard-layout';
import { Card } from '@/components/ui/card';
import { Table, TableBody, TableCell, TableHead, TableHeader, TableRow } from '@/components/ui/table';
import { supabase } from '@/lib/supabase';
import { Activity, Wifi, Camera, Car, CheckCircle2, AlertCircle, XCircle } from 'lucide-react';
import { AnimatedCard, FadeIn, SlideIn } from '@/components/animated-card';

interface SystemMetrics {
  total_pods: number;
  pods_online: number;
  total_cameras: number;
  cameras_active: number;
  plates_detected_24h: number;
  gatewise_connected: boolean;
  uptime_percentage: number;
  last_sync?: string;
}

interface GatewiseHealth {
  status: 'healthy' | 'unhealthy';
  statusCode: number;
  enabled: boolean;
}

interface PodHealth {
  id: string;
  pod_name: string;
  status: 'online' | 'warning' | 'offline' | 'error';
  last_checkin: string | null;
  camera_count: number;
  plates_detected_24h: number;
  sites: {
    name: string;
  };
}

interface Company {
  name: string;
  logo_url: string | null;
  uptime_sla: number;
}

export default function DashboardPage() {
  const { user, profile, loading, effectiveRole } = useAuth();
  const { activeCompanyId } = useCompany();
  const router = useRouter();
  const [metrics, setMetrics] = useState<SystemMetrics | null>(null);
  const [pods, setPods] = useState<PodHealth[]>([]);
  const [company, setCompany] = useState<Company | null>(null);
  const [loadingData, setLoadingData] = useState(true);
  const [gatewiseHealth, setGatewiseHealth] = useState<GatewiseHealth | null>(null);

  useEffect(() => {
    if (!loading && !user) {
      router.push('/login');
    }
  }, [user, loading, router]);

  useEffect(() => {
    if (user && profile && activeCompanyId) {
      fetchDashboardData();
      fetchGatewiseHealth();
    }
  }, [user, profile, activeCompanyId]);

  const fetchDashboardData = async () => {
    if (!activeCompanyId) return;
    setLoadingData(true);

    const { data: companyData } = await supabase
      .from('companies')
      .select('name, logo_url, uptime_sla')
      .eq('id', activeCompanyId)
      .single();

    if (companyData) {
      setCompany(companyData);
    }

    const { data: metricsData } = await supabase
      .from('system_metrics')
      .select('*')
      .eq('company_id', activeCompanyId)
      .order('metric_date', { ascending: false })
      .limit(1)
      .maybeSingle();

    if (metricsData) {
      setMetrics(metricsData);
    } else {
      setMetrics({
        total_pods: 0,
        pods_online: 0,
        total_cameras: 0,
        cameras_active: 0,
        plates_detected_24h: 0,
        gatewise_connected: false,
        uptime_percentage: 100,
      });
    }

    if (effectiveRole !== 'resident') {
      const { data: podsData } = await supabase
        .from('pod_health')
        .select(`
          id,
          pod_name,
          status,
          last_checkin,
          camera_count,
          plates_detected_24h,
          sites!inner (
            name,
            communities!inner (
              company_id
            )
          )
        `)
        .eq('sites.communities.company_id', activeCompanyId)
        .order('pod_name');

      if (podsData) {
        setPods(podsData as any);
      }
    }

    setLoadingData(false);
  };

  const fetchGatewiseHealth = async () => {
    try {
      const healthResponse = await fetch('/api/gatewise/health');
      const healthData = await healthResponse.json();

      const { data: communities } = await supabase
        .from('communities')
        .select('id')
        .eq('company_id', activeCompanyId);

      let isEnabled = false;
      if (communities && communities.length > 0) {
        const { data: configData } = await supabase
          .from('gatewise_config')
          .select('enabled')
          .in('community_id', communities.map(c => c.id))
          .eq('enabled', true)
          .limit(1)
          .maybeSingle();

        isEnabled = !!configData;
      }

      setGatewiseHealth({
        status: healthData.status,
        statusCode: healthData.statusCode,
        enabled: isEnabled,
      });
    } catch (error) {
      console.error('Error fetching Gatewise health:', error);
      setGatewiseHealth({
        status: 'unhealthy',
        statusCode: 0,
        enabled: false,
      });
    }
  };

  const getStatusIcon = (status: string) => {
    switch (status) {
      case 'online':
        return <CheckCircle2 className="w-5 h-5 text-green-500" />;
      case 'warning':
        return <AlertCircle className="w-5 h-5 text-yellow-500" />;
      case 'offline':
      case 'error':
        return <XCircle className="w-5 h-5 text-red-500" />;
      default:
        return <XCircle className="w-5 h-5 text-gray-500" />;
    }
  };

  const getStatusColor = (status: string) => {
    switch (status) {
      case 'online':
        return 'text-green-600 dark:text-green-400';
      case 'warning':
        return 'text-yellow-600 dark:text-yellow-400';
      case 'offline':
      case 'error':
        return 'text-red-600 dark:text-red-400';
      default:
        return 'text-gray-600 dark:text-gray-400';
    }
  };

  const formatLastCheckin = (timestamp: string | null) => {
    if (!timestamp) return 'Never';
    const date = new Date(timestamp);
    const now = new Date();
    const diffMs = now.getTime() - date.getTime();
    const diffMins = Math.floor(diffMs / 60000);

    if (diffMins < 1) return 'Just now';
    if (diffMins < 60) return `${diffMins} min ago`;
    const diffHours = Math.floor(diffMins / 60);
    if (diffHours < 24) return `${diffHours}h ago`;
    return date.toLocaleDateString();
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
      <div className="max-w-7xl mx-auto space-y-8">
        <FadeIn>
          <div className="flex items-start justify-between">
            <div>
              <h2 className="text-3xl font-bold mb-2">
                Welcome back, {user.email?.split('@')[0] || 'User'}!
              </h2>
              <p className="text-muted-foreground text-lg">
                {company?.name || 'Your'} Access Control system is {metrics?.uptime_percentage === 100 ? 'running smoothly' : 'operational'}
                {metrics && metrics.pods_online > 0 && ` — ${metrics.pods_online} pod${metrics.pods_online > 1 ? 's' : ''} online`}
              </p>
              {metrics && (
                <div className="mt-3 flex items-center gap-6 text-sm">
                  <div className="flex items-center gap-2">
                    <Activity className="w-4 h-4 text-green-500" />
                    <span className="text-muted-foreground">System Health:</span>
                    <span className="font-semibold">{metrics.uptime_percentage}% operational</span>
                  </div>
                  {metrics.last_sync && (
                    <div className="flex items-center gap-2">
                      <span className="text-muted-foreground">Last sync:</span>
                      <span className="font-semibold">{formatLastCheckin(metrics.last_sync)}</span>
                    </div>
                  )}
                </div>
              )}
            </div>
            {company?.logo_url && (
              <img src={company.logo_url} alt="Company Logo" className="h-16 w-auto rounded-lg" />
            )}
          </div>
        </FadeIn>

        {loadingData ? (
          <div className="text-center py-12">
            <div className="text-lg text-muted-foreground">Loading dashboard...</div>
          </div>
        ) : (
          <>
            <div className="grid grid-cols-2 md:grid-cols-3 lg:grid-cols-5 gap-4">
              <AnimatedCard delay={0.1} className="p-6 rounded-2xl shadow-sm bg-white dark:bg-[#2D3748]">
                <div className="flex items-center justify-between mb-2">
                  <Wifi className="w-5 h-5 text-blue-500" />
                  <span className={`text-xs font-medium ${metrics && metrics.pods_online === metrics.total_pods ? 'text-green-600 dark:text-green-400' : 'text-yellow-600 dark:text-yellow-400'}`}>
                    {metrics && metrics.total_pods > 0 ? `${Math.round((metrics.pods_online / metrics.total_pods) * 100)}%` : '—'}
                  </span>
                </div>
                <h3 className="text-sm text-muted-foreground mb-1">Pods Online</h3>
                <p className="text-2xl font-semibold">
                  {metrics?.pods_online || 0} / {metrics?.total_pods || 0}
                </p>
              </AnimatedCard>

              <AnimatedCard delay={0.15} className="p-6 rounded-2xl shadow-sm bg-white dark:bg-[#2D3748]">
                <div className="flex items-center justify-between mb-2">
                  {gatewiseHealth?.status === 'healthy' && gatewiseHealth?.enabled ? (
                    <CheckCircle2 className="w-5 h-5 text-green-500" />
                  ) : gatewiseHealth?.enabled ? (
                    <AlertCircle className="w-5 h-5 text-yellow-500" />
                  ) : (
                    <XCircle className="w-5 h-5 text-gray-500" />
                  )}
                  <span className={`text-xs font-medium ${
                    gatewiseHealth?.status === 'healthy' && gatewiseHealth?.enabled
                      ? 'text-green-600 dark:text-green-400'
                      : gatewiseHealth?.enabled
                      ? 'text-yellow-600 dark:text-yellow-400'
                      : 'text-gray-600 dark:text-gray-400'
                  }`}>
                    {!gatewiseHealth?.enabled ? 'Disabled' : gatewiseHealth?.status === 'healthy' ? 'Connected' : 'API Down'}
                  </span>
                </div>
                <h3 className="text-sm text-muted-foreground mb-1">Gatewise</h3>
                <p className="text-2xl font-semibold">
                  {!gatewiseHealth?.enabled ? 'Off' : gatewiseHealth?.status === 'healthy' ? 'Active' : 'Error'}
                </p>
              </AnimatedCard>

              <AnimatedCard delay={0.2} className="p-6 rounded-2xl shadow-sm bg-white dark:bg-[#2D3748]">
                <div className="flex items-center justify-between mb-2">
                  <Camera className="w-5 h-5 text-purple-500" />
                  <span className={`text-xs font-medium ${metrics && metrics.cameras_active === metrics.total_cameras ? 'text-green-600 dark:text-green-400' : 'text-yellow-600 dark:text-yellow-400'}`}>
                    Active
                  </span>
                </div>
                <h3 className="text-sm text-muted-foreground mb-1">Camera Feeds</h3>
                <p className="text-2xl font-semibold">
                  {metrics?.cameras_active || 0} / {metrics?.total_cameras || 0}
                </p>
              </AnimatedCard>

              <AnimatedCard delay={0.25} className="p-6 rounded-2xl shadow-sm bg-white dark:bg-[#2D3748]">
                <div className="flex items-center justify-between mb-2">
                  <Car className="w-5 h-5 text-cyan-500" />
                  <span className="text-xs font-medium text-blue-600 dark:text-blue-400">24h</span>
                </div>
                <h3 className="text-sm text-muted-foreground mb-1">Plates Detected</h3>
                <p className="text-2xl font-semibold">{metrics?.plates_detected_24h || 0}</p>
              </AnimatedCard>

              <AnimatedCard delay={0.3} className="p-6 rounded-2xl shadow-sm bg-white dark:bg-[#2D3748]">
                <div className="flex items-center justify-between mb-2">
                  <Activity className="w-5 h-5 text-green-500" />
                  <span className="text-xs font-medium text-green-600 dark:text-green-400">
                    {company?.uptime_sla || 99.9}% SLA
                  </span>
                </div>
                <h3 className="text-sm text-muted-foreground mb-1">System Health</h3>
                <p className="text-2xl font-semibold">{metrics?.uptime_percentage || 100}%</p>
              </AnimatedCard>
            </div>

            {effectiveRole !== 'resident' && pods.length > 0 && (
              <SlideIn delay={0.4} direction="up">
                <Card className="p-6 shadow-lg border-0 bg-white dark:bg-[#2D3748]">
                  <h3 className="text-xl font-bold mb-4">Pod Status</h3>
                  <Table>
                    <TableHeader>
                      <TableRow>
                        <TableHead>Pod Name</TableHead>
                        <TableHead>Location</TableHead>
                        <TableHead>Status</TableHead>
                        <TableHead>Cameras</TableHead>
                        <TableHead>Plates (24h)</TableHead>
                        <TableHead>Last Check-In</TableHead>
                      </TableRow>
                    </TableHeader>
                    <TableBody>
                      {pods.map((pod) => (
                        <TableRow key={pod.id}>
                          <TableCell className="font-medium">{pod.pod_name}</TableCell>
                          <TableCell>{pod.sites?.name || '—'}</TableCell>
                          <TableCell>
                            <div className="flex items-center gap-2">
                              {getStatusIcon(pod.status)}
                              <span className={`capitalize font-medium ${getStatusColor(pod.status)}`}>
                                {pod.status}
                              </span>
                            </div>
                          </TableCell>
                          <TableCell>{pod.camera_count || 0}</TableCell>
                          <TableCell>{pod.plates_detected_24h || 0}</TableCell>
                          <TableCell className="text-muted-foreground">
                            {formatLastCheckin(pod.last_checkin)}
                          </TableCell>
                        </TableRow>
                      ))}
                    </TableBody>
                  </Table>
                </Card>
              </SlideIn>
            )}

            {effectiveRole === 'resident' && (
              <SlideIn delay={0.2} direction="up">
                <Card className="p-8 rounded-3xl shadow-lg bg-gradient-to-br from-blue-50 to-cyan-50 dark:from-blue-950/30 dark:to-cyan-950/30">
                  <h3 className="text-xl font-bold mb-3">Welcome to PlateBridge</h3>
                  <p className="text-muted-foreground leading-relaxed">
                    View and manage your registered vehicles from the Plates section.
                    Your community access system is operating normally.
                  </p>
                </Card>
              </SlideIn>
            )}
          </>
        )}
      </div>
    </DashboardLayout>
  );
}
