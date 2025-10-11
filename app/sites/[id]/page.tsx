'use client';

import { useState, useEffect } from 'react';
import { useRouter, useParams } from 'next/navigation';
import { DashboardLayout } from '@/components/dashboard-layout';
import { useAuth } from '@/lib/auth-context';
import { Card, CardContent, CardDescription, CardHeader, CardTitle } from '@/components/ui/card';
import { Button } from '@/components/ui/button';
import { Badge } from '@/components/ui/badge';
import { Alert, AlertDescription } from '@/components/ui/alert';
import { supabase } from '@/lib/supabase';
import { toast } from 'sonner';
import { ArrowLeft, QrCode, Copy, CheckCircle2, MapPin, Server } from 'lucide-react';

interface Site {
  id: string;
  name: string;
  site_id: string;
  community_id: string;
  is_active: boolean;
  community: {
    name: string;
    company_id: string;
  };
}

export default function SiteDetailPage() {
  const router = useRouter();
  const params = useParams();
  const siteId = params?.id as string;
  const { user, loading } = useAuth();

  const [site, setSite] = useState<Site | null>(null);
  const [loadingSite, setLoadingSite] = useState(true);
  const [copied, setCopied] = useState(false);

  useEffect(() => {
    if (!loading && !user) {
      router.push('/login');
    }
  }, [user, loading, router]);

  useEffect(() => {
    if (user && siteId) {
      loadSite();
    }
  }, [user, siteId]);

  const loadSite = async () => {
    try {
      setLoadingSite(true);
      const { data, error } = await supabase
        .from('sites')
        .select('*, community:communities(name, company_id)')
        .eq('id', siteId)
        .single();

      if (error) throw error;
      setSite(data);
    } catch (error) {
      console.error('Error loading site:', error);
      toast.error('Failed to load site');
    } finally {
      setLoadingSite(false);
    }
  };

  const copyToClipboard = (text: string, label: string) => {
    navigator.clipboard.writeText(text);
    setCopied(true);
    toast.success(`${label} copied to clipboard`);
    setTimeout(() => setCopied(false), 2000);
  };

  const generateQRCodeData = () => {
    if (!site) return '';

    const qrData = {
      site_id: site.id,
      site_name: site.name,
      community_id: site.community_id,
      community_name: site.community?.name,
      portal_url: process.env.NEXT_PUBLIC_SITE_URL || window.location.origin,
      version: '1.0'
    };

    return JSON.stringify(qrData);
  };

  const generateQRCodeURL = () => {
    const data = generateQRCodeData();
    return `https://api.qrserver.com/v1/create-qr-code/?size=300x300&data=${encodeURIComponent(data)}`;
  };

  if (loading || loadingSite) {
    return (
      <DashboardLayout>
        <div className="flex items-center justify-center h-64">
          <div className="animate-spin rounded-full h-8 w-8 border-b-2 border-gray-900" />
        </div>
      </DashboardLayout>
    );
  }

  if (!site) {
    return (
      <DashboardLayout>
        <Alert>
          <AlertDescription>Site not found</AlertDescription>
        </Alert>
      </DashboardLayout>
    );
  }

  return (
    <DashboardLayout>
      <div className="space-y-6">
        <div className="flex items-center gap-4">
          <Button variant="ghost" size="sm" onClick={() => router.push('/properties')}>
            <ArrowLeft className="mr-2 h-4 w-4" />
            Back
          </Button>
          <div>
            <div className="flex items-center gap-2">
              <h1 className="text-3xl font-bold">{site.name}</h1>
              <Badge variant={site.is_active ? 'default' : 'secondary'}>
                {site.is_active ? 'Active' : 'Inactive'}
              </Badge>
            </div>
            <p className="text-muted-foreground">{site.community?.name}</p>
          </div>
        </div>

        <div className="grid gap-6 md:grid-cols-2">
          <Card>
            <CardHeader>
              <CardTitle className="flex items-center gap-2">
                <MapPin className="h-5 w-5" />
                Site Information
              </CardTitle>
            </CardHeader>
            <CardContent className="space-y-4">
              <div>
                <label className="text-sm text-muted-foreground">Site ID</label>
                <div className="flex items-center gap-2 mt-1">
                  <code className="flex-1 px-3 py-2 bg-muted rounded text-sm font-mono">
                    {site.id}
                  </code>
                  <Button
                    variant="outline"
                    size="sm"
                    onClick={() => copyToClipboard(site.id, 'Site ID')}
                  >
                    {copied ? <CheckCircle2 className="h-4 w-4" /> : <Copy className="h-4 w-4" />}
                  </Button>
                </div>
              </div>

              <div>
                <label className="text-sm text-muted-foreground">Site Code</label>
                <div className="flex items-center gap-2 mt-1">
                  <code className="flex-1 px-3 py-2 bg-muted rounded text-sm font-mono">
                    {site.site_id}
                  </code>
                  <Button
                    variant="outline"
                    size="sm"
                    onClick={() => copyToClipboard(site.site_id, 'Site Code')}
                  >
                    <Copy className="h-4 w-4" />
                  </Button>
                </div>
              </div>

              <div>
                <label className="text-sm text-muted-foreground">Community ID</label>
                <div className="flex items-center gap-2 mt-1">
                  <code className="flex-1 px-3 py-2 bg-muted rounded text-sm font-mono">
                    {site.community_id}
                  </code>
                  <Button
                    variant="outline"
                    size="sm"
                    onClick={() => copyToClipboard(site.community_id, 'Community ID')}
                  >
                    <Copy className="h-4 w-4" />
                  </Button>
                </div>
              </div>
            </CardContent>
          </Card>

          <Card>
            <CardHeader>
              <CardTitle className="flex items-center gap-2">
                <QrCode className="h-5 w-5" />
                POD Registration QR Code
              </CardTitle>
              <CardDescription>
                Scan this QR code during POD installation to auto-configure site settings
              </CardDescription>
            </CardHeader>
            <CardContent className="space-y-4">
              <div className="flex justify-center p-4 bg-white rounded-lg border">
                <img
                  src={generateQRCodeURL()}
                  alt="POD Registration QR Code"
                  className="w-64 h-64"
                />
              </div>

              <div className="space-y-2">
                <p className="text-sm text-muted-foreground">
                  This QR code contains:
                </p>
                <ul className="text-sm space-y-1 ml-4">
                  <li>• Site ID for registration</li>
                  <li>• Portal URL</li>
                  <li>• Community information</li>
                </ul>
              </div>

              <Button
                className="w-full"
                variant="outline"
                onClick={() => {
                  const data = generateQRCodeData();
                  copyToClipboard(data, 'QR Code Data');
                }}
              >
                <Copy className="mr-2 h-4 w-4" />
                Copy QR Code Data
              </Button>
            </CardContent>
          </Card>
        </div>

        <Card>
          <CardHeader>
            <CardTitle className="flex items-center gap-2">
              <Server className="h-5 w-5" />
              POD Registration Instructions
            </CardTitle>
            <CardDescription>
              How to register a POD to this site
            </CardDescription>
          </CardHeader>
          <CardContent className="space-y-6">
            <div>
              <h3 className="font-semibold mb-2">Method 1: QR Code (Recommended)</h3>
              <ol className="list-decimal list-inside space-y-2 text-sm text-muted-foreground">
                <li>Power on the POD and wait for setup mode</li>
                <li>Scan the QR code above using the POD's camera or mobile app</li>
                <li>POD will automatically register to this site</li>
                <li>Verify registration in the PODs dashboard</li>
              </ol>
            </div>

            <div>
              <h3 className="font-semibold mb-2">Method 2: Manual Entry</h3>
              <ol className="list-decimal list-inside space-y-2 text-sm text-muted-foreground">
                <li>Connect to POD's WiFi hotspot (PlateBridge-Setup-XXXX)</li>
                <li>Open browser to http://192.168.4.1</li>
                <li>Enter Site ID: <code className="px-1 py-0.5 bg-muted rounded text-xs">{site.id}</code></li>
                <li>Enter Portal URL: <code className="px-1 py-0.5 bg-muted rounded text-xs">{process.env.NEXT_PUBLIC_SITE_URL || window.location.origin}</code></li>
                <li>Click "Register" and wait for confirmation</li>
              </ol>
            </div>

            <div>
              <h3 className="font-semibold mb-2">Method 3: API Registration</h3>
              <div className="bg-muted p-4 rounded-lg">
                <pre className="text-xs overflow-x-auto">
{`curl -X POST ${process.env.NEXT_PUBLIC_SITE_URL || window.location.origin}/api/pods/register \\
  -H "Content-Type: application/json" \\
  -d '{
    "serial": "PB-XXXX-XXXX",
    "mac": "aa:bb:cc:dd:ee:ff",
    "model": "PB-M1",
    "version": "1.0.0",
    "site_id": "${site.id}"
  }'`}
                </pre>
              </div>
              <Button
                className="mt-2"
                variant="outline"
                size="sm"
                onClick={() => {
                  const curlCommand = `curl -X POST ${process.env.NEXT_PUBLIC_SITE_URL || window.location.origin}/api/pods/register -H "Content-Type: application/json" -d '{"serial": "PB-XXXX-XXXX", "mac": "aa:bb:cc:dd:ee:ff", "model": "PB-M1", "version": "1.0.0", "site_id": "${site.id}"}'`;
                  copyToClipboard(curlCommand, 'cURL command');
                }}
              >
                <Copy className="mr-2 h-4 w-4" />
                Copy cURL Command
              </Button>
            </div>
          </CardContent>
        </Card>
      </div>
    </DashboardLayout>
  );
}
