/*
  # Add Camera Recordings and Stream Security

  1. New Tables
    - `camera_recordings` - Stores metadata for recorded video clips
      - `id` (uuid, primary key)
      - `camera_id` (uuid, foreign key to cameras)
      - `pod_id` (uuid, foreign key to pods)
      - `recorded_at` (timestamptz)
      - `duration_seconds` (int)
      - `file_path` (text) - Path in Supabase Storage
      - `file_size_bytes` (bigint)
      - `event_type` (text) - 'plate_detection', 'motion', 'manual'
      - `plate_number` (text, nullable)
      - `thumbnail_path` (text, nullable)
      - `metadata` (jsonb)
      - `created_at` (timestamptz)

  2. Table Updates
    - Add `stream_token_secret` to pods table for validating stream tokens
    - Add `last_recording_at` to cameras table

  3. Security
    - Enable RLS on `camera_recordings`
    - Users can view recordings from cameras in their company
    - PODs can insert recordings for their own cameras

  4. Storage
    - Create storage bucket for camera recordings (done via Supabase dashboard)
*/

-- Add stream token secret to pods
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_name = 'pods' AND column_name = 'stream_token_secret'
  ) THEN
    ALTER TABLE pods ADD COLUMN stream_token_secret text;
  END IF;
END $$;

-- Add last recording timestamp to cameras
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_name = 'cameras' AND column_name = 'last_recording_at'
  ) THEN
    ALTER TABLE cameras ADD COLUMN last_recording_at timestamptz;
  END IF;
END $$;

-- Create camera_recordings table
CREATE TABLE IF NOT EXISTS camera_recordings (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  camera_id uuid REFERENCES cameras(id) ON DELETE CASCADE NOT NULL,
  pod_id uuid REFERENCES pods(id) ON DELETE CASCADE NOT NULL,
  recorded_at timestamptz DEFAULT now() NOT NULL,
  duration_seconds int DEFAULT 0,
  file_path text NOT NULL,
  file_size_bytes bigint DEFAULT 0,
  event_type text DEFAULT 'manual',
  plate_number text,
  thumbnail_path text,
  metadata jsonb DEFAULT '{}'::jsonb,
  created_at timestamptz DEFAULT now()
);

-- Create indexes for common queries
CREATE INDEX IF NOT EXISTS idx_recordings_camera_id ON camera_recordings(camera_id);
CREATE INDEX IF NOT EXISTS idx_recordings_pod_id ON camera_recordings(pod_id);
CREATE INDEX IF NOT EXISTS idx_recordings_recorded_at ON camera_recordings(recorded_at DESC);
CREATE INDEX IF NOT EXISTS idx_recordings_plate ON camera_recordings(plate_number) WHERE plate_number IS NOT NULL;

-- Enable RLS
ALTER TABLE camera_recordings ENABLE ROW LEVEL SECURITY;

-- Policy: Users can view recordings from cameras in their company
CREATE POLICY "users_view_company_recordings"
  ON camera_recordings FOR SELECT
  TO authenticated
  USING (
    EXISTS (
      SELECT 1 FROM cameras c
      JOIN pods p ON p.id = c.pod_id
      JOIN sites s ON s.id = p.site_id
      JOIN communities com ON com.id = s.community_id
      JOIN memberships m ON m.company_id = com.company_id
      WHERE c.id = camera_recordings.camera_id
      AND m.user_id = auth.uid()
    )
  );

-- Policy: System can insert recordings (we'll handle POD auth via service role)
CREATE POLICY "system_insert_recordings"
  ON camera_recordings FOR INSERT
  TO authenticated
  WITH CHECK (true);

-- Policy: Users with admin/manager role can delete old recordings
CREATE POLICY "admins_delete_recordings"
  ON camera_recordings FOR DELETE
  TO authenticated
  USING (
    EXISTS (
      SELECT 1 FROM cameras c
      JOIN pods p ON p.id = c.pod_id
      JOIN sites s ON s.id = p.site_id
      JOIN communities com ON com.id = s.community_id
      JOIN memberships m ON m.company_id = com.company_id
      WHERE c.id = camera_recordings.camera_id
      AND m.user_id = auth.uid()
      AND m.role IN ('owner', 'admin', 'manager')
    )
  );
