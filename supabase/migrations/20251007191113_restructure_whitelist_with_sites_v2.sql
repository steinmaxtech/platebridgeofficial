/*
  # Restructure Whitelist with Sites Assignment
  
  ## Overview
  This migration restructures the whitelist table to associate entries with communities
  and adds a sites array to track which pods (up to 100 per community) each vehicle can access.
  
  ## Changes to whitelist table
  
  1. Update Structure
    - Change `property_id` reference to `community_id` (references communities table)
    - Add `site_ids` (text[]) - Array of site IDs the vehicle can access
    - Keep existing fields: plate, unit, tenant, vehicle, starts, ends, days, time_start, time_end, enabled, notes
  
  2. Data Migration
    - The site_id foreign key is removed (was added in a previous migration)
    - Update to use community_id instead
  
  ## Security
  - Update RLS policies to use community membership through companies
  - Policies check if user has access to the community's parent company
  
  ## Notes
  - Sites (pods) are already structured under communities (up to 100 per community)
  - This allows better organization when managing thousands of residents across communities
  - Each whitelist entry is tied to a community and can be assigned to multiple sites within that community
*/

-- Drop old RLS policies first (they depend on the columns)
DROP POLICY IF EXISTS "Users can view whitelist entries for their property" ON whitelist;
DROP POLICY IF EXISTS "Users can insert whitelist entries for their property" ON whitelist;
DROP POLICY IF EXISTS "Users can update whitelist entries for their property" ON whitelist;
DROP POLICY IF EXISTS "Users can delete whitelist entries for their property" ON whitelist;
DROP POLICY IF EXISTS "Users can view whitelist for accessible properties" ON whitelist;
DROP POLICY IF EXISTS "Managers can insert whitelist for their property" ON whitelist;
DROP POLICY IF EXISTS "Managers can update whitelist for their property" ON whitelist;
DROP POLICY IF EXISTS "Managers can delete whitelist for their property" ON whitelist;

-- Drop old property_id foreign key if exists
DO $$
BEGIN
  IF EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_name = 'whitelist' AND column_name = 'property_id'
  ) THEN
    ALTER TABLE whitelist DROP COLUMN property_id CASCADE;
  END IF;
END $$;

-- Drop site_id column if exists (was single site reference)
DO $$
BEGIN
  IF EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_name = 'whitelist' AND column_name = 'site_id'
  ) THEN
    ALTER TABLE whitelist DROP COLUMN site_id CASCADE;
  END IF;
END $$;

-- Add community_id and site_ids if they don't exist
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_name = 'whitelist' AND column_name = 'community_id'
  ) THEN
    ALTER TABLE whitelist ADD COLUMN community_id uuid REFERENCES communities(id) ON DELETE CASCADE;
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_name = 'whitelist' AND column_name = 'site_ids'
  ) THEN
    ALTER TABLE whitelist ADD COLUMN site_ids text[] DEFAULT ARRAY[]::text[];
  END IF;
END $$;

-- Make community_id NOT NULL after adding it (only if table is empty or all have values)
DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM whitelist WHERE community_id IS NULL) THEN
    ALTER TABLE whitelist ALTER COLUMN community_id SET NOT NULL;
  END IF;
END $$;

-- Create indexes for better query performance
CREATE INDEX IF NOT EXISTS idx_whitelist_community_id ON whitelist(community_id);
CREATE INDEX IF NOT EXISTS idx_whitelist_site_ids ON whitelist USING GIN(site_ids);
CREATE INDEX IF NOT EXISTS idx_whitelist_plate ON whitelist(plate);
CREATE INDEX IF NOT EXISTS idx_whitelist_enabled ON whitelist(enabled);

-- Create new RLS policies based on community membership
CREATE POLICY "Users can view whitelist in their company communities"
  ON whitelist FOR SELECT
  TO authenticated
  USING (
    EXISTS (
      SELECT 1 FROM memberships m
      JOIN communities c ON c.company_id = m.company_id
      WHERE c.id = whitelist.community_id
      AND m.user_id = auth.uid()
    )
  );

CREATE POLICY "Company owners and admins can insert whitelist entries"
  ON whitelist FOR INSERT
  TO authenticated
  WITH CHECK (
    EXISTS (
      SELECT 1 FROM memberships m
      JOIN communities c ON c.company_id = m.company_id
      WHERE c.id = whitelist.community_id
      AND m.user_id = auth.uid()
      AND m.role IN ('owner', 'admin', 'manager')
    )
  );

CREATE POLICY "Company owners and admins can update whitelist entries"
  ON whitelist FOR UPDATE
  TO authenticated
  USING (
    EXISTS (
      SELECT 1 FROM memberships m
      JOIN communities c ON c.company_id = m.company_id
      WHERE c.id = whitelist.community_id
      AND m.user_id = auth.uid()
      AND m.role IN ('owner', 'admin', 'manager')
    )
  )
  WITH CHECK (
    EXISTS (
      SELECT 1 FROM memberships m
      JOIN communities c ON c.company_id = m.company_id
      WHERE c.id = whitelist.community_id
      AND m.user_id = auth.uid()
      AND m.role IN ('owner', 'admin', 'manager')
    )
  );

CREATE POLICY "Company owners and admins can delete whitelist entries"
  ON whitelist FOR DELETE
  TO authenticated
  USING (
    EXISTS (
      SELECT 1 FROM memberships m
      JOIN communities c ON c.company_id = m.company_id
      WHERE c.id = whitelist.community_id
      AND m.user_id = auth.uid()
      AND m.role IN ('owner', 'admin', 'manager')
    )
  );
