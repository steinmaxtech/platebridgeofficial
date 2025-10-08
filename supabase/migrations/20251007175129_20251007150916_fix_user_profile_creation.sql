/*
  # Fix User Profile Creation on Signup

  1. Changes
    - Add a permissive RLS policy to allow new user profile creation during signup
    - The trigger function already has SECURITY DEFINER but RLS was blocking it
    - This policy allows the INSERT only if the user is creating their own profile

  2. Security
    - Users can only create a profile for themselves (id = auth.uid())
    - Default role is 'viewer' (enforced by table default)
    - Existing owner/admin policy remains for creating other users' profiles
*/

DROP POLICY IF EXISTS "Users can create their own profile on signup" ON user_profiles;
CREATE POLICY "Users can create their own profile on signup"
  ON user_profiles FOR INSERT
  TO authenticated
  WITH CHECK (id = auth.uid());