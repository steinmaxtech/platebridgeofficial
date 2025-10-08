import { createClient } from '@supabase/supabase-js';

const supabaseUrl = process.env.NEXT_PUBLIC_SUPABASE_URL || '';
const supabaseAnonKey = process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY || '';

if (!supabaseUrl || !supabaseAnonKey) {
  console.error('Missing Supabase environment variables');
}

export const supabase = createClient(supabaseUrl, supabaseAnonKey);

export type UserRole = 'owner' | 'admin' | 'manager' | 'viewer' | 'resident';

export interface UserProfile {
  id: string;
  role: UserRole;
  view_as_role: UserRole | null;
  property_id: string | null;
  created_at: string;
  updated_at: string;
}

export interface Property {
  id: string;
  name: string;
  timezone: string;
  address: string;
  is_active: boolean;
  config_version: number;
  created_at: string;
  updated_at: string;
}

export interface PlateEntry {
  id: string;
  property_id: string;
  plate: string;
  unit: string | null;
  tenant: string | null;
  vehicle: string | null;
  starts: string | null;
  ends: string | null;
  days: string | null;
  time_start: string | null;
  time_end: string | null;
  enabled: boolean;
  notes: string | null;
  created_at: string;
  updated_at: string;
}

export interface AuditEntry {
  id: string;
  ts: string;
  site_id: string | null;
  property_id: string | null;
  plate: string | null;
  camera: string | null;
  action: string;
  result: string;
  by: string;
  metadata: Record<string, any>;
}
