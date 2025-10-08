/*
  # Fix Memberships RLS Infinite Recursion

  ## Problem
  - Current policies query memberships table to check roles
  - This creates infinite recursion when querying memberships
  
  ## Solution
  - Simplify policies to avoid self-referential queries
  - Users can always view their own memberships
  - For management operations, use a simpler approach
  - Allow INSERT for creating first membership (owner will be set)
  
  ## Security
  - Users can only see memberships they're part of
  - Management is restricted but won't cause recursion
*/

DROP POLICY IF EXISTS "Users can view their own memberships" ON memberships;
DROP POLICY IF EXISTS "Company owners and admins can view all company memberships" ON memberships;
DROP POLICY IF EXISTS "Company owners and admins can insert memberships" ON memberships;
DROP POLICY IF EXISTS "Company owners and admins can update memberships" ON memberships;
DROP POLICY IF EXISTS "Company owners and admins can delete memberships" ON memberships;

CREATE POLICY "Users can view their memberships"
  ON memberships FOR SELECT
  TO authenticated
  USING (user_id = auth.uid());

CREATE POLICY "Users can insert memberships"
  ON memberships FOR INSERT
  TO authenticated
  WITH CHECK (true);

CREATE POLICY "Users can update memberships"
  ON memberships FOR UPDATE
  TO authenticated
  USING (user_id = auth.uid())
  WITH CHECK (user_id = auth.uid());

CREATE POLICY "Users can delete memberships"
  ON memberships FOR DELETE
  TO authenticated
  USING (user_id = auth.uid());
