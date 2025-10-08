/*
  # Rename Whitelist Table to Plates
  
  ## Overview
  This migration renames the `whitelist` table to `plates` for better terminology.
  All related indexes, policies, and constraints are updated accordingly.
  
  ## Changes
  1. Rename table from `whitelist` to `plates`
  2. Update all indexes to use new naming
  3. Update all RLS policies with new naming
  
  ## Notes
  - This is a non-destructive rename operation
  - All data is preserved
  - All relationships and constraints remain intact
*/

-- Rename the table
ALTER TABLE IF EXISTS whitelist RENAME TO plates;

-- Rename indexes
ALTER INDEX IF EXISTS idx_whitelist_community_id RENAME TO idx_plates_community_id;
ALTER INDEX IF EXISTS idx_whitelist_site_ids RENAME TO idx_plates_site_ids;
ALTER INDEX IF EXISTS idx_whitelist_plate RENAME TO idx_plates_plate;
ALTER INDEX IF EXISTS idx_whitelist_enabled RENAME TO idx_plates_enabled;

-- Drop old policies (they reference the old table name)
DROP POLICY IF EXISTS "Users can view whitelist in their company communities" ON plates;
DROP POLICY IF EXISTS "Company owners and admins can insert whitelist entries" ON plates;
DROP POLICY IF EXISTS "Company owners and admins can update whitelist entries" ON plates;
DROP POLICY IF EXISTS "Company owners and admins can delete whitelist entries" ON plates;
DROP POLICY IF EXISTS "Residents can view their own whitelist entries" ON plates;

-- Create new policies with updated names
CREATE POLICY "Users can view plates in their company communities"
  ON plates FOR SELECT
  TO authenticated
  USING (
    EXISTS (
      SELECT 1 FROM memberships m
      JOIN communities c ON c.company_id = m.company_id
      WHERE c.id = plates.community_id
      AND m.user_id = auth.uid()
    )
  );

CREATE POLICY "Company owners and admins can insert plate entries"
  ON plates FOR INSERT
  TO authenticated
  WITH CHECK (
    EXISTS (
      SELECT 1 FROM memberships m
      JOIN communities c ON c.company_id = m.company_id
      WHERE c.id = plates.community_id
      AND m.user_id = auth.uid()
      AND m.role IN ('owner', 'admin', 'manager')
    )
  );

CREATE POLICY "Company owners and admins can update plate entries"
  ON plates FOR UPDATE
  TO authenticated
  USING (
    EXISTS (
      SELECT 1 FROM memberships m
      JOIN communities c ON c.company_id = m.company_id
      WHERE c.id = plates.community_id
      AND m.user_id = auth.uid()
      AND m.role IN ('owner', 'admin', 'manager')
    )
  )
  WITH CHECK (
    EXISTS (
      SELECT 1 FROM memberships m
      JOIN communities c ON c.company_id = m.company_id
      WHERE c.id = plates.community_id
      AND m.user_id = auth.uid()
      AND m.role IN ('owner', 'admin', 'manager')
    )
  );

CREATE POLICY "Company owners and admins can delete plate entries"
  ON plates FOR DELETE
  TO authenticated
  USING (
    EXISTS (
      SELECT 1 FROM memberships m
      JOIN communities c ON c.company_id = m.company_id
      WHERE c.id = plates.community_id
      AND m.user_id = auth.uid()
      AND m.role IN ('owner', 'admin', 'manager')
    )
  );

CREATE POLICY "Residents can view their own plate entries"
  ON plates FOR SELECT
  TO authenticated
  USING (
    EXISTS (
      SELECT 1 FROM memberships m
      JOIN communities c ON c.company_id = m.company_id
      WHERE c.id = plates.community_id
      AND m.user_id = auth.uid()
      AND m.role = 'resident'
      AND plates.tenant = (
        SELECT email FROM auth.users WHERE id = auth.uid()
      )
    )
  );
