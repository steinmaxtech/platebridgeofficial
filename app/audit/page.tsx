'use client';

import { useEffect, useState } from 'react';
import { useAuth } from '@/lib/auth-context';
import { useRouter } from 'next/navigation';
import { DashboardLayout } from '@/components/dashboard-layout';
import { Card } from '@/components/ui/card';
import { Table, TableBody, TableCell, TableHead, TableHeader, TableRow } from '@/components/ui/table';
import { Badge } from '@/components/ui/badge';
import { supabase } from '@/lib/supabase';
import { Calendar, Activity } from 'lucide-react';

interface AuditEvent {
  id: string;
  event_type: string;
  user_id: string;
  user_email?: string;
  metadata: any;
  created_at: string;
}

export default function AuditPage() {
  const { user, profile, loading } = useAuth();
  const router = useRouter();
  const [events, setEvents] = useState<AuditEvent[]>([]);
  const [loadingEvents, setLoadingEvents] = useState(true);

  useEffect(() => {
    if (!loading && !user) {
      router.push('/login');
    }
  }, [user, loading, router]);

  useEffect(() => {
    if (user && profile) {
      fetchEvents();
    }
  }, [user, profile]);

  const fetchEvents = async () => {
    setLoadingEvents(true);
    const { data } = await supabase
      .from('audit_events')
      .select(`
        *,
        user_profiles!inner (
          email
        )
      `)
      .order('created_at', { ascending: false })
      .limit(100);

    if (data) {
      const formatted = data.map((event: any) => ({
        ...event,
        user_email: event.user_profiles?.email
      }));
      setEvents(formatted);
    }
    setLoadingEvents(false);
  };

  const getEventBadgeColor = (eventType: string) => {
    switch (eventType) {
      case 'user.created': return 'bg-green-100 text-green-800 dark:bg-green-900/20 dark:text-green-400';
      case 'user.updated': return 'bg-blue-100 text-blue-800 dark:bg-blue-900/20 dark:text-blue-400';
      case 'plate.added': return 'bg-purple-100 text-purple-800 dark:bg-purple-900/20 dark:text-purple-400';
      case 'plate.removed': return 'bg-red-100 text-red-800 dark:bg-red-900/20 dark:text-red-400';
      case 'property.created': return 'bg-cyan-100 text-cyan-800 dark:bg-cyan-900/20 dark:text-cyan-400';
      case 'property.updated': return 'bg-yellow-100 text-yellow-800 dark:bg-yellow-900/20 dark:text-yellow-400';
      default: return 'bg-gray-100 text-gray-800 dark:bg-gray-700 dark:text-gray-300';
    }
  };

  const formatEventType = (eventType: string) => {
    return eventType.split('.').map(word =>
      word.charAt(0).toUpperCase() + word.slice(1)
    ).join(' ');
  };

  const formatMetadata = (metadata: any) => {
    if (!metadata) return '—';

    const relevantKeys = Object.keys(metadata).filter(key =>
      !key.includes('id') && !key.includes('timestamp')
    );

    if (relevantKeys.length === 0) return '—';

    return relevantKeys.map(key =>
      `${key}: ${metadata[key]}`
    ).join(', ');
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
      <div className="max-w-7xl mx-auto">
        <div className="mb-8">
          <div className="flex items-center gap-3 mb-2">
            <div className="p-3 rounded-2xl bg-blue-50 dark:bg-blue-900/20">
              <Activity className="w-6 h-6 text-blue-600 dark:text-blue-400" />
            </div>
            <h2 className="text-3xl font-bold">Audit Log</h2>
          </div>
          <p className="text-muted-foreground">Track all system activities and changes</p>
        </div>

        <Card className="p-6 shadow-lg border-0 bg-white dark:bg-[#2D3748]">
          {loadingEvents ? (
            <div className="text-center py-8">Loading audit events...</div>
          ) : events.length === 0 ? (
            <div className="text-center py-8 text-muted-foreground">
              No audit events yet. Activity will be logged here.
            </div>
          ) : (
            <Table>
              <TableHeader>
                <TableRow>
                  <TableHead>Event</TableHead>
                  <TableHead>User</TableHead>
                  <TableHead>Details</TableHead>
                  <TableHead>
                    <div className="flex items-center gap-2">
                      <Calendar className="w-4 h-4" />
                      Timestamp
                    </div>
                  </TableHead>
                </TableRow>
              </TableHeader>
              <TableBody>
                {events.map((event) => (
                  <TableRow key={event.id}>
                    <TableCell>
                      <Badge className={getEventBadgeColor(event.event_type)}>
                        {formatEventType(event.event_type)}
                      </Badge>
                    </TableCell>
                    <TableCell className="font-medium">{event.user_email}</TableCell>
                    <TableCell className="text-muted-foreground text-sm max-w-md truncate">
                      {formatMetadata(event.metadata)}
                    </TableCell>
                    <TableCell className="text-sm">
                      {new Date(event.created_at).toLocaleString()}
                    </TableCell>
                  </TableRow>
                ))}
              </TableBody>
            </Table>
          )}
        </Card>

        <div className="mt-6 text-sm text-muted-foreground text-center">
          Showing last 100 events
        </div>
      </div>
    </DashboardLayout>
  );
}
