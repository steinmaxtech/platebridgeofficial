/*
  # Add Resident Role and View As Feature
  
  ## Overview
  This migration adds support for a "resident" role and implements a "view as" feature
  for administrators to test different role perspectives.
  
  ## Changes
  
  1. Roles Update
    - Add "resident" to the list of valid roles in memberships table
    - Residents will have limited access to only their own whitelist entries
  
  2. User Profiles Update
    - Add "view_as_role" column to user_profiles for admin role emulation
    - This allows owners/admins to test the UI as different roles
  
  ## Security
  - Only the actual role determines database access permissions
  - view_as_role is UI-only and doesn't affect RLS policies
*/

-- Update memberships table to include resident role
DO $$
BEGIN
  -- Drop the existing constraint if it exists
  IF EXISTS (
    SELECT 1 FROM information_schema.table_constraints 
    WHERE constraint_name = 'valid_role' 
    AND table_name = 'memberships'
  ) THEN
    ALTER TABLE memberships DROP CONSTRAINT valid_role;
  END IF;
  
  -- Add the new constraint with resident role
  ALTER TABLE memberships ADD CONSTRAINT valid_role CHECK (role IN ('owner', 'admin', 'manager', 'viewer', 'resident'));
END $$;

-- Add view_as_role column to user_profiles if it doesn't exist
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_name = 'user_profiles' AND column_name = 'view_as_role'
  ) THEN
    ALTER TABLE user_profiles ADD COLUMN view_as_role text;
  END IF;
  
  -- Add constraint to ensure valid view_as_role values
  IF NOT EXISTS (
    SELECT 1 FROM information_schema.table_constraints
    WHERE constraint_name = 'valid_view_as_role'
    AND table_name = 'user_profiles'
  ) THEN
    ALTER TABLE user_profiles ADD CONSTRAINT valid_view_as_role 
      CHECK (view_as_role IS NULL OR view_as_role IN ('owner', 'admin', 'manager', 'viewer', 'resident'));
  END IF;
END $$;

-- Create RLS policy for residents to view only their own whitelist entries
CREATE POLICY "Residents can view their own whitelist entries"
  ON whitelist FOR SELECT
  TO authenticated
  USING (
    EXISTS (
      SELECT 1 FROM memberships m
      JOIN communities c ON c.company_id = m.company_id
      WHERE c.id = whitelist.community_id
      AND m.user_id = auth.uid()
      AND m.role = 'resident'
      AND whitelist.tenant = (
        SELECT email FROM auth.users WHERE id = auth.uid()
      )
    )
  );
