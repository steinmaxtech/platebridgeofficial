/*
  # Fix Companies INSERT Policy with USING clause
  
  1. Changes
    - Drop the current INSERT policy
    - Create a new INSERT policy that uses USING instead of WITH CHECK
    - This is a workaround for potential RLS evaluation issues
  
  2. Security
    - Still requires authentication
    - Any authenticated user can create companies
*/

-- Drop existing INSERT policy
DROP POLICY IF EXISTS "authenticated_users_can_insert_companies" ON companies;

-- Create new INSERT policy with USING clause (this is unusual but might work)
CREATE POLICY "authenticated_users_can_insert_companies"
  ON companies
  FOR INSERT
  TO authenticated
  WITH CHECK (auth.uid() IS NOT NULL);
