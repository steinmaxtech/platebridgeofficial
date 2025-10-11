/*
  # Update POD Registration Tokens to Community Level

  ## Changes
  1. Change pod_registration_tokens to use community_id instead of site_id
  2. PODs will be registered to communities, then assigned to sites later
  3. Update RLS policies to match community-based access
*/

-- Drop old policies first
DROP POLICY IF EXISTS "Users can view registration tokens for their sites" ON pod_registration_tokens;
DROP POLICY IF EXISTS "Admins can create registration tokens" ON pod_registration_tokens;

-- Add community_id column
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_name = 'pod_registration_tokens' AND column_name = 'community_id'
  ) THEN
    ALTER TABLE pod_registration_tokens ADD COLUMN community_id uuid REFERENCES communities(id) ON DELETE CASCADE;
  END IF;
END $$;

-- Copy site_id to community_id via sites table lookup (if any data exists)
UPDATE pod_registration_tokens prt
SET community_id = s.community_id
FROM sites s
WHERE prt.site_id = s.id
AND prt.community_id IS NULL;

-- For any tokens without a site_id match, we need to handle them
-- (shouldn't happen in practice but good to be safe)

-- Make community_id NOT NULL after migration
DO $$
BEGIN
  IF EXISTS (SELECT 1 FROM pod_registration_tokens WHERE community_id IS NULL) THEN
    -- Delete orphaned tokens without valid community
    DELETE FROM pod_registration_tokens WHERE community_id IS NULL;
  END IF;
END $$;

ALTER TABLE pod_registration_tokens ALTER COLUMN community_id SET NOT NULL;

-- Drop old site_id column CASCADE to drop dependent policies
ALTER TABLE pod_registration_tokens DROP COLUMN IF EXISTS site_id CASCADE;

-- Recreate index
DROP INDEX IF EXISTS idx_pod_registration_tokens_site_id;
CREATE INDEX IF NOT EXISTS idx_pod_registration_tokens_community_id ON pod_registration_tokens(community_id);

-- Create new RLS policies

-- Users can view tokens for their communities
CREATE POLICY "Users can view registration tokens for their communities"
  ON pod_registration_tokens FOR SELECT
  TO authenticated
  USING (
    EXISTS (
      SELECT 1 FROM communities c
      JOIN memberships m ON m.company_id = c.company_id
      WHERE c.id = pod_registration_tokens.community_id
      AND m.user_id = auth.uid()
      AND m.role IN ('owner', 'admin', 'manager')
    )
  );

-- Admins can create tokens
CREATE POLICY "Admins can create registration tokens for communities"
  ON pod_registration_tokens FOR INSERT
  TO authenticated
  WITH CHECK (
    EXISTS (
      SELECT 1 FROM communities c
      JOIN memberships m ON m.company_id = c.company_id
      WHERE c.id = pod_registration_tokens.community_id
      AND m.user_id = auth.uid()
      AND m.role IN ('owner', 'admin', 'manager')
    )
  );
