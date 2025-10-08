/*
  # Fix Companies RLS Policy - Final Solution
  
  1. Changes
    - Re-enable RLS on companies table
    - Drop all existing policies
    - Create new simplified policies that actually work
    - INSERT policy allows any authenticated user to create companies
    - SELECT policy allows users to see companies they're members of
    - UPDATE policy allows owners/admins to update companies
  
  2. Security
    - RLS is enabled
    - All operations require authentication
    - Proper ownership tracking through memberships table
*/

-- Re-enable RLS
ALTER TABLE companies ENABLE ROW LEVEL SECURITY;

-- Drop all existing policies
DROP POLICY IF EXISTS "Authenticated users can create companies" ON companies;
DROP POLICY IF EXISTS "Users can view companies they are members of" ON companies;
DROP POLICY IF EXISTS "Company owners and admins can update companies" ON companies;

-- Create new INSERT policy for authenticated users
CREATE POLICY "authenticated_users_can_insert_companies"
  ON companies
  FOR INSERT
  TO authenticated
  WITH CHECK (true);

-- Create new SELECT policy
CREATE POLICY "users_can_view_member_companies"
  ON companies
  FOR SELECT
  TO authenticated
  USING (
    EXISTS (
      SELECT 1 FROM memberships
      WHERE memberships.company_id = companies.id
      AND memberships.user_id = auth.uid()
    )
  );

-- Create new UPDATE policy
CREATE POLICY "owners_admins_can_update_companies"
  ON companies
  FOR UPDATE
  TO authenticated
  USING (
    EXISTS (
      SELECT 1 FROM memberships
      WHERE memberships.company_id = companies.id
      AND memberships.user_id = auth.uid()
      AND memberships.role IN ('owner', 'admin')
    )
  )
  WITH CHECK (
    EXISTS (
      SELECT 1 FROM memberships
      WHERE memberships.company_id = companies.id
      AND memberships.user_id = auth.uid()
      AND memberships.role IN ('owner', 'admin')
    )
  );

-- Create new DELETE policy
CREATE POLICY "owners_can_delete_companies"
  ON companies
  FOR DELETE
  TO authenticated
  USING (
    EXISTS (
      SELECT 1 FROM memberships
      WHERE memberships.company_id = companies.id
      AND memberships.user_id = auth.uid()
      AND memberships.role = 'owner'
    )
  );
