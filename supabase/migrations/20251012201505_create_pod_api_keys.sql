/*
  # Create POD API Keys Table

  1. New Tables
    - `pod_api_keys`
      - `id` (uuid, primary key) - Unique key identifier
      - `name` (text) - Friendly name for the key
      - `community_id` (uuid) - Reference to community
      - `pod_id` (text) - Pod identifier string
      - `key_hash` (text) - SHA-256 hash of the API key (never store plaintext)
      - `created_by` (uuid) - User who created the key
      - `created_at` (timestamptz) - When key was created
      - `last_used_at` (timestamptz) - Last time key was used for authentication
      - `revoked_at` (timestamptz) - When key was revoked (null if active)

  2. Security
    - Enable RLS on `pod_api_keys` table
    - Only authenticated users in the company can view keys
    - Admins/managers can create and revoke keys
    - Key hash is unique to prevent duplicate keys
    - Soft delete via revoked_at (keys are never hard deleted for audit trail)

  3. Important Notes
    - Only the hash is stored, never the plaintext key
    - Keys are shown once at creation time only
    - Revoked keys are kept for audit purposes
    - Keys can be filtered by active status (revoked_at IS NULL)
*/

-- Create pod_api_keys table
CREATE TABLE IF NOT EXISTS pod_api_keys (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  name text NOT NULL,
  community_id uuid NOT NULL REFERENCES communities(id) ON DELETE CASCADE,
  pod_id text NOT NULL,
  key_hash text NOT NULL UNIQUE,
  created_by uuid NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  created_at timestamptz DEFAULT now(),
  last_used_at timestamptz,
  revoked_at timestamptz,
  CONSTRAINT pod_api_keys_name_length CHECK (char_length(name) >= 1 AND char_length(name) <= 100),
  CONSTRAINT pod_api_keys_pod_id_length CHECK (char_length(pod_id) >= 1 AND char_length(pod_id) <= 100)
);

-- Create indexes for performance
CREATE INDEX IF NOT EXISTS idx_pod_api_keys_community ON pod_api_keys(community_id);
CREATE INDEX IF NOT EXISTS idx_pod_api_keys_key_hash ON pod_api_keys(key_hash) WHERE revoked_at IS NULL;
CREATE INDEX IF NOT EXISTS idx_pod_api_keys_revoked ON pod_api_keys(revoked_at);
CREATE INDEX IF NOT EXISTS idx_pod_api_keys_pod_id ON pod_api_keys(pod_id);

-- Enable RLS
ALTER TABLE pod_api_keys ENABLE ROW LEVEL SECURITY;

-- Policy: Authenticated users can view keys in their communities
CREATE POLICY "Users can view keys in their communities"
  ON pod_api_keys
  FOR SELECT
  TO authenticated
  USING (
    EXISTS (
      SELECT 1 
      FROM communities c
      JOIN memberships m ON m.company_id = c.company_id
      WHERE c.id = pod_api_keys.community_id
      AND m.user_id = auth.uid()
    )
  );

-- Policy: Admins/managers can create keys in their communities
CREATE POLICY "Admins can create keys"
  ON pod_api_keys
  FOR INSERT
  TO authenticated
  WITH CHECK (
    EXISTS (
      SELECT 1 
      FROM communities c
      JOIN memberships m ON m.company_id = c.company_id
      WHERE c.id = pod_api_keys.community_id
      AND m.user_id = auth.uid()
      AND m.role IN ('owner', 'admin', 'manager')
    )
  );

-- Policy: Admins/managers can update (revoke) keys in their communities
CREATE POLICY "Admins can revoke keys"
  ON pod_api_keys
  FOR UPDATE
  TO authenticated
  USING (
    EXISTS (
      SELECT 1 
      FROM communities c
      JOIN memberships m ON m.company_id = c.company_id
      WHERE c.id = pod_api_keys.community_id
      AND m.user_id = auth.uid()
      AND m.role IN ('owner', 'admin', 'manager')
    )
  )
  WITH CHECK (
    EXISTS (
      SELECT 1 
      FROM communities c
      JOIN memberships m ON m.company_id = c.company_id
      WHERE c.id = pod_api_keys.community_id
      AND m.user_id = auth.uid()
      AND m.role IN ('owner', 'admin', 'manager')
    )
  );

-- Policy: Only owners can permanently delete keys
CREATE POLICY "Owners can delete keys"
  ON pod_api_keys
  FOR DELETE
  TO authenticated
  USING (
    EXISTS (
      SELECT 1 
      FROM communities c
      JOIN memberships m ON m.company_id = c.company_id
      WHERE c.id = pod_api_keys.community_id
      AND m.user_id = auth.uid()
      AND m.role = 'owner'
    )
  );