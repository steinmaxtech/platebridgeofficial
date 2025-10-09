'use client';

import { useEffect, useState } from 'react';
import { useAuth } from '@/lib/auth-context';
import { useRouter, useParams } from 'next/navigation';
import { DashboardLayout } from '@/components/dashboard-layout';
import { Card } from '@/components/ui/card';
import { Button } from '@/components/ui/button';
import { Badge } from '@/components/ui/badge';
import { supabase } from '@/lib/supabase';
import { Film, Play, Download, ArrowLeft, Calendar, Clock } from 'lucide-react';
import { AnimatedCard, FadeIn } from '@/components/animated-card';
import {
  Dialog,
  DialogContent,
  DialogHeader,
  DialogTitle,
} from '@/components/ui/dialog';

interface Recording {
  id: string;
  camera_id: string;
  camera_name: string;
  pod_name: string;
  site_name: string;
  community_name: string;
  recorded_at: string;
  duration_seconds: number;
  file_size_bytes: number;
  event_type: string;
  plate_number: string | null;
  video_url: string | null;
  thumbnail_url: string | null;
  expires_in: number;
}

export default function RecordingsPage() {
  const { user, profile, loading } = useAuth();
  const router = useRouter();
  const params = useParams();
  const cameraId = params.id as string;

  const [recordings, setRecordings] = useState<Recording[]>([]);
  const [loadingData, setLoadingData] = useState(true);
  const [selectedRecording, setSelectedRecording] = useState<Recording | null>(null);
  const [showVideoDialog, setShowVideoDialog] = useState(false);
  const [cameraName, setCameraName] = useState<string>('');

  useEffect(() => {
    if (!loading && !user) {
      router.push('/login');
    }
  }, [user, loading, router]);

  useEffect(() => {
    if (user && profile && cameraId) {
      fetchCameraDetails();
      fetchRecordings();
    }
  }, [user, profile, cameraId]);

  const fetchCameraDetails = async () => {
    const { data, error } = await supabase
      .from('cameras')
      .select('name')
      .eq('id', cameraId)
      .maybeSingle();

    if (data) {
      setCameraName(data.name);
    }
  };

  const fetchRecordings = async () => {
    setLoadingData(true);

    try {
      const { data: { session } } = await supabase.auth.getSession();

      if (!session) {
        console.error('No active session');
        setLoadingData(false);
        return;
      }

      const response = await fetch(`/api/pod/recordings?camera_id=${cameraId}&limit=100`, {
        headers: {
          'Authorization': `Bearer ${session.access_token}`
        }
      });

      if (!response.ok) {
        console.error('Failed to fetch recordings:', await response.text());
        setLoadingData(false);
        return;
      }

      const data = await response.json();
      setRecordings(data.recordings || []);
    } catch (error) {
      console.error('Error fetching recordings:', error);
    } finally {
      setLoadingData(false);
    }
  };

  const handlePlayRecording = (recording: Recording) => {
    setSelectedRecording(recording);
    setShowVideoDialog(true);
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

  const formatDuration = (seconds: number) => {
    const mins = Math.floor(seconds / 60);
    const secs = seconds % 60;
    return `${mins}:${secs.toString().padStart(2, '0')}`;
  };

  const formatFileSize = (bytes: number) => {
    const mb = bytes / (1024 * 1024);
    return `${mb.toFixed(2)} MB`;
  };

  const getEventTypeBadge = (eventType: string) => {
    const variants: Record<string, 'default' | 'secondary' | 'destructive' | 'outline'> = {
      plate_detection: 'default',
      motion: 'secondary',
      manual: 'outline',
    };

    return (
      <Badge variant={variants[eventType] || 'outline'} className="capitalize">
        {eventType.replace('_', ' ')}
      </Badge>
    );
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
              <Button
                variant="ghost"
                onClick={() => router.push('/cameras')}
                className="mb-4"
              >
                <ArrowLeft className="w-4 h-4 mr-2" />
                Back to Cameras
              </Button>
              <h2 className="text-3xl font-bold flex items-center gap-3">
                <Film className="w-8 h-8 text-blue-500" />
                Recordings: {cameraName || 'Camera'}
              </h2>
              <p className="text-muted-foreground text-lg mt-2">
                View recorded footage from this camera
              </p>
            </div>
            <div className="flex items-center gap-2">
              <Badge variant="outline" className="text-base px-4 py-2">
                {recordings.length} {recordings.length === 1 ? 'Recording' : 'Recordings'}
              </Badge>
            </div>
          </div>
        </FadeIn>

        {loadingData ? (
          <div className="text-center py-12">
            <div className="text-lg text-muted-foreground">Loading recordings...</div>
          </div>
        ) : recordings.length === 0 ? (
          <Card className="p-12 text-center shadow-lg border-0 bg-white dark:bg-[#2D3748]">
            <Film className="w-16 h-16 text-muted-foreground mx-auto mb-4" />
            <h3 className="text-xl font-semibold mb-2">No Recordings Found</h3>
            <p className="text-muted-foreground">
              No recordings are available for this camera yet.
            </p>
          </Card>
        ) : (
          <div className="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-3 gap-6">
            {recordings.map((recording, index) => (
              <AnimatedCard
                key={recording.id}
                delay={index * 0.05}
                className="p-0 rounded-2xl shadow-lg border-0 bg-white dark:bg-[#2D3748] hover:shadow-xl transition-all overflow-hidden"
              >
                <div className="relative">
                  {recording.thumbnail_url ? (
                    <img
                      src={recording.thumbnail_url}
                      alt="Recording thumbnail"
                      className="w-full aspect-video object-cover"
                    />
                  ) : (
                    <div className="w-full aspect-video bg-gray-800 flex items-center justify-center">
                      <Film className="w-12 h-12 text-gray-600" />
                    </div>
                  )}
                  <div className="absolute top-2 right-2">
                    {getEventTypeBadge(recording.event_type)}
                  </div>
                  {recording.plate_number && (
                    <div className="absolute bottom-2 left-2">
                      <Badge variant="secondary" className="font-mono">
                        {recording.plate_number}
                      </Badge>
                    </div>
                  )}
                </div>

                <div className="p-4 space-y-3">
                  <div className="flex items-center gap-2 text-sm text-muted-foreground">
                    <Calendar className="w-4 h-4" />
                    <span>{formatDate(recording.recorded_at)}</span>
                  </div>

                  <div className="flex items-center justify-between text-sm">
                    <div className="flex items-center gap-2 text-muted-foreground">
                      <Clock className="w-4 h-4" />
                      <span>{formatDuration(recording.duration_seconds)}</span>
                    </div>
                    <span className="text-muted-foreground text-xs">
                      {formatFileSize(recording.file_size_bytes)}
                    </span>
                  </div>

                  <div className="flex gap-2 pt-2">
                    <Button
                      onClick={() => handlePlayRecording(recording)}
                      className="flex-1"
                      disabled={!recording.video_url}
                    >
                      <Play className="w-4 h-4 mr-2" />
                      Play
                    </Button>
                    {recording.video_url && (
                      <Button
                        variant="outline"
                        onClick={() => window.open(recording.video_url!, '_blank')}
                      >
                        <Download className="w-4 h-4" />
                      </Button>
                    )}
                  </div>
                </div>
              </AnimatedCard>
            ))}
          </div>
        )}
      </div>

      <Dialog open={showVideoDialog} onOpenChange={setShowVideoDialog}>
        <DialogContent className="max-w-5xl">
          <DialogHeader>
            <DialogTitle className="flex items-center gap-2">
              <Film className="w-5 h-5" />
              {formatDate(selectedRecording?.recorded_at || '')}
              {selectedRecording?.plate_number && (
                <Badge variant="secondary" className="ml-2 font-mono">
                  {selectedRecording.plate_number}
                </Badge>
              )}
            </DialogTitle>
          </DialogHeader>
          <div className="space-y-4">
            <div className="aspect-video bg-black rounded-lg flex items-center justify-center relative overflow-hidden">
              {selectedRecording?.video_url ? (
                <video
                  className="w-full h-full"
                  controls
                  autoPlay
                  src={selectedRecording.video_url}
                >
                  Your browser does not support the video tag.
                </video>
              ) : (
                <div className="text-white text-center">
                  <Film className="w-16 h-16 mx-auto mb-4 opacity-50" />
                  <p className="text-lg">Video not available</p>
                </div>
              )}
            </div>
            <div className="grid grid-cols-2 gap-4 text-sm">
              <div>
                <span className="text-muted-foreground">Event Type:</span>
                <span className="ml-2">{selectedRecording && getEventTypeBadge(selectedRecording.event_type)}</span>
              </div>
              <div>
                <span className="text-muted-foreground">Duration:</span>
                <span className="ml-2 font-medium">
                  {selectedRecording && formatDuration(selectedRecording.duration_seconds)}
                </span>
              </div>
              <div>
                <span className="text-muted-foreground">Pod:</span>
                <span className="ml-2 font-medium">{selectedRecording?.pod_name}</span>
              </div>
              <div>
                <span className="text-muted-foreground">Site:</span>
                <span className="ml-2 font-medium">{selectedRecording?.site_name}</span>
              </div>
            </div>
          </div>
        </DialogContent>
      </Dialog>
    </DashboardLayout>
  );
}
