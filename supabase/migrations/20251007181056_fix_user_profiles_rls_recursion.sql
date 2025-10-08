/*
  # Fix User Profiles RLS Infinite Recursion

  1. Problem
    - Current policies query user_profiles table to check roles
    - This creates infinite recursion when querying user_profiles
  
  2. Solution
    - Drop all existing policies
    - Create simple policies that don't reference user_profiles
    - Users can read/update their own profile
    - All authenticated users can read all profiles (needed for role checks)
    - Only the user can create their own profile on signup
  
  3. Security
    - Maintains security while preventing recursion
    - Users can't modify other users' data
    - Profile creation is restricted to authenticated users for their own ID
*/

DROP POLICY IF EXISTS "Users can view their own profile" ON user_profiles;
DROP POLICY IF EXISTS "Owners and admins can view all profiles" ON user_profiles;
DROP POLICY IF EXISTS "Users can create their own profile on signup" ON user_profiles;
DROP POLICY IF EXISTS "Owners and admins can insert profiles" ON user_profiles;
DROP POLICY IF EXISTS "Owners and admins can update profiles" ON user_profiles;
DROP POLICY IF EXISTS "Owners and admins can delete profiles" ON user_profiles;

CREATE POLICY "Users can read all profiles"
  ON user_profiles FOR SELECT
  TO authenticated
  USING (true);

CREATE POLICY "Users can insert their own profile"
  ON user_profiles FOR INSERT
  TO authenticated
  WITH CHECK (auth.uid() = id);

CREATE POLICY "Users can update their own profile"
  ON user_profiles FOR UPDATE
  TO authenticated
  USING (auth.uid() = id)
  WITH CHECK (auth.uid() = id);

CREATE POLICY "Users can delete their own profile"
  ON user_profiles FOR DELETE
  TO authenticated
  USING (auth.uid() = id);
