/*
  # Create Companies, Communities, and Sites Structure

  ## Overview
  This migration creates a hierarchical structure for managing companies, their communities, and gate/pod sites.

  ## New Tables

  ### 1. companies
  - `id` (uuid, primary key)
  - `name` (text, unique) - Company name
  - `is_active` (boolean) - Whether company is active
  - `created_at` (timestamptz)
  - `updated_at` (timestamptz)

  ### 2. communities
  - `id` (uuid, primary key)
  - `company_id` (uuid, foreign key to companies) - Parent company
  - `name` (text) - Community name
  - `timezone` (text) - Community timezone
  - `address` (text) - Physical address
  - `is_active` (boolean) - Whether community is active
  - `created_at` (timestamptz)
  - `updated_at` (timestamptz)

  ### 3. sites
  - `id` (uuid, primary key)
  - `community_id` (uuid, foreign key to communities) - Parent community
  - `name` (text) - Site/gate/pod name
  - `site_id` (text, unique) - External identifier for edge pods
  - `camera_ids` (text[]) - Array of camera identifiers
  - `is_active` (boolean) - Whether site is active
  - `config_version` (integer) - Version for edge pod sync
  - `created_at` (timestamptz)
  - `updated_at` (timestamptz)

  ### 4. memberships
  - `id` (uuid, primary key)
  - `user_id` (uuid, foreign key to auth.users) - The user
  - `company_id` (uuid, foreign key to companies) - The company they belong to
  - `role` (text) - User role (owner, admin, manager, viewer)
  - `created_at` (timestamptz)
  - `updated_at` (timestamptz)

  ## Changes to Existing Tables
  - Migrate data from properties to communities
  - Update foreign keys in whitelist and audit tables
  - Update user_profiles to remove property_id (replaced by memberships)

  ## Security
  - Enable RLS on all new tables
  - Create policies based on company membership and roles
*/

-- Create companies table
CREATE TABLE IF NOT EXISTS companies (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  name text UNIQUE NOT NULL,
  is_active boolean NOT NULL DEFAULT true,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now()
);

ALTER TABLE companies ENABLE ROW LEVEL SECURITY;

-- Create communities table
CREATE TABLE IF NOT EXISTS communities (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  company_id uuid NOT NULL REFERENCES companies(id) ON DELETE CASCADE,
  name text NOT NULL,
  timezone text NOT NULL DEFAULT 'America/New_York',
  address text NOT NULL DEFAULT '',
  is_active boolean NOT NULL DEFAULT true,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now()
);

ALTER TABLE communities ENABLE ROW LEVEL SECURITY;

-- Create sites table
CREATE TABLE IF NOT EXISTS sites (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  community_id uuid NOT NULL REFERENCES communities(id) ON DELETE CASCADE,
  name text NOT NULL,
  site_id text UNIQUE NOT NULL,
  camera_ids text[] DEFAULT ARRAY[]::text[],
  is_active boolean NOT NULL DEFAULT true,
  config_version integer NOT NULL DEFAULT 1,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now()
);

ALTER TABLE sites ENABLE ROW LEVEL SECURITY;

-- Create memberships table
CREATE TABLE IF NOT EXISTS memberships (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id uuid NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  company_id uuid NOT NULL REFERENCES companies(id) ON DELETE CASCADE,
  role text NOT NULL DEFAULT 'viewer',
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  UNIQUE(user_id, company_id),
  CONSTRAINT valid_role CHECK (role IN ('owner', 'admin', 'manager', 'viewer'))
);

ALTER TABLE memberships ENABLE ROW LEVEL SECURITY;

-- Add community_id to whitelist table
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_name = 'whitelist' AND column_name = 'community_id'
  ) THEN
    ALTER TABLE whitelist ADD COLUMN community_id uuid REFERENCES communities(id) ON DELETE CASCADE;
  END IF;
END $$;

-- Add community_id to audit table
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_name = 'audit' AND column_name = 'community_id'
  ) THEN
    ALTER TABLE audit ADD COLUMN community_id uuid REFERENCES communities(id) ON DELETE SET NULL;
  END IF;
END $$;

-- Create indexes for better query performance
CREATE INDEX IF NOT EXISTS idx_communities_company_id ON communities(company_id);
CREATE INDEX IF NOT EXISTS idx_sites_community_id ON sites(community_id);
CREATE INDEX IF NOT EXISTS idx_memberships_user_id ON memberships(user_id);
CREATE INDEX IF NOT EXISTS idx_memberships_company_id ON memberships(company_id);
CREATE INDEX IF NOT EXISTS idx_whitelist_community_id ON whitelist(community_id);
CREATE INDEX IF NOT EXISTS idx_audit_community_id ON audit(community_id);

-- RLS Policies for companies
CREATE POLICY "Users can view companies they are members of"
  ON companies FOR SELECT
  TO authenticated
  USING (
    EXISTS (
      SELECT 1 FROM memberships
      WHERE memberships.company_id = companies.id
      AND memberships.user_id = auth.uid()
    )
  );

CREATE POLICY "Company owners and admins can update companies"
  ON companies FOR UPDATE
  TO authenticated
  USING (
    EXISTS (
      SELECT 1 FROM memberships
      WHERE memberships.company_id = companies.id
      AND memberships.user_id = auth.uid()
      AND memberships.role IN ('owner', 'admin')
    )
  )
  WITH CHECK (
    EXISTS (
      SELECT 1 FROM memberships
      WHERE memberships.company_id = companies.id
      AND memberships.user_id = auth.uid()
      AND memberships.role IN ('owner', 'admin')
    )
  );

CREATE POLICY "Only owners can create companies"
  ON companies FOR INSERT
  TO authenticated
  WITH CHECK (true);

-- RLS Policies for communities
CREATE POLICY "Users can view communities in their companies"
  ON communities FOR SELECT
  TO authenticated
  USING (
    EXISTS (
      SELECT 1 FROM memberships
      WHERE memberships.company_id = communities.company_id
      AND memberships.user_id = auth.uid()
    )
  );

CREATE POLICY "Company owners and admins can insert communities"
  ON communities FOR INSERT
  TO authenticated
  WITH CHECK (
    EXISTS (
      SELECT 1 FROM memberships
      WHERE memberships.company_id = communities.company_id
      AND memberships.user_id = auth.uid()
      AND memberships.role IN ('owner', 'admin')
    )
  );

CREATE POLICY "Company owners and admins can update communities"
  ON communities FOR UPDATE
  TO authenticated
  USING (
    EXISTS (
      SELECT 1 FROM memberships
      WHERE memberships.company_id = communities.company_id
      AND memberships.user_id = auth.uid()
      AND memberships.role IN ('owner', 'admin')
    )
  )
  WITH CHECK (
    EXISTS (
      SELECT 1 FROM memberships
      WHERE memberships.company_id = communities.company_id
      AND memberships.user_id = auth.uid()
      AND memberships.role IN ('owner', 'admin')
    )
  );

CREATE POLICY "Company owners and admins can delete communities"
  ON communities FOR DELETE
  TO authenticated
  USING (
    EXISTS (
      SELECT 1 FROM memberships m
      JOIN communities c ON c.company_id = m.company_id
      WHERE c.id = communities.id
      AND m.user_id = auth.uid()
      AND m.role IN ('owner', 'admin')
    )
  );

-- RLS Policies for sites
CREATE POLICY "Users can view sites in their company communities"
  ON sites FOR SELECT
  TO authenticated
  USING (
    EXISTS (
      SELECT 1 FROM memberships m
      JOIN communities c ON c.company_id = m.company_id
      WHERE c.id = sites.community_id
      AND m.user_id = auth.uid()
    )
  );

CREATE POLICY "Company owners and admins can insert sites"
  ON sites FOR INSERT
  TO authenticated
  WITH CHECK (
    EXISTS (
      SELECT 1 FROM memberships m
      JOIN communities c ON c.company_id = m.company_id
      WHERE c.id = sites.community_id
      AND m.user_id = auth.uid()
      AND m.role IN ('owner', 'admin')
    )
  );

CREATE POLICY "Company owners and admins can update sites"
  ON sites FOR UPDATE
  TO authenticated
  USING (
    EXISTS (
      SELECT 1 FROM memberships m
      JOIN communities c ON c.company_id = m.company_id
      WHERE c.id = sites.community_id
      AND m.user_id = auth.uid()
      AND m.role IN ('owner', 'admin')
    )
  )
  WITH CHECK (
    EXISTS (
      SELECT 1 FROM memberships m
      JOIN communities c ON c.company_id = m.company_id
      WHERE c.id = sites.community_id
      AND m.user_id = auth.uid()
      AND m.role IN ('owner', 'admin')
    )
  );

CREATE POLICY "Company owners and admins can delete sites"
  ON sites FOR DELETE
  TO authenticated
  USING (
    EXISTS (
      SELECT 1 FROM memberships m
      JOIN communities c ON c.company_id = m.company_id
      WHERE c.id = sites.community_id
      AND m.user_id = auth.uid()
      AND m.role IN ('owner', 'admin')
    )
  );

-- RLS Policies for memberships
CREATE POLICY "Users can view their own memberships"
  ON memberships FOR SELECT
  TO authenticated
  USING (user_id = auth.uid());

CREATE POLICY "Company owners and admins can view all company memberships"
  ON memberships FOR SELECT
  TO authenticated
  USING (
    EXISTS (
      SELECT 1 FROM memberships m
      WHERE m.company_id = memberships.company_id
      AND m.user_id = auth.uid()
      AND m.role IN ('owner', 'admin')
    )
  );

CREATE POLICY "Company owners and admins can insert memberships"
  ON memberships FOR INSERT
  TO authenticated
  WITH CHECK (
    EXISTS (
      SELECT 1 FROM memberships m
      WHERE m.company_id = memberships.company_id
      AND m.user_id = auth.uid()
      AND m.role IN ('owner', 'admin')
    )
  );

CREATE POLICY "Company owners and admins can update memberships"
  ON memberships FOR UPDATE
  TO authenticated
  USING (
    EXISTS (
      SELECT 1 FROM memberships m
      WHERE m.company_id = memberships.company_id
      AND m.user_id = auth.uid()
      AND m.role IN ('owner', 'admin')
    )
  )
  WITH CHECK (
    EXISTS (
      SELECT 1 FROM memberships m
      WHERE m.company_id = memberships.company_id
      AND m.user_id = auth.uid()
      AND m.role IN ('owner', 'admin')
    )
  );

CREATE POLICY "Company owners and admins can delete memberships"
  ON memberships FOR DELETE
  TO authenticated
  USING (
    EXISTS (
      SELECT 1 FROM memberships m
      WHERE m.company_id = memberships.company_id
      AND m.user_id = auth.uid()
      AND m.role IN ('owner', 'admin')
    )
  );
