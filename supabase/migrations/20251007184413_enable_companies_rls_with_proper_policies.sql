/*
  # Enable RLS on Companies with Proper Policies
  
  1. Changes
    - Enable RLS on companies table
    - Create policies for authenticated users to insert companies
    - Create policies for users to view companies they're members of
    - Create policies for owners/admins to update companies
    - Create policies for owners to delete companies
  
  2. Security
    - All authenticated users can create companies
    - Users can only view companies they have membership in
    - Only owners and admins can update companies
    - Only owners can delete companies
*/

-- Enable RLS
ALTER TABLE companies ENABLE ROW LEVEL SECURITY;

-- Drop all existing policies (if any)
DROP POLICY IF EXISTS "Authenticated users can create companies" ON companies;
DROP POLICY IF EXISTS "Users can view their companies" ON companies;
DROP POLICY IF EXISTS "Owners and admins can update companies" ON companies;
DROP POLICY IF EXISTS "Owners can delete companies" ON companies;

-- Allow authenticated users to insert companies
CREATE POLICY "Authenticated users can create companies"
  ON companies
  FOR INSERT
  TO authenticated
  WITH CHECK (true);

-- Allow users to view companies where they have membership
CREATE POLICY "Users can view their companies"
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

-- Allow owners and admins to update companies
CREATE POLICY "Owners and admins can update companies"
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

-- Allow owners to delete companies
CREATE POLICY "Owners can delete companies"
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
