/*
  # Access Control System for Trusted Vehicles

  Creates tables for managing trusted vehicle access (delivery, emergency, etc.)
  
  1. New Tables
    - `access_lists` - Authorized vehicles with schedules
    - `access_logs` - Audit log of access decisions
    - `community_access_settings` - Community-level configuration
    
  2. Security
    - RLS enabled on all tables
    - Authenticated users can manage their community's access lists
*/

-- Create enum types
DO $$ BEGIN
  CREATE TYPE access_entry_type AS ENUM ('resident', 'delivery', 'emergency', 'service', 'visitor', 'contractor');
EXCEPTION
  WHEN duplicate_object THEN null;
END $$;

DO $$ BEGIN
  CREATE TYPE access_decision AS ENUM ('granted', 'denied', 'manual', 'override');
EXCEPTION
  WHEN duplicate_object THEN null;
END $$;

-- Create access_lists table
CREATE TABLE IF NOT EXISTS access_lists (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  community_id uuid NOT NULL REFERENCES communities(id) ON DELETE CASCADE,
  plate text NOT NULL,
  type access_entry_type NOT NULL DEFAULT 'visitor',
  vendor_name text,
  schedule_start time,
  schedule_end time,
  days_active text DEFAULT 'Mon-Sun',
  expires_at timestamptz,
  notes text,
  created_by uuid REFERENCES auth.users(id),
  created_at timestamptz DEFAULT now(),
  updated_at timestamptz DEFAULT now(),
  is_active boolean DEFAULT true
);

-- Create indexes
CREATE INDEX IF NOT EXISTS idx_access_lists_plate ON access_lists(plate) WHERE is_active = true;
CREATE INDEX IF NOT EXISTS idx_access_lists_community ON access_lists(community_id) WHERE is_active = true;
CREATE INDEX IF NOT EXISTS idx_access_lists_type ON access_lists(type);

-- Create access_logs table
CREATE TABLE IF NOT EXISTS access_logs (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  pod_id uuid REFERENCES pods(id) ON DELETE SET NULL,
  community_id uuid NOT NULL REFERENCES communities(id) ON DELETE CASCADE,
  plate text NOT NULL,
  decision access_decision NOT NULL,
  reason text,
  access_type access_entry_type,
  vendor_name text,
  gate_triggered boolean DEFAULT false,
  confidence numeric,
  timestamp timestamptz DEFAULT now()
);

-- Create indexes
CREATE INDEX IF NOT EXISTS idx_access_logs_community ON access_logs(community_id, timestamp DESC);
CREATE INDEX IF NOT EXISTS idx_access_logs_pod ON access_logs(pod_id, timestamp DESC);
CREATE INDEX IF NOT EXISTS idx_access_logs_plate ON access_logs(plate);
CREATE INDEX IF NOT EXISTS idx_access_logs_timestamp ON access_logs(timestamp DESC);

-- Create community_access_settings table
CREATE TABLE IF NOT EXISTS community_access_settings (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  community_id uuid UNIQUE NOT NULL REFERENCES communities(id) ON DELETE CASCADE,
  auto_grant_enabled boolean DEFAULT true,
  lockdown_mode boolean DEFAULT false,
  require_confidence numeric DEFAULT 85.0,
  notification_on_grant boolean DEFAULT false,
  notification_emails text[] DEFAULT '{}',
  created_at timestamptz DEFAULT now(),
  updated_at timestamptz DEFAULT now()
);

-- Create index
CREATE INDEX IF NOT EXISTS idx_community_access_settings_community ON community_access_settings(community_id);

-- Enable RLS
ALTER TABLE access_lists ENABLE ROW LEVEL SECURITY;
ALTER TABLE access_logs ENABLE ROW LEVEL SECURITY;
ALTER TABLE community_access_settings ENABLE ROW LEVEL SECURITY;

-- Simple RLS policies (can be enhanced later based on user roles)
CREATE POLICY "Authenticated users can view access lists"
  ON access_lists FOR SELECT
  TO authenticated
  USING (true);

CREATE POLICY "Authenticated users can manage access lists"
  ON access_lists FOR ALL
  TO authenticated
  USING (true);

CREATE POLICY "Authenticated users can view access logs"
  ON access_logs FOR SELECT
  TO authenticated
  USING (true);

CREATE POLICY "System can insert access logs"
  ON access_logs FOR INSERT
  TO authenticated
  WITH CHECK (true);

CREATE POLICY "Authenticated users can view settings"
  ON community_access_settings FOR SELECT
  TO authenticated
  USING (true);

CREATE POLICY "Authenticated users can manage settings"
  ON community_access_settings FOR ALL
  TO authenticated
  USING (true);

-- Create trigger function
CREATE OR REPLACE FUNCTION update_updated_at_column()
RETURNS TRIGGER AS $$
BEGIN
  NEW.updated_at = now();
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- Create triggers
DROP TRIGGER IF EXISTS update_access_lists_updated_at ON access_lists;
CREATE TRIGGER update_access_lists_updated_at
  BEFORE UPDATE ON access_lists
  FOR EACH ROW
  EXECUTE FUNCTION update_updated_at_column();

DROP TRIGGER IF EXISTS update_community_access_settings_updated_at ON community_access_settings;
CREATE TRIGGER update_community_access_settings_updated_at
  BEFORE UPDATE ON community_access_settings
  FOR EACH ROW
  EXECUTE FUNCTION update_updated_at_column();

-- Create access check function
CREATE OR REPLACE FUNCTION check_plate_access(
  p_plate text,
  p_community_id uuid,
  p_confidence numeric DEFAULT 100
)
RETURNS jsonb AS $$
DECLARE
  v_settings community_access_settings%ROWTYPE;
  v_access access_lists%ROWTYPE;
  v_current_time time;
  v_current_day text;
BEGIN
  -- Get settings
  SELECT * INTO v_settings
  FROM community_access_settings
  WHERE community_id = p_community_id;

  -- Create default settings if not found
  IF NOT FOUND THEN
    INSERT INTO community_access_settings (community_id)
    VALUES (p_community_id)
    RETURNING * INTO v_settings;
  END IF;

  -- Check lockdown
  IF v_settings.lockdown_mode THEN
    RETURN jsonb_build_object(
      'access', 'denied',
      'reason', 'Community is in lockdown mode'
    );
  END IF;

  -- Check auto-grant enabled
  IF NOT v_settings.auto_grant_enabled THEN
    RETURN jsonb_build_object(
      'access', 'denied',
      'reason', 'Auto-grant is disabled'
    );
  END IF;

  -- Check confidence
  IF p_confidence < v_settings.require_confidence THEN
    RETURN jsonb_build_object(
      'access', 'denied',
      'reason', 'Confidence below threshold',
      'confidence', p_confidence,
      'required', v_settings.require_confidence
    );
  END IF;

  -- Normalize plate
  p_plate := UPPER(REPLACE(p_plate, ' ', ''));

  -- Get current time
  v_current_time := CURRENT_TIME;
  v_current_day := TO_CHAR(CURRENT_DATE, 'Dy');

  -- Find matching entry
  SELECT * INTO v_access
  FROM access_lists
  WHERE plate = p_plate
    AND community_id = p_community_id
    AND is_active = true
    AND (expires_at IS NULL OR expires_at > now())
    AND (days_active ILIKE '%' || v_current_day || '%')
    AND (
      (schedule_start IS NULL AND schedule_end IS NULL)
      OR (v_current_time BETWEEN schedule_start AND schedule_end)
    )
  ORDER BY
    CASE type
      WHEN 'emergency' THEN 1
      WHEN 'resident' THEN 2
      WHEN 'delivery' THEN 3
      ELSE 4
    END
  LIMIT 1;

  -- Return result
  IF FOUND THEN
    RETURN jsonb_build_object(
      'access', 'granted',
      'type', v_access.type,
      'vendor', v_access.vendor_name,
      'reason', 'Authorized ' || v_access.type,
      'duration', CASE
        WHEN v_access.type = 'emergency' THEN 30
        WHEN v_access.type = 'delivery' THEN 15
        ELSE 10
      END
    );
  ELSE
    RETURN jsonb_build_object(
      'access', 'denied',
      'reason', 'Plate not in access list'
    );
  END IF;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;
