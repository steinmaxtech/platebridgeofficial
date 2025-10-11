/*
  # Allow anonymous token validation for pod registration

  1. Security Changes
    - Add SELECT policy for anon role to validate registration tokens
    - Allow anonymous UPDATE for marking tokens as used during registration
    - Maintains security by only allowing specific operations

  This enables PODs to register without authentication using valid tokens.
*/

-- Drop existing policies if they exist
DROP POLICY IF EXISTS "Anonymous can validate registration tokens" ON pod_registration_tokens;
DROP POLICY IF EXISTS "Anonymous can mark tokens as used" ON pod_registration_tokens;

-- Allow anonymous users to read tokens for validation
CREATE POLICY "Anonymous can validate registration tokens"
  ON pod_registration_tokens
  FOR SELECT
  TO anon
  USING (true);

-- Allow anonymous users to update tokens during registration
CREATE POLICY "Anonymous can mark tokens as used"
  ON pod_registration_tokens
  FOR UPDATE
  TO anon
  USING (true)
  WITH CHECK (true);