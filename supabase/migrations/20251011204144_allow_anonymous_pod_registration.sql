/*
  # Allow anonymous pod registration

  1. Security Changes
    - Add SELECT policy for anon role to query sites
    - Add INSERT policy for anon role to register new pods
    - Add SELECT policy for anon role to check existing pods
    - Add UPDATE policy for anon role to update pod status during registration

  This enables PODs to self-register using valid registration tokens.
*/

-- Drop existing policies if they exist
DROP POLICY IF EXISTS "Anonymous can query sites for registration" ON sites;
DROP POLICY IF EXISTS "Anonymous can register new pods" ON pods;
DROP POLICY IF EXISTS "Anonymous can check existing pods" ON pods;
DROP POLICY IF EXISTS "Anonymous can update pods during registration" ON pods;

-- Allow anonymous users to query sites for pod assignment
CREATE POLICY "Anonymous can query sites for registration"
  ON sites
  FOR SELECT
  TO anon
  USING (true);

-- Allow anonymous users to insert new pods during registration
CREATE POLICY "Anonymous can register new pods"
  ON pods
  FOR INSERT
  TO anon
  WITH CHECK (true);

-- Allow anonymous users to check for existing pods
CREATE POLICY "Anonymous can check existing pods"
  ON pods
  FOR SELECT
  TO anon
  USING (true);

-- Allow anonymous users to update pods during registration
CREATE POLICY "Anonymous can update pods during registration"
  ON pods
  FOR UPDATE
  TO anon
  USING (true)
  WITH CHECK (true);