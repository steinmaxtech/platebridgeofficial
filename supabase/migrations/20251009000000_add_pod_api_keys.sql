/*
  # Add Pod API Keys Table

  1. New Tables
    - `pod_api_keys`
      - `id` (uuid, primary key)
      - `name` (text) - Friendly name for the API key
      - `site_id` (uuid) - Which site this key is for
      - `pod_id` (text) - Which pod this key is for
      - `key_hash` (text) - SHA-256 hash of the API key
      - `created_by` (uuid) - User who created the key
      - `created_at` (timestamptz)
      - `last_used_at` (timestamptz)
      - `revoked_at` (timestamptz) - When key was revoked, if applicable

  2. Security
    - Enable RLS on `pod_api_keys` table
    - Add policies for authenticated users to manage their API keys
    - API keys are hashed for security

  3. Indexes
    - Index on key_hash for fast lookups during authentication
    - Index on site_id for filtering
*/

-- Create pod_api_keys table
CREATE TABLE IF NOT EXISTS pod_api_keys (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  name text NOT NULL,
  site_id uuid NOT NULL REFERENCES sites(id) ON DELETE CASCADE,
  pod_id text NOT NULL,
  key_hash text NOT NULL,
  created_by uuid NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  created_at timestamptz DEFAULT now(),
  last_used_at timestamptz,
  revoked_at timestamptz,
  UNIQUE(key_hash)
);

-- Create index for fast API key lookups
CREATE INDEX IF NOT EXISTS idx_pod_api_keys_key_hash ON pod_api_keys(key_hash);
CREATE INDEX IF NOT EXISTS idx_pod_api_keys_site_id ON pod_api_keys(site_id);

-- Enable RLS
ALTER TABLE pod_api_keys ENABLE ROW LEVEL SECURITY;

-- Policy: Users can view API keys for sites they have access to
CREATE POLICY "Users can view API keys for their sites"
  ON pod_api_keys
  FOR SELECT
  TO authenticated
  USING (
    EXISTS (
      SELECT 1 FROM memberships m
      WHERE m.user_id = auth.uid()
      AND (
        m.community_id IN (
          SELECT community_id FROM sites WHERE id = pod_api_keys.site_id
        )
        OR m.company_id IN (
          SELECT c.id FROM companies c
          JOIN sites s ON s.community_id IN (
            SELECT id FROM communities WHERE company_id = c.id
          )
          WHERE s.id = pod_api_keys.site_id
        )
      )
    )
  );

-- Policy: Users can create API keys for sites they have access to
CREATE POLICY "Users can create API keys for their sites"
  ON pod_api_keys
  FOR INSERT
  TO authenticated
  WITH CHECK (
    EXISTS (
      SELECT 1 FROM memberships m
      WHERE m.user_id = auth.uid()
      AND (
        m.community_id IN (
          SELECT community_id FROM sites WHERE id = pod_api_keys.site_id
        )
        OR m.company_id IN (
          SELECT c.id FROM companies c
          JOIN sites s ON s.community_id IN (
            SELECT id FROM communities WHERE company_id = c.id
          )
          WHERE s.id = pod_api_keys.site_id
        )
      )
    )
    AND created_by = auth.uid()
  );

-- Policy: Users can delete API keys they created
CREATE POLICY "Users can delete their API keys"
  ON pod_api_keys
  FOR DELETE
  TO authenticated
  USING (created_by = auth.uid());

-- Add comment
COMMENT ON TABLE pod_api_keys IS 'API keys for pod authentication with the portal';
