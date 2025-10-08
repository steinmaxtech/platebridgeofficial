/*
  # Fix Plates RLS Policy for Residents
  
  ## Changes
  - Drop old resident SELECT policy that accesses auth.users directly
  - Create new policy that uses auth.email() function instead
  
  ## Security
  - Residents can only view plates where tenant matches their email
  - Avoids direct access to auth.users table which causes permission errors
*/

-- Drop the problematic policy
DROP POLICY IF EXISTS "Residents can view their own plate entries" ON plates;

-- Create new policy using auth.email() function which is safe
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
      AND plates.tenant = auth.email()
    )
  );
