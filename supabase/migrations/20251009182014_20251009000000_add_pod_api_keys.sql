/*
  # Add Pod API Keys Table with Community Support

  1. New Tables
    - `pod_api_keys`
      - `id` (uuid, primary key)
      - `name` (text) - Friendly name for the API key
      - `community_id` (uuid) - Which community this POD is in
      - `pod_id` (text) - Unique identifier for the pod
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
    - Index on community_id for filtering
*/

-- Create pod_api_keys table
CREATE TABLE IF NOT EXISTS pod_api_keys (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  name text NOT NULL,
  community_id uuid NOT NULL REFERENCES communities(id) ON DELETE CASCADE,
  pod_id text NOT NULL,
  key_hash text NOT NULL,
  created_by uuid NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  created_at timestamptz DEFAULT now() NOT NULL,
  last_used_at timestamptz,
  revoked_at timestamptz,
  UNIQUE(key_hash)
);

-- Create index for fast API key lookups
CREATE INDEX IF NOT EXISTS idx_pod_api_keys_key_hash ON pod_api_keys(key_hash);
CREATE INDEX IF NOT EXISTS idx_pod_api_keys_community_id ON pod_api_keys(community_id);

-- Enable RLS
ALTER TABLE pod_api_keys ENABLE ROW LEVEL SECURITY;

-- Policy: Users can view POD API keys for their communities
CREATE POLICY "Users can view POD API keys for their communities"
  ON pod_api_keys FOR SELECT
  TO authenticated
  USING (
    EXISTS (
      SELECT 1 FROM communities
      JOIN memberships ON memberships.company_id = communities.company_id
      WHERE communities.id = pod_api_keys.community_id
      AND memberships.user_id = auth.uid()
      AND memberships.role IN ('owner', 'admin', 'manager')
    )
  );

-- Policy: Users can create POD API keys for their communities
CREATE POLICY "Users can create POD API keys for their communities"
  ON pod_api_keys FOR INSERT
  TO authenticated
  WITH CHECK (
    EXISTS (
      SELECT 1 FROM communities
      JOIN memberships ON memberships.company_id = communities.company_id
      WHERE communities.id = pod_api_keys.community_id
      AND memberships.user_id = auth.uid()
      AND memberships.role IN ('owner', 'admin', 'manager')
    )
    AND created_by = auth.uid()
  );

-- Policy: Users can update POD API keys for their communities
CREATE POLICY "Users can update POD API keys for their communities"
  ON pod_api_keys FOR UPDATE
  TO authenticated
  USING (
    EXISTS (
      SELECT 1 FROM communities
      JOIN memberships ON memberships.company_id = communities.company_id
      WHERE communities.id = pod_api_keys.community_id
      AND memberships.user_id = auth.uid()
      AND memberships.role IN ('owner', 'admin', 'manager')
    )
  )
  WITH CHECK (
    EXISTS (
      SELECT 1 FROM communities
      JOIN memberships ON memberships.company_id = communities.company_id
      WHERE communities.id = pod_api_keys.community_id
      AND memberships.user_id = auth.uid()
      AND memberships.role IN ('owner', 'admin', 'manager')
    )
  );

-- Policy: Users can delete POD API keys for their communities
CREATE POLICY "Users can delete POD API keys for their communities"
  ON pod_api_keys FOR DELETE
  TO authenticated
  USING (
    EXISTS (
      SELECT 1 FROM communities
      JOIN memberships ON memberships.company_id = communities.company_id
      WHERE communities.id = pod_api_keys.community_id
      AND memberships.user_id = auth.uid()
      AND memberships.role IN ('owner', 'admin', 'manager')
    )
  );

-- Add comment
COMMENT ON TABLE pod_api_keys IS 'API keys for POD authentication with the portal';
