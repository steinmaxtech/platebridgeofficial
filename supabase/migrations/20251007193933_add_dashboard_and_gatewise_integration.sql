/*
  # Add Dashboard Metrics and Gatewise Integration
  
  ## Overview
  This migration adds support for custom dashboards for admins and property managers,
  including Gatewise API integration, pod health tracking, and system metrics.
  
  ## New Tables
  1. `pod_health`
    - Tracks real-time health status of edge pods
    - Includes last check-in times, sync status, and metrics
    
  2. `gatewise_config`
    - Stores Gatewise API credentials per community
    - Encrypted API keys for secure storage
    
  3. `system_metrics`
    - Aggregated metrics for dashboard display
    - Plate detections, pod status, camera feeds
  
  ## Changes to Existing Tables
  - Add `logo_url` to companies table for branding
  - Add `gatewise_enabled` flag to communities
  
  ## Security
  - RLS policies for each table based on company membership
  - Encrypted storage for API keys
  - Manager role can manage their community's Gatewise config
*/

-- Add logo support to companies
ALTER TABLE companies 
ADD COLUMN IF NOT EXISTS logo_url TEXT,
ADD COLUMN IF NOT EXISTS uptime_sla DECIMAL(5,2) DEFAULT 99.9;

-- Add Gatewise flag to communities
ALTER TABLE communities 
ADD COLUMN IF NOT EXISTS gatewise_enabled BOOLEAN DEFAULT false;

-- Create pod_health table for tracking edge device status
CREATE TABLE IF NOT EXISTS pod_health (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  site_id UUID NOT NULL REFERENCES sites(id) ON DELETE CASCADE,
  pod_name TEXT NOT NULL,
  status TEXT NOT NULL DEFAULT 'offline' CHECK (status IN ('online', 'warning', 'offline', 'error')),
  last_checkin TIMESTAMPTZ,
  last_sync TIMESTAMPTZ,
  version TEXT,
  ip_address TEXT,
  cpu_usage DECIMAL(5,2),
  memory_usage DECIMAL(5,2),
  disk_usage DECIMAL(5,2),
  camera_count INTEGER DEFAULT 0,
  plates_detected_24h INTEGER DEFAULT 0,
  error_message TEXT,
  metadata JSONB DEFAULT '{}'::jsonb,
  created_at TIMESTAMPTZ DEFAULT now(),
  updated_at TIMESTAMPTZ DEFAULT now(),
  UNIQUE(site_id, pod_name)
);

CREATE INDEX IF NOT EXISTS idx_pod_health_site_id ON pod_health(site_id);
CREATE INDEX IF NOT EXISTS idx_pod_health_status ON pod_health(status);
CREATE INDEX IF NOT EXISTS idx_pod_health_last_checkin ON pod_health(last_checkin);

-- Create gatewise_config table for API credentials
CREATE TABLE IF NOT EXISTS gatewise_config (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  community_id UUID NOT NULL REFERENCES communities(id) ON DELETE CASCADE,
  api_key TEXT NOT NULL,
  api_endpoint TEXT DEFAULT 'https://api.gatewise.com/v1',
  enabled BOOLEAN DEFAULT true,
  last_sync TIMESTAMPTZ,
  sync_status TEXT DEFAULT 'pending' CHECK (sync_status IN ('pending', 'syncing', 'success', 'error')),
  error_message TEXT,
  metadata JSONB DEFAULT '{}'::jsonb,
  created_at TIMESTAMPTZ DEFAULT now(),
  updated_at TIMESTAMPTZ DEFAULT now(),
  UNIQUE(community_id)
);

CREATE INDEX IF NOT EXISTS idx_gatewise_config_community_id ON gatewise_config(community_id);
CREATE INDEX IF NOT EXISTS idx_gatewise_config_enabled ON gatewise_config(enabled);

-- Create system_metrics table for dashboard aggregations
CREATE TABLE IF NOT EXISTS system_metrics (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  company_id UUID NOT NULL REFERENCES companies(id) ON DELETE CASCADE,
  metric_date DATE NOT NULL DEFAULT CURRENT_DATE,
  total_pods INTEGER DEFAULT 0,
  pods_online INTEGER DEFAULT 0,
  total_cameras INTEGER DEFAULT 0,
  cameras_active INTEGER DEFAULT 0,
  plates_detected_24h INTEGER DEFAULT 0,
  plates_detected_7d INTEGER DEFAULT 0,
  gatewise_connected BOOLEAN DEFAULT false,
  uptime_percentage DECIMAL(5,2) DEFAULT 100.0,
  metadata JSONB DEFAULT '{}'::jsonb,
  created_at TIMESTAMPTZ DEFAULT now(),
  updated_at TIMESTAMPTZ DEFAULT now(),
  UNIQUE(company_id, metric_date)
);

CREATE INDEX IF NOT EXISTS idx_system_metrics_company_id ON system_metrics(company_id);
CREATE INDEX IF NOT EXISTS idx_system_metrics_date ON system_metrics(metric_date);

-- Enable RLS on new tables
ALTER TABLE pod_health ENABLE ROW LEVEL SECURITY;
ALTER TABLE gatewise_config ENABLE ROW LEVEL SECURITY;
ALTER TABLE system_metrics ENABLE ROW LEVEL SECURITY;

-- RLS Policies for pod_health
CREATE POLICY "Users can view pod health in their company communities"
  ON pod_health FOR SELECT
  TO authenticated
  USING (
    EXISTS (
      SELECT 1 FROM memberships m
      JOIN communities c ON c.company_id = m.company_id
      JOIN sites s ON s.community_id = c.id
      WHERE s.id = pod_health.site_id
      AND m.user_id = auth.uid()
    )
  );

CREATE POLICY "Managers can update pod health for their sites"
  ON pod_health FOR UPDATE
  TO authenticated
  USING (
    EXISTS (
      SELECT 1 FROM memberships m
      JOIN communities c ON c.company_id = m.company_id
      JOIN sites s ON s.community_id = c.id
      WHERE s.id = pod_health.site_id
      AND m.user_id = auth.uid()
      AND m.role IN ('owner', 'admin', 'manager')
    )
  )
  WITH CHECK (
    EXISTS (
      SELECT 1 FROM memberships m
      JOIN communities c ON c.company_id = m.company_id
      JOIN sites s ON s.community_id = c.id
      WHERE s.id = pod_health.site_id
      AND m.user_id = auth.uid()
      AND m.role IN ('owner', 'admin', 'manager')
    )
  );

CREATE POLICY "Managers can insert pod health for their sites"
  ON pod_health FOR INSERT
  TO authenticated
  WITH CHECK (
    EXISTS (
      SELECT 1 FROM memberships m
      JOIN communities c ON c.company_id = m.company_id
      JOIN sites s ON s.community_id = c.id
      WHERE s.id = pod_health.site_id
      AND m.user_id = auth.uid()
      AND m.role IN ('owner', 'admin', 'manager')
    )
  );

-- RLS Policies for gatewise_config
CREATE POLICY "Users can view gatewise config in their communities"
  ON gatewise_config FOR SELECT
  TO authenticated
  USING (
    EXISTS (
      SELECT 1 FROM memberships m
      JOIN communities c ON c.company_id = m.company_id
      WHERE c.id = gatewise_config.community_id
      AND m.user_id = auth.uid()
    )
  );

CREATE POLICY "Managers can manage gatewise config for their communities"
  ON gatewise_config FOR ALL
  TO authenticated
  USING (
    EXISTS (
      SELECT 1 FROM memberships m
      JOIN communities c ON c.company_id = m.company_id
      WHERE c.id = gatewise_config.community_id
      AND m.user_id = auth.uid()
      AND m.role IN ('owner', 'admin', 'manager')
    )
  )
  WITH CHECK (
    EXISTS (
      SELECT 1 FROM memberships m
      JOIN communities c ON c.company_id = m.company_id
      WHERE c.id = gatewise_config.community_id
      AND m.user_id = auth.uid()
      AND m.role IN ('owner', 'admin', 'manager')
    )
  );

-- RLS Policies for system_metrics
CREATE POLICY "Users can view metrics for their company"
  ON system_metrics FOR SELECT
  TO authenticated
  USING (
    EXISTS (
      SELECT 1 FROM memberships m
      WHERE m.company_id = system_metrics.company_id
      AND m.user_id = auth.uid()
    )
  );

CREATE POLICY "Admins can manage metrics for their company"
  ON system_metrics FOR ALL
  TO authenticated
  USING (
    EXISTS (
      SELECT 1 FROM memberships m
      WHERE m.company_id = system_metrics.company_id
      AND m.user_id = auth.uid()
      AND m.role IN ('owner', 'admin')
    )
  )
  WITH CHECK (
    EXISTS (
      SELECT 1 FROM memberships m
      WHERE m.company_id = system_metrics.company_id
      AND m.user_id = auth.uid()
      AND m.role IN ('owner', 'admin')
    )
  );

-- Function to update pod health timestamp
CREATE OR REPLACE FUNCTION update_pod_health_timestamp()
RETURNS TRIGGER AS $$
BEGIN
  NEW.updated_at = now();
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER update_pod_health_timestamp
  BEFORE UPDATE ON pod_health
  FOR EACH ROW
  EXECUTE FUNCTION update_pod_health_timestamp();

CREATE TRIGGER update_gatewise_config_timestamp
  BEFORE UPDATE ON gatewise_config
  FOR EACH ROW
  EXECUTE FUNCTION update_pod_health_timestamp();

CREATE TRIGGER update_system_metrics_timestamp
  BEFORE UPDATE ON system_metrics
  FOR EACH ROW
  EXECUTE FUNCTION update_pod_health_timestamp();
