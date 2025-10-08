/*
  # Fix Memberships RLS Infinite Recursion

  1. Problem
    - The memberships table has RLS policies that query the memberships table itself
    - This creates infinite recursion when trying to check permissions
    
  2. Solution
    - Simplify policies to avoid self-referencing queries
    - Users can view their own memberships directly
    - Admin checks should be handled at the application level to avoid recursion
    
  3. Changes
    - Drop existing problematic policies
    - Create simple, non-recursive policies
    - Allow authenticated users to read their own memberships
    - Allow insert for authenticated users (application will handle validation)
    - Allow updates/deletes only for own user_id
*/

-- Drop all existing policies on memberships
DROP POLICY IF EXISTS "users_can_view_memberships" ON memberships;
DROP POLICY IF EXISTS "admins_can_manage_memberships" ON memberships;
DROP POLICY IF EXISTS "Users can insert memberships" ON memberships;

-- Create simple, non-recursive policies
CREATE POLICY "Users can view own memberships"
  ON memberships FOR SELECT
  TO authenticated
  USING (user_id = auth.uid());

CREATE POLICY "Users can insert memberships"
  ON memberships FOR INSERT
  TO authenticated
  WITH CHECK (auth.uid() IS NOT NULL);

CREATE POLICY "Users can update own memberships"
  ON memberships FOR UPDATE
  TO authenticated
  USING (user_id = auth.uid())
  WITH CHECK (user_id = auth.uid());

CREATE POLICY "Users can delete own memberships"
  ON memberships FOR DELETE
  TO authenticated
  USING (user_id = auth.uid());
