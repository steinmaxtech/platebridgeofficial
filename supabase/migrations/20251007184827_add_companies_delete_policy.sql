/*
  # Add DELETE policy for companies
  
  1. Policy
    - Allow company owners to delete their companies
    - Must have 'owner' role in memberships table
  
  2. Security
    - Only owners can delete companies
    - Prevents accidental or unauthorized deletion
*/

CREATE POLICY "Company owners can delete companies"
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
