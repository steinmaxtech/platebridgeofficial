/*
  # Add Gatewise Community and Access Point IDs

  1. Changes
    - Add `gatewise_community_id` column to `gatewise_config` table
    - Add `gatewise_access_point_id` column to `gatewise_config` table
  
  2. Purpose
    - Store Gatewise-specific IDs needed for API calls
    - The full API URL format is: {api_endpoint}/community/{gatewise_community_id}/access-point/{gatewise_access_point_id}/open
*/

-- Add gatewise_community_id column if it doesn't exist
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_name = 'gatewise_config' AND column_name = 'gatewise_community_id'
  ) THEN
    ALTER TABLE gatewise_config ADD COLUMN gatewise_community_id text DEFAULT '';
  END IF;
END $$;

-- Add gatewise_access_point_id column if it doesn't exist
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_name = 'gatewise_config' AND column_name = 'gatewise_access_point_id'
  ) THEN
    ALTER TABLE gatewise_config ADD COLUMN gatewise_access_point_id text DEFAULT '';
  END IF;
END $$;
