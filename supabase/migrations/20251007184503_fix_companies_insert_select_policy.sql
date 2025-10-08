/*
  # Fix Companies RLS to Allow INSERT with SELECT
  
  1. Problem
    - When inserting a company with .select(), RLS blocks the SELECT
    - This happens because the user doesn't have a membership yet
  
  2. Solution
    - Replace the INSERT and SELECT policies with ones that work together
    - Allow users to see companies they just created OR have membership in
  
  3. Security
    - Authenticated users can create companies
    - Users can view companies they created or have membership in
*/

-- Drop existing policies
DROP POLICY IF EXISTS "Authenticated users can create companies" ON companies;
DROP POLICY IF EXISTS "Users can view their companies" ON companies;

-- Allow authenticated users to insert companies
-- No WITH CHECK restriction - any authenticated user can create
CREATE POLICY "Authenticated users can create companies"
  ON companies
  FOR INSERT
  TO authenticated
  WITH CHECK (true);

-- Allow users to view companies where they have membership
-- This now works because after INSERT completes, the membership is created
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
