/*
  # Restructure PODs to use Communities instead of Sites

  1. Changes
    - Drop site_id column from pod_api_keys table
    - Add community_id column to pod_api_keys table
    - Update foreign key to reference communities instead of sites
    - Update RLS policies to work with communities
    - Migrate any existing POD data to use communities

  2. Security
    - Update RLS policies to check community membership
    - Maintain same security level with new structure
*/

-- First, check if we have any existing POD data and migrate it
DO $$
BEGIN
  -- Add community_id column if it doesn't exist
  IF NOT EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_name = 'pod_api_keys' AND column_name = 'community_id'
  ) THEN
    ALTER TABLE pod_api_keys ADD COLUMN community_id uuid;
  END IF;

  -- Migrate existing data from sites to communities
  UPDATE pod_api_keys
  SET community_id = sites.community_id
  FROM sites
  WHERE pod_api_keys.site_id = sites.id
  AND pod_api_keys.community_id IS NULL;
END $$;

-- Add foreign key constraint for community_id
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM information_schema.table_constraints
    WHERE constraint_name = 'pod_api_keys_community_id_fkey'
  ) THEN
    ALTER TABLE pod_api_keys
    ADD CONSTRAINT pod_api_keys_community_id_fkey
    FOREIGN KEY (community_id) REFERENCES communities(id) ON DELETE CASCADE;
  END IF;
END $$;

-- Drop the old site_id column if it exists
DO $$
BEGIN
  IF EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_name = 'pod_api_keys' AND column_name = 'site_id'
  ) THEN
    ALTER TABLE pod_api_keys DROP COLUMN site_id;
  END IF;
END $$;

-- Make community_id NOT NULL after migration
ALTER TABLE pod_api_keys ALTER COLUMN community_id SET NOT NULL;

-- Drop old RLS policies
DROP POLICY IF EXISTS "Users can view POD API keys for their sites" ON pod_api_keys;
DROP POLICY IF EXISTS "Users can create POD API keys for their sites" ON pod_api_keys;
DROP POLICY IF EXISTS "Users can update POD API keys for their sites" ON pod_api_keys;
DROP POLICY IF EXISTS "Users can delete POD API keys for their sites" ON pod_api_keys;

-- Create new RLS policies for community-based access
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
  );

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
