/*
  # Fix Companies Insert Policy
  
  1. Changes
    - Drop the existing restrictive insert policy
    - Create a new policy that allows any authenticated user to create companies
    - This is necessary because memberships are created AFTER the company is created
  
  2. Security
    - Still restricts to authenticated users only
    - Ownership is established through the memberships table immediately after creation
*/

DROP POLICY IF EXISTS "Only owners can create companies" ON companies;

CREATE POLICY "Authenticated users can create companies"
  ON companies
  FOR INSERT
  TO authenticated
  WITH CHECK (true);
