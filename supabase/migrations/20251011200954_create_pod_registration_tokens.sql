/*
  # POD Registration Tokens & Transfer System

  ## Overview
  Creates a secure token-based POD registration system. Only devices with a valid 
  registration token can register with the portal.

  ## 1. New Tables
    - `pod_registration_tokens`
      - `id` (uuid, primary key) - Token UUID
      - `site_id` (uuid, foreign key) - Site where POD will be registered
      - `token` (text, unique) - One-time registration token
      - `expires_at` (timestamptz) - Token expiration time
      - `used_at` (timestamptz, nullable) - When token was used (null = unused)
      - `used_by_serial` (text, nullable) - Serial number of POD that used token
      - `used_by_mac` (text, nullable) - MAC address of POD that used token
      - `pod_id` (uuid, nullable, foreign key) - POD created with this token
      - `created_by` (uuid, foreign key) - User who created token
      - `created_at` (timestamptz) - Token creation time
      - `max_uses` (integer) - Number of times token can be used (default 1)
      - `use_count` (integer) - Number of times token has been used
      - `notes` (text, nullable) - Admin notes about token

    - `pod_transfers`
      - `id` (uuid, primary key) - Transfer record ID
      - `pod_id` (uuid, foreign key) - POD being transferred
      - `from_site_id` (uuid, nullable) - Original site
      - `to_site_id` (uuid) - Destination site
      - `transferred_by` (uuid, foreign key) - User who initiated transfer
      - `transferred_at` (timestamptz) - Transfer timestamp
      - `reason` (text, nullable) - Reason for transfer
      - `old_api_key_hash` (text) - Previous API key (invalidated)
      - `new_api_key_hash` (text) - New API key issued

  ## 2. Security
    - Enable RLS on both tables
    - Only authenticated users in the company can view tokens
    - Only admins/owners can create tokens
    - Tokens can be used during registration (one-time use)
    - Transfer history is immutable (no deletes)

  ## 3. Token System
    - Tokens are single-use by default
    - Tokens expire after 24 hours
    - Tokens are invalidated after use
    - Serial number and MAC are recorded when used
*/

-- Create pod_registration_tokens table
CREATE TABLE IF NOT EXISTS pod_registration_tokens (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  site_id uuid NOT NULL REFERENCES sites(id) ON DELETE CASCADE,
  token text UNIQUE NOT NULL,
  expires_at timestamptz NOT NULL DEFAULT (now() + interval '24 hours'),
  used_at timestamptz,
  used_by_serial text,
  used_by_mac text,
  pod_id uuid REFERENCES pods(id) ON DELETE SET NULL,
  created_by uuid NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  created_at timestamptz DEFAULT now(),
  max_uses integer DEFAULT 1,
  use_count integer DEFAULT 0,
  notes text,
  CONSTRAINT valid_use_count CHECK (use_count <= max_uses),
  CONSTRAINT used_when_pod_exists CHECK ((pod_id IS NULL) OR (used_at IS NOT NULL))
);

-- Create pod_transfers table
CREATE TABLE IF NOT EXISTS pod_transfers (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  pod_id uuid NOT NULL REFERENCES pods(id) ON DELETE CASCADE,
  from_site_id uuid REFERENCES sites(id) ON DELETE SET NULL,
  to_site_id uuid NOT NULL REFERENCES sites(id) ON DELETE CASCADE,
  transferred_by uuid NOT NULL REFERENCES auth.users(id) ON DELETE SET NULL,
  transferred_at timestamptz DEFAULT now(),
  reason text,
  old_api_key_hash text,
  new_api_key_hash text NOT NULL
);

-- Indexes for performance
CREATE INDEX IF NOT EXISTS idx_pod_registration_tokens_site_id ON pod_registration_tokens(site_id);
CREATE INDEX IF NOT EXISTS idx_pod_registration_tokens_token ON pod_registration_tokens(token);
CREATE INDEX IF NOT EXISTS idx_pod_registration_tokens_expires_at ON pod_registration_tokens(expires_at);
CREATE INDEX IF NOT EXISTS idx_pod_registration_tokens_used_at ON pod_registration_tokens(used_at);
CREATE INDEX IF NOT EXISTS idx_pod_transfers_pod_id ON pod_transfers(pod_id);
CREATE INDEX IF NOT EXISTS idx_pod_transfers_from_site_id ON pod_transfers(from_site_id);
CREATE INDEX IF NOT EXISTS idx_pod_transfers_to_site_id ON pod_transfers(to_site_id);

-- Enable RLS
ALTER TABLE pod_registration_tokens ENABLE ROW LEVEL SECURITY;
ALTER TABLE pod_transfers ENABLE ROW LEVEL SECURITY;

-- RLS Policies for pod_registration_tokens

-- Users can view tokens for sites in their company
CREATE POLICY "Users can view registration tokens for their sites"
  ON pod_registration_tokens FOR SELECT
  TO authenticated
  USING (
    EXISTS (
      SELECT 1 FROM sites s
      JOIN communities c ON c.id = s.community_id
      JOIN memberships m ON m.company_id = c.company_id
      WHERE s.id = pod_registration_tokens.site_id
      AND m.user_id = auth.uid()
      AND m.role IN ('owner', 'admin', 'manager')
    )
  );

-- Admins/owners can create tokens
CREATE POLICY "Admins can create registration tokens"
  ON pod_registration_tokens FOR INSERT
  TO authenticated
  WITH CHECK (
    EXISTS (
      SELECT 1 FROM sites s
      JOIN communities c ON c.id = s.community_id
      JOIN memberships m ON m.company_id = c.company_id
      WHERE s.id = pod_registration_tokens.site_id
      AND m.user_id = auth.uid()
      AND m.role IN ('owner', 'admin', 'manager')
    )
  );

-- Allow updates to mark token as used
CREATE POLICY "System can update token usage"
  ON pod_registration_tokens FOR UPDATE
  TO authenticated
  USING (true)
  WITH CHECK (
    used_at IS NOT NULL AND 
    use_count <= max_uses
  );

-- RLS Policies for pod_transfers

-- Users can view transfer history for PODs in their company
CREATE POLICY "Users can view transfer history"
  ON pod_transfers FOR SELECT
  TO authenticated
  USING (
    EXISTS (
      SELECT 1 FROM pods p
      JOIN sites s ON s.id = p.site_id
      JOIN communities c ON c.id = s.community_id
      JOIN memberships m ON m.company_id = c.company_id
      WHERE p.id = pod_transfers.pod_id
      AND m.user_id = auth.uid()
    )
  );

-- Only admins/owners can create transfers
CREATE POLICY "Admins can create transfers"
  ON pod_transfers FOR INSERT
  TO authenticated
  WITH CHECK (
    EXISTS (
      SELECT 1 FROM pods p
      JOIN sites s ON s.id = p.site_id
      JOIN communities c ON c.id = s.community_id
      JOIN memberships m ON m.company_id = c.company_id
      WHERE p.id = pod_transfers.pod_id
      AND m.user_id = auth.uid()
      AND m.role IN ('owner', 'admin')
    )
  );

-- Function to clean up expired tokens
CREATE OR REPLACE FUNCTION cleanup_expired_tokens()
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
BEGIN
  DELETE FROM pod_registration_tokens
  WHERE expires_at < now()
  AND used_at IS NULL;
END;
$$;