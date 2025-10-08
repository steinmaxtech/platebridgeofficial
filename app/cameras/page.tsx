'use client';

import { useEffect, useState } from 'react';
import { useAuth } from '@/lib/auth-context';
import { useCompany } from '@/lib/community-context';
import { useRouter } from 'next/navigation';
import { DashboardLayout } from '@/components/dashboard-layout';
import { Card } from '@/components/ui/card';
import { Button } from '@/components/ui/button';
import { Badge } from '@/components/ui/badge';
import { supabase } from '@/lib/supabase';
import { Camera, Video, VideoOff, Play, AlertCircle, CheckCircle2, Maximize2 } from 'lucide-react';
import { AnimatedCard, FadeIn } from '@/components/animated-card';
import {
  Dialog,
  DialogContent,
  DialogHeader,
  DialogTitle,
} from '@/components/ui/dialog';

interface CameraWithPod {
  id: string;
  name: string;
  stream_url: string;
  status: 'active' | 'inactive' | 'error';
  position: string | null;
  created_at: string;
  updated_at: string;
  pods: {
    id: string;
    name: string;
    status: string;
    sites: {
      id: string;
      name: string;
      communities: {
        id: string;
        name: string;
        company_id: string;
      };
    };
  };
}

export default function CamerasPage() {
  const { user, profile, loading } = useAuth();
  const { activeCompanyId } = useCompany();
  const router = useRouter();
  const [cameras, setCameras] = useState<CameraWithPod[]>([]);
  const [loadingData, setLoadingData] = useState(true);
  const [selectedCamera, setSelectedCamera] = useState<CameraWithPod | null>(null);
  const [showStreamDialog, setShowStreamDialog] = useState(false);

  useEffect(() => {
    if (!loading && !user) {
      router.push('/login');
    }
  }, [user, loading, router]);

  useEffect(() => {
    if (user && profile && activeCompanyId) {
      fetchCameras();
    }
  }, [user, profile, activeCompanyId]);

  const fetchCameras = async () => {
    if (!activeCompanyId) return;
    setLoadingData(true);

    const { data, error } = await supabase
      .from('cameras')
      .select(`
        id,
        name,
        stream_url,
        status,
        position,
        created_at,
        updated_at,
        pods!inner (
          id,
          name,
          status,
          sites!inner (
            id,
            name,
            communities!inner (
              id,
              name,
              company_id
            )
          )
        )
      `)
      .eq('pods.sites.communities.company_id', activeCompanyId)
      .order('name');

    if (error) {
      console.error('Error fetching cameras:', error);
    } else if (data) {
      setCameras(data as any);
    }

    setLoadingData(false);
  };

  const getStatusIcon = (status: string) => {
    switch (status) {
      case 'active':
        return <CheckCircle2 className="w-4 h-4 text-green-500" />;
      case 'inactive':
        return <VideoOff className="w-4 h-4 text-gray-400" />;
      case 'error':
        return <AlertCircle className="w-4 h-4 text-red-500" />;
      default:
        return <Video className="w-4 h-4 text-gray-400" />;
    }
  };

  const getStatusBadge = (status: string) => {
    const variants: Record<string, 'default' | 'secondary' | 'destructive' | 'outline'> = {
      active: 'default',
      inactive: 'secondary',
      error: 'destructive',
    };

    return (
      <Badge variant={variants[status] || 'outline'} className="capitalize">
        {status}
      </Badge>
    );
  };

  const handleViewStream = (camera: CameraWithPod) => {
    setSelectedCamera(camera);
    setShowStreamDialog(true);
  };

  const formatDate = (dateString: string) => {
    return new Date(dateString).toLocaleDateString('en-US', {
      month: 'short',
      day: 'numeric',
      year: 'numeric',
      hour: '2-digit',
      minute: '2-digit',
    });
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
          <div className="flex items-center justify-between">
            <div>
              <h2 className="text-3xl font-bold flex items-center gap-3">
                <Camera className="w-8 h-8 text-blue-500" />
                Camera Management
              </h2>
              <p className="text-muted-foreground text-lg mt-2">
                Monitor and manage camera feeds across all sites
              </p>
            </div>
            <div className="flex items-center gap-2">
              <Badge variant="outline" className="text-base px-4 py-2">
                {cameras.length} {cameras.length === 1 ? 'Camera' : 'Cameras'}
              </Badge>
            </div>
          </div>
        </FadeIn>

        {loadingData ? (
          <div className="text-center py-12">
            <div className="text-lg text-muted-foreground">Loading cameras...</div>
          </div>
        ) : cameras.length === 0 ? (
          <Card className="p-12 text-center shadow-lg border-0 bg-white dark:bg-[#2D3748]">
            <Camera className="w-16 h-16 text-muted-foreground mx-auto mb-4" />
            <h3 className="text-xl font-semibold mb-2">No Cameras Found</h3>
            <p className="text-muted-foreground">
              No cameras are currently configured for this company.
            </p>
          </Card>
        ) : (
          <div className="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-3 gap-6">
            {cameras.map((camera, index) => (
              <AnimatedCard
                key={camera.id}
                delay={index * 0.05}
                className="p-6 rounded-2xl shadow-lg border-0 bg-white dark:bg-[#2D3748] hover:shadow-xl transition-all"
              >
                <div className="space-y-4">
                  <div className="flex items-start justify-between">
                    <div className="flex items-center gap-3">
                      {getStatusIcon(camera.status)}
                      <div>
                        <h3 className="font-semibold text-lg">{camera.name}</h3>
                        {camera.position && (
                          <p className="text-sm text-muted-foreground">{camera.position}</p>
                        )}
                      </div>
                    </div>
                    {getStatusBadge(camera.status)}
                  </div>

                  <div className="space-y-2 text-sm">
                    <div className="flex items-center justify-between py-2 border-t border-border">
                      <span className="text-muted-foreground">Pod</span>
                      <span className="font-medium">{camera.pods.name}</span>
                    </div>
                    <div className="flex items-center justify-between py-2 border-t border-border">
                      <span className="text-muted-foreground">Site</span>
                      <span className="font-medium">{camera.pods.sites.name}</span>
                    </div>
                    <div className="flex items-center justify-between py-2 border-t border-border">
                      <span className="text-muted-foreground">Community</span>
                      <span className="font-medium">
                        {camera.pods.sites.communities.name}
                      </span>
                    </div>
                    <div className="flex items-center justify-between py-2 border-t border-border">
                      <span className="text-muted-foreground">Last Updated</span>
                      <span className="font-medium text-xs">
                        {formatDate(camera.updated_at)}
                      </span>
                    </div>
                  </div>

                  <div className="pt-2">
                    <Button
                      onClick={() => handleViewStream(camera)}
                      disabled={camera.status !== 'active'}
                      className="w-full"
                      variant={camera.status === 'active' ? 'default' : 'outline'}
                    >
                      {camera.status === 'active' ? (
                        <>
                          <Play className="w-4 h-4 mr-2" />
                          View Stream
                        </>
                      ) : (
                        <>
                          <VideoOff className="w-4 h-4 mr-2" />
                          Stream Unavailable
                        </>
                      )}
                    </Button>
                  </div>
                </div>
              </AnimatedCard>
            ))}
          </div>
        )}
      </div>

      <Dialog open={showStreamDialog} onOpenChange={setShowStreamDialog}>
        <DialogContent className="max-w-5xl">
          <DialogHeader>
            <DialogTitle className="flex items-center gap-2">
              <Video className="w-5 h-5" />
              {selectedCamera?.name}
              {selectedCamera?.position && (
                <span className="text-muted-foreground text-sm font-normal">
                  {selectedCamera.position}
                </span>
              )}
            </DialogTitle>
          </DialogHeader>
          <div className="space-y-4">
            <div className="aspect-video bg-black rounded-lg flex items-center justify-center relative overflow-hidden">
              {selectedCamera?.stream_url ? (
                <video
                  className="w-full h-full"
                  controls
                  autoPlay
                  src={selectedCamera.stream_url}
                >
                  Your browser does not support the video tag.
                </video>
              ) : (
                <div className="text-white text-center">
                  <VideoOff className="w-16 h-16 mx-auto mb-4 opacity-50" />
                  <p className="text-lg">Stream URL not configured</p>
                </div>
              )}
            </div>
            <div className="grid grid-cols-2 gap-4 text-sm">
              <div>
                <span className="text-muted-foreground">Pod:</span>
                <span className="ml-2 font-medium">{selectedCamera?.pods.name}</span>
              </div>
              <div>
                <span className="text-muted-foreground">Site:</span>
                <span className="ml-2 font-medium">
                  {selectedCamera?.pods.sites.name}
                </span>
              </div>
              <div>
                <span className="text-muted-foreground">Status:</span>
                <span className="ml-2">{selectedCamera && getStatusBadge(selectedCamera.status)}</span>
              </div>
              <div>
                <span className="text-muted-foreground">Pod Status:</span>
                <span className="ml-2 capitalize">{selectedCamera?.pods.status}</span>
              </div>
            </div>
          </div>
        </DialogContent>
      </Dialog>
    </DashboardLayout>
  );
}
