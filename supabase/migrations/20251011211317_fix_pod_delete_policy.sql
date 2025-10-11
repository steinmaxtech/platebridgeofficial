/*
  # Fix POD Delete Policy

  ## Changes
  Updates the pod deletion RLS policy to use the correct roles (owner, admin, manager)
  instead of the incorrect roles (community_admin, super_admin).

  ## Security
  - Only owners, admins, and managers can delete PODs
  - Policy checks membership through sites -> communities -> company -> memberships
*/

-- Drop the old delete policy with incorrect roles
DROP POLICY IF EXISTS "Company/Community admins can delete PODs" ON pods;

-- Create new delete policy with correct roles
CREATE POLICY "Company/Community admins can delete PODs"
  ON pods FOR DELETE
  TO authenticated
  USING (
    EXISTS (
      SELECT 1
      FROM sites s
      JOIN communities c ON c.id = s.community_id
      JOIN memberships m ON m.company_id = c.company_id
      WHERE s.id = pods.site_id
      AND m.user_id = auth.uid()
      AND m.role IN ('owner', 'admin', 'manager')
    )
  );
