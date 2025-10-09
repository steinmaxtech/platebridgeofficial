/*
  # Add Company Settings Fields

  ## Overview
  This migration adds additional settings fields to the companies table for enhanced configuration options.

  ## Changes to Existing Tables

  ### companies
  - `timezone` (text) - Company timezone for scheduling and reports
  - `sla_target_minutes` (integer) - Target response time in minutes
  - `notification_email` (text) - Email for system notifications
  - `logo_url` (text) - URL to company logo image

  ## Notes
  - All new fields are optional with sensible defaults
  - Timezone defaults to America/New_York (Eastern Time)
  - SLA target defaults to 15 minutes
*/

-- Add timezone field
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_name = 'companies' AND column_name = 'timezone'
  ) THEN
    ALTER TABLE companies ADD COLUMN timezone text DEFAULT 'America/New_York';
  END IF;
END $$;

-- Add SLA target minutes field
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_name = 'companies' AND column_name = 'sla_target_minutes'
  ) THEN
    ALTER TABLE companies ADD COLUMN sla_target_minutes integer DEFAULT 15;
  END IF;
END $$;

-- Add notification email field
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_name = 'companies' AND column_name = 'notification_email'
  ) THEN
    ALTER TABLE companies ADD COLUMN notification_email text;
  END IF;
END $$;

-- Add logo URL field
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_name = 'companies' AND column_name = 'logo_url'
  ) THEN
    ALTER TABLE companies ADD COLUMN logo_url text;
  END IF;
END $$;
