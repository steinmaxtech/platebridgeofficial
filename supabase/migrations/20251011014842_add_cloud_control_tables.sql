/*
  Add Cloud Control Tables for POD Management

  1. New Tables
    - pod_commands: Remote command queue
    - pod_detections: Plate detection events

  2. Pod Table Enhancements
    - Hardware info and metrics columns

  3. Security
    - RLS policies for all tables
*/

-- Enhance pods table with cloud control fields
DO $$
BEGIN
  -- Add serial_number if not exists
  IF NOT EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_name = 'pods' AND column_name = 'serial_number'
  ) THEN
    ALTER TABLE pods ADD COLUMN serial_number text;
  END IF;

  -- Add hardware_model if not exists
  IF NOT EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_name = 'pods' AND column_name = 'hardware_model'
  ) THEN
    ALTER TABLE pods ADD COLUMN hardware_model text DEFAULT 'PB-M1';
  END IF;

  -- Add cpu_usage if not exists
  IF NOT EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_name = 'pods' AND column_name = 'cpu_usage'
  ) THEN
    ALTER TABLE pods ADD COLUMN cpu_usage numeric;
  END IF;

  -- Add memory_usage if not exists
  IF NOT EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_name = 'pods' AND column_name = 'memory_usage'
  ) THEN
    ALTER TABLE pods ADD COLUMN memory_usage numeric;
  END IF;

  -- Add disk_usage if not exists
  IF NOT EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_name = 'pods' AND column_name = 'disk_usage'
  ) THEN
    ALTER TABLE pods ADD COLUMN disk_usage numeric;
  END IF;

  -- Add temperature if not exists
  IF NOT EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_name = 'pods' AND column_name = 'temperature'
  ) THEN
    ALTER TABLE pods ADD COLUMN temperature numeric;
  END IF;

  -- Add public_url if not exists
  IF NOT EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_name = 'pods' AND column_name = 'public_url'
  ) THEN
    ALTER TABLE pods ADD COLUMN public_url text;
  END IF;

  -- Add software_version if not exists (in addition to firmware_version)
  IF NOT EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_name = 'pods' AND column_name = 'software_version'
  ) THEN
    ALTER TABLE pods ADD COLUMN software_version text DEFAULT '1.0.0';
  END IF;

  -- Add mac_address if not exists
  IF NOT EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_name = 'pods' AND column_name = 'mac_address'
  ) THEN
    ALTER TABLE pods ADD COLUMN mac_address text;
  END IF;
END $$;

-- Create pod_commands table
CREATE TABLE IF NOT EXISTS pod_commands (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  pod_id uuid NOT NULL REFERENCES pods(id) ON DELETE CASCADE,
  command text NOT NULL CHECK (command IN ('restart', 'update', 'reboot', 'refresh_config', 'test_camera', 'clear_cache')),
  status text NOT NULL DEFAULT 'queued' CHECK (status IN ('queued', 'sent', 'acknowledged', 'completed', 'failed')),
  parameters jsonb DEFAULT '{}',
  result jsonb DEFAULT '{}',
  error_message text,
  created_by uuid NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  created_at timestamptz DEFAULT now(),
  sent_at timestamptz,
  executed_at timestamptz,
  completed_at timestamptz
);

-- Create pod_detections table
CREATE TABLE IF NOT EXISTS pod_detections (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  pod_id uuid NOT NULL REFERENCES pods(id) ON DELETE CASCADE,
  camera_id uuid REFERENCES cameras(id) ON DELETE SET NULL,
  plate text NOT NULL,
  confidence numeric NOT NULL CHECK (confidence >= 0 AND confidence <= 1),
  image_url text,
  metadata jsonb DEFAULT '{}',
  detected_at timestamptz NOT NULL,
  created_at timestamptz DEFAULT now()
);

-- Create indexes for performance
CREATE INDEX IF NOT EXISTS idx_pod_commands_pod_id ON pod_commands(pod_id);
CREATE INDEX IF NOT EXISTS idx_pod_commands_status ON pod_commands(status) WHERE status IN ('queued', 'sent');
CREATE INDEX IF NOT EXISTS idx_pod_detections_pod_id ON pod_detections(pod_id);
CREATE INDEX IF NOT EXISTS idx_pod_detections_camera_id ON pod_detections(camera_id);
CREATE INDEX IF NOT EXISTS idx_pod_detections_detected_at ON pod_detections(detected_at DESC);
CREATE INDEX IF NOT EXISTS idx_pod_detections_plate ON pod_detections(plate);
CREATE INDEX IF NOT EXISTS idx_pods_serial_number ON pods(serial_number);
CREATE INDEX IF NOT EXISTS idx_pods_status ON pods(status);

-- Enable RLS
ALTER TABLE pod_commands ENABLE ROW LEVEL SECURITY;
ALTER TABLE pod_detections ENABLE ROW LEVEL SECURITY;

-- RLS Policies for pod_commands

-- Admins can view all commands
CREATE POLICY "Admins can view commands for their communities"
  ON pod_commands FOR SELECT
  TO authenticated
  USING (
    EXISTS (
      SELECT 1 FROM pods
      JOIN sites ON sites.id = pods.site_id
      JOIN communities ON communities.id = sites.community_id
      JOIN memberships ON memberships.company_id = communities.company_id
      WHERE pods.id = pod_commands.pod_id
      AND memberships.user_id = auth.uid()
      AND memberships.role IN ('owner', 'admin', 'manager')
    )
  );

-- Admins can create commands
CREATE POLICY "Admins can create commands for their communities"
  ON pod_commands FOR INSERT
  TO authenticated
  WITH CHECK (
    EXISTS (
      SELECT 1 FROM pods
      JOIN sites ON sites.id = pods.site_id
      JOIN communities ON communities.id = sites.community_id
      JOIN memberships ON memberships.company_id = communities.company_id
      WHERE pods.id = pod_commands.pod_id
      AND memberships.user_id = auth.uid()
      AND memberships.role IN ('owner', 'admin', 'manager')
    )
    AND created_by = auth.uid()
  );

-- Admins can update command status
CREATE POLICY "Admins can update commands for their communities"
  ON pod_commands FOR UPDATE
  TO authenticated
  USING (
    EXISTS (
      SELECT 1 FROM pods
      JOIN sites ON sites.id = pods.site_id
      JOIN communities ON communities.id = sites.community_id
      JOIN memberships ON memberships.company_id = communities.company_id
      WHERE pods.id = pod_commands.pod_id
      AND memberships.user_id = auth.uid()
      AND memberships.role IN ('owner', 'admin', 'manager')
    )
  );

-- RLS Policies for pod_detections

-- Community members can view detections
CREATE POLICY "Users can view detections for their communities"
  ON pod_detections FOR SELECT
  TO authenticated
  USING (
    EXISTS (
      SELECT 1 FROM pods
      JOIN sites ON sites.id = pods.site_id
      JOIN communities ON communities.id = sites.community_id
      JOIN memberships ON memberships.company_id = communities.company_id
      WHERE pods.id = pod_detections.pod_id
      AND memberships.user_id = auth.uid()
    )
  );

-- PODs can insert detections (via service role key)
CREATE POLICY "Service role can insert detections"
  ON pod_detections FOR INSERT
  TO authenticated
  WITH CHECK (true);

-- Add comments
COMMENT ON TABLE pod_commands IS 'Command queue for remote POD management from cloud portal';
COMMENT ON TABLE pod_detections IS 'Plate detection events uploaded from PODs';
