'use client';

import { useState, useEffect } from 'react';
import { useRouter, useParams } from 'next/navigation';
import { DashboardLayout } from '@/components/dashboard-layout';
import { useAuth } from '@/lib/auth-context';
import { Card, CardContent, CardDescription, CardHeader, CardTitle } from '@/components/ui/card';
import { Button } from '@/components/ui/button';
import { Badge } from '@/components/ui/badge';
import { Table, TableBody, TableCell, TableHead, TableHeader, TableRow } from '@/components/ui/table';
import { Dialog, DialogContent, DialogDescription, DialogHeader, DialogTitle, DialogTrigger } from '@/components/ui/dialog';
import { AlertDialog, AlertDialogAction, AlertDialogCancel, AlertDialogContent, AlertDialogDescription, AlertDialogFooter, AlertDialogHeader, AlertDialogTitle } from '@/components/ui/alert-dialog';
import { toast } from 'sonner';
import { Key, Plus, Trash2, Copy, Check, Calendar, RefreshCw } from 'lucide-react';
import { formatDistanceToNow } from 'date-fns';

interface Token {
  id: string;
  token: string;
  expires_at: string;
  used_at: string | null;
  used_by_serial: string | null;
  used_by_mac: string | null;
  pod_id: string | null;
  created_at: string;
  use_count: number;
  max_uses: number;
  notes: string | null;
}

export default function CommunityTokensPage() {
  const router = useRouter();
  const params = useParams();
  const communityId = params.id as string;
  const { user, loading } = useAuth();

  const [tokens, setTokens] = useState<Token[]>([]);
  const [loadingTokens, setLoadingTokens] = useState(true);
  const [communityName, setCommunityName] = useState('');
  const [showCreateDialog, setShowCreateDialog] = useState(false);
  const [generatedToken, setGeneratedToken] = useState<string | null>(null);
  const [creatingToken, setCreatingToken] = useState(false);
  const [copiedToken, setCopiedToken] = useState<string | null>(null);
  const [deletingToken, setDeletingToken] = useState<string | null>(null);
  const [showDeleteDialog, setShowDeleteDialog] = useState(false);

  useEffect(() => {
    if (!loading && !user) {
      router.push('/login');
    }
  }, [user, loading, router]);

  useEffect(() => {
    if (user && communityId) {
      loadCommunity();
      loadTokens();
    }
  }, [user, communityId]);

  const loadCommunity = async () => {
    try {
      const { supabase } = await import('@/lib/supabase');
      const { data } = await supabase
        .from('communities')
        .select('name')
        .eq('id', communityId)
        .single();

      if (data) {
        setCommunityName(data.name);
      }
    } catch (error) {
      console.error('Error loading community:', error);
    }
  };

  const loadTokens = async () => {
    try {
      setLoadingTokens(true);
      const { supabase } = await import('@/lib/supabase');
      const { data: session } = await supabase.auth.getSession();

      const response = await fetch(
        `/api/pods/registration-tokens?community_id=${communityId}`,
        {
          headers: {
            Authorization: `Bearer ${session.session?.access_token}`,
          },
        }
      );

      if (!response.ok) throw new Error('Failed to fetch tokens');

      const result = await response.json();
      setTokens(result.tokens || []);
    } catch (error) {
      console.error('Error loading tokens:', error);
      toast.error('Failed to load tokens');
    } finally {
      setLoadingTokens(false);
    }
  };

  const handleCreateToken = async () => {
    try {
      setCreatingToken(true);
      const { supabase } = await import('@/lib/supabase');
      const { data: session } = await supabase.auth.getSession();

      const response = await fetch('/api/pods/registration-tokens', {
        method: 'POST',
        headers: {
          'Content-Type': 'application/json',
          Authorization: `Bearer ${session.session?.access_token}`,
        },
        body: JSON.stringify({
          community_id: communityId,
          expires_in_hours: 24,
          max_uses: 1,
          notes: 'Generated from portal',
        }),
      });

      if (!response.ok) throw new Error('Failed to create token');

      const result = await response.json();
      setGeneratedToken(result.token.token);
      toast.success('Token created successfully');
      await loadTokens();
    } catch (error) {
      console.error('Error creating token:', error);
      toast.error('Failed to create token');
    } finally {
      setCreatingToken(false);
    }
  };

  const handleDeleteToken = (tokenId: string) => {
    setDeletingToken(tokenId);
    setShowDeleteDialog(true);
  };

  const confirmDeleteToken = async () => {
    if (!deletingToken) return;

    try {
      const { supabase } = await import('@/lib/supabase');
      const { data: session } = await supabase.auth.getSession();

      const response = await fetch(
        `/api/pods/registration-tokens?id=${deletingToken}`,
        {
          method: 'DELETE',
          headers: {
            Authorization: `Bearer ${session.session?.access_token}`,
          },
        }
      );

      if (!response.ok) throw new Error('Failed to delete token');

      toast.success('Token deleted successfully');
      setShowDeleteDialog(false);
      setDeletingToken(null);
      await loadTokens();
    } catch (error) {
      console.error('Error deleting token:', error);
      toast.error('Failed to delete token');
    }
  };

  const handleCopyToken = (token: string) => {
    navigator.clipboard.writeText(token);
    setCopiedToken(token);
    setTimeout(() => setCopiedToken(null), 2000);
    toast.success('Token copied to clipboard');
  };

  const handleCloseCreateDialog = () => {
    setShowCreateDialog(false);
    setGeneratedToken(null);
  };

  if (loading || loadingTokens) {
    return (
      <DashboardLayout>
        <div className="flex items-center justify-center h-64">
          <div className="animate-spin rounded-full h-8 w-8 border-b-2 border-gray-900" />
        </div>
      </DashboardLayout>
    );
  }

  const activeTokens = tokens.filter(t => !t.used_at);
  const usedTokens = tokens.filter(t => t.used_at);

  return (
    <DashboardLayout>
      <div className="space-y-6">
        <div className="flex justify-between items-center">
          <div>
            <h1 className="text-3xl font-bold">POD Registration Tokens</h1>
            <p className="text-muted-foreground">
              {communityName} - Manage secure tokens for POD registration
            </p>
          </div>
          <Button onClick={() => setShowCreateDialog(true)}>
            <Plus className="mr-2 h-4 w-4" />
            Generate Token
          </Button>
        </div>

        <div className="grid gap-4 md:grid-cols-3">
          <Card>
            <CardHeader className="flex flex-row items-center justify-between space-y-0 pb-2">
              <CardTitle className="text-sm font-medium">Total Tokens</CardTitle>
              <Key className="h-4 w-4 text-muted-foreground" />
            </CardHeader>
            <CardContent>
              <div className="text-2xl font-bold">{tokens.length}</div>
            </CardContent>
          </Card>

          <Card>
            <CardHeader className="flex flex-row items-center justify-between space-y-0 pb-2">
              <CardTitle className="text-sm font-medium">Active Tokens</CardTitle>
              <RefreshCw className="h-4 w-4 text-green-500" />
            </CardHeader>
            <CardContent>
              <div className="text-2xl font-bold">{activeTokens.length}</div>
            </CardContent>
          </Card>

          <Card>
            <CardHeader className="flex flex-row items-center justify-between space-y-0 pb-2">
              <CardTitle className="text-sm font-medium">Used Tokens</CardTitle>
              <Check className="h-4 w-4 text-muted-foreground" />
            </CardHeader>
            <CardContent>
              <div className="text-2xl font-bold">{usedTokens.length}</div>
            </CardContent>
          </Card>
        </div>

        <Card>
          <CardHeader>
            <CardTitle>Active Tokens</CardTitle>
            <CardDescription>
              Unused tokens ready for POD registration
            </CardDescription>
          </CardHeader>
          <CardContent>
            {activeTokens.length === 0 ? (
              <div className="text-center py-12">
                <Key className="mx-auto h-12 w-12 text-gray-400" />
                <h3 className="mt-2 text-sm font-medium">No active tokens</h3>
                <p className="mt-1 text-sm text-muted-foreground">
                  Generate a token to register new PODs
                </p>
              </div>
            ) : (
              <Table>
                <TableHeader>
                  <TableRow>
                    <TableHead>Token</TableHead>
                    <TableHead>Created</TableHead>
                    <TableHead>Expires</TableHead>
                    <TableHead>Notes</TableHead>
                    <TableHead className="text-right">Actions</TableHead>
                  </TableRow>
                </TableHeader>
                <TableBody>
                  {activeTokens.map((token) => (
                    <TableRow key={token.id}>
                      <TableCell className="font-mono text-sm">
                        {token.token.substring(0, 20)}...
                        <Button
                          variant="ghost"
                          size="sm"
                          onClick={() => handleCopyToken(token.token)}
                          className="ml-2 h-6 w-6 p-0"
                        >
                          {copiedToken === token.token ? (
                            <Check className="h-3 w-3 text-green-500" />
                          ) : (
                            <Copy className="h-3 w-3" />
                          )}
                        </Button>
                      </TableCell>
                      <TableCell>
                        {formatDistanceToNow(new Date(token.created_at), { addSuffix: true })}
                      </TableCell>
                      <TableCell>
                        {formatDistanceToNow(new Date(token.expires_at), { addSuffix: true })}
                      </TableCell>
                      <TableCell>{token.notes || '-'}</TableCell>
                      <TableCell className="text-right">
                        <Button
                          variant="ghost"
                          size="sm"
                          onClick={() => handleDeleteToken(token.id)}
                          className="text-red-600 hover:text-red-700"
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

        <Card>
          <CardHeader>
            <CardTitle>Used Tokens</CardTitle>
            <CardDescription>
              Tokens that have been used for POD registration
            </CardDescription>
          </CardHeader>
          <CardContent>
            {usedTokens.length === 0 ? (
              <div className="text-center py-8 text-sm text-muted-foreground">
                No used tokens
              </div>
            ) : (
              <Table>
                <TableHeader>
                  <TableRow>
                    <TableHead>Token</TableHead>
                    <TableHead>Used</TableHead>
                    <TableHead>Serial</TableHead>
                    <TableHead>MAC</TableHead>
                    <TableHead>Notes</TableHead>
                  </TableRow>
                </TableHeader>
                <TableBody>
                  {usedTokens.map((token) => (
                    <TableRow key={token.id}>
                      <TableCell className="font-mono text-sm">
                        {token.token.substring(0, 20)}...
                      </TableCell>
                      <TableCell>
                        {formatDistanceToNow(new Date(token.used_at!), { addSuffix: true })}
                      </TableCell>
                      <TableCell className="text-sm">{token.used_by_serial || '-'}</TableCell>
                      <TableCell className="font-mono text-xs">{token.used_by_mac || '-'}</TableCell>
                      <TableCell>{token.notes || '-'}</TableCell>
                    </TableRow>
                  ))}
                </TableBody>
              </Table>
            )}
          </CardContent>
        </Card>
      </div>

      <Dialog open={showCreateDialog} onOpenChange={handleCloseCreateDialog}>
        <DialogContent>
          <DialogHeader>
            <DialogTitle>Generate POD Registration Token</DialogTitle>
            <DialogDescription>
              {generatedToken ? 'Token generated successfully' : 'Create a new token for POD registration'}
            </DialogDescription>
          </DialogHeader>
          {generatedToken ? (
            <div className="space-y-4">
              <div className="p-4 bg-muted rounded-lg">
                <p className="text-sm font-medium mb-2">Registration Token:</p>
                <div className="flex items-center gap-2">
                  <code className="flex-1 p-2 bg-background rounded border text-xs break-all">
                    {generatedToken}
                  </code>
                  <Button
                    size="sm"
                    variant="outline"
                    onClick={() => handleCopyToken(generatedToken)}
                  >
                    {copiedToken === generatedToken ? (
                      <Check className="h-4 w-4 text-green-500" />
                    ) : (
                      <Copy className="h-4 w-4" />
                    )}
                  </Button>
                </div>
              </div>
              <p className="text-sm text-muted-foreground">
                This token is valid for 24 hours and can only be used once.
                Copy it now and provide it to your POD during installation.
              </p>
              <Button onClick={handleCloseCreateDialog} className="w-full">
                Done
              </Button>
            </div>
          ) : (
            <div className="space-y-4">
              <p className="text-sm">
                This will generate a new single-use token valid for 24 hours.
              </p>
              <Button
                onClick={handleCreateToken}
                disabled={creatingToken}
                className="w-full"
              >
                {creatingToken ? 'Generating...' : 'Generate Token'}
              </Button>
            </div>
          )}
        </DialogContent>
      </Dialog>

      <AlertDialog open={showDeleteDialog} onOpenChange={setShowDeleteDialog}>
        <AlertDialogContent>
          <AlertDialogHeader>
            <AlertDialogTitle>Delete Token</AlertDialogTitle>
            <AlertDialogDescription>
              Are you sure you want to delete this token? This action cannot be undone.
            </AlertDialogDescription>
          </AlertDialogHeader>
          <AlertDialogFooter>
            <AlertDialogCancel onClick={() => setDeletingToken(null)}>
              Cancel
            </AlertDialogCancel>
            <AlertDialogAction
              onClick={confirmDeleteToken}
              className="bg-red-600 hover:bg-red-700"
            >
              Delete Token
            </AlertDialogAction>
          </AlertDialogFooter>
        </AlertDialogContent>
      </AlertDialog>
    </DashboardLayout>
  );
}
