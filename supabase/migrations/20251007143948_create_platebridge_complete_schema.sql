/*
  # PlateBridge Cloud Hub - Complete Database Schema

  1. Tables Created
    - `properties` - Property management with config versioning
      - id, name, timezone, address, is_active, config_version, timestamps
    
    - `whitelist` - License plate whitelist entries
      - id, property_id, plate, unit, tenant, vehicle
      - starts, ends, days, time_start, time_end
      - enabled, notes, timestamps
    
    - `audit` - System audit log
      - id, ts, site_id, property_id, plate, camera
      - action, result, by, metadata
    
    - `user_profiles` - User roles and property assignments
      - id (FK to auth.users), role, property_id, timestamps

  2. Security (RLS)
    - All tables have RLS enabled
    - Owners/admins: full access
    - Managers: scoped to assigned property
    - Viewers: read-only access to assigned property
    - Audit: append-only from server, readable by authorized users

  3. Indexes
    - Performance indexes on frequently queried columns
    - Foreign key indexes for joins

  4. Triggers
    - Auto-update timestamps
    - Auto-create user profile on signup
*/

CREATE TABLE IF NOT EXISTS properties (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  name text UNIQUE NOT NULL,
  timezone text DEFAULT 'America/New_York' NOT NULL,
  address text DEFAULT '' NOT NULL,
  is_active boolean DEFAULT true NOT NULL,
  config_version integer DEFAULT 1 NOT NULL,
  created_at timestamptz DEFAULT now() NOT NULL,
  updated_at timestamptz DEFAULT now() NOT NULL
);

CREATE TABLE IF NOT EXISTS whitelist (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  property_id uuid NOT NULL REFERENCES properties(id) ON DELETE CASCADE,
  plate text NOT NULL,
  unit text,
  tenant text,
  vehicle text,
  starts date,
  ends date,
  days text,
  time_start text,
  time_end text,
  enabled boolean DEFAULT true NOT NULL,
  notes text,
  created_at timestamptz DEFAULT now() NOT NULL,
  updated_at timestamptz DEFAULT now() NOT NULL
);

CREATE TABLE IF NOT EXISTS audit (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  ts timestamptz DEFAULT now() NOT NULL,
  site_id text,
  property_id uuid REFERENCES properties(id) ON DELETE SET NULL,
  plate text,
  camera text,
  action text NOT NULL,
  result text NOT NULL,
  by text NOT NULL,
  metadata jsonb DEFAULT '{}'::jsonb
);

CREATE TABLE IF NOT EXISTS user_profiles (
  id uuid PRIMARY KEY REFERENCES auth.users(id) ON DELETE CASCADE,
  role text DEFAULT 'viewer' NOT NULL CHECK (role IN ('owner', 'admin', 'manager', 'viewer')),
  property_id uuid REFERENCES properties(id) ON DELETE SET NULL,
  created_at timestamptz DEFAULT now() NOT NULL,
  updated_at timestamptz DEFAULT now() NOT NULL
);

CREATE INDEX IF NOT EXISTS idx_whitelist_property ON whitelist(property_id);
CREATE INDEX IF NOT EXISTS idx_whitelist_plate ON whitelist(plate);
CREATE INDEX IF NOT EXISTS idx_whitelist_enabled ON whitelist(enabled);
CREATE INDEX IF NOT EXISTS idx_audit_property ON audit(property_id);
CREATE INDEX IF NOT EXISTS idx_audit_ts ON audit(ts DESC);
CREATE INDEX IF NOT EXISTS idx_user_profiles_role ON user_profiles(role);
CREATE INDEX IF NOT EXISTS idx_user_profiles_property ON user_profiles(property_id);

ALTER TABLE properties ENABLE ROW LEVEL SECURITY;
ALTER TABLE whitelist ENABLE ROW LEVEL SECURITY;
ALTER TABLE audit ENABLE ROW LEVEL SECURITY;
ALTER TABLE user_profiles ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Owners and admins can view all properties" ON properties;
CREATE POLICY "Owners and admins can view all properties"
  ON properties FOR SELECT
  TO authenticated
  USING (
    EXISTS (
      SELECT 1 FROM user_profiles
      WHERE user_profiles.id = auth.uid()
      AND user_profiles.role IN ('owner', 'admin')
    )
  );

DROP POLICY IF EXISTS "Managers and viewers can view their property" ON properties;
CREATE POLICY "Managers and viewers can view their property"
  ON properties FOR SELECT
  TO authenticated
  USING (
    EXISTS (
      SELECT 1 FROM user_profiles
      WHERE user_profiles.id = auth.uid()
      AND user_profiles.property_id = properties.id
    )
  );

DROP POLICY IF EXISTS "Owners and admins can insert properties" ON properties;
CREATE POLICY "Owners and admins can insert properties"
  ON properties FOR INSERT
  TO authenticated
  WITH CHECK (
    EXISTS (
      SELECT 1 FROM user_profiles
      WHERE user_profiles.id = auth.uid()
      AND user_profiles.role IN ('owner', 'admin')
    )
  );

DROP POLICY IF EXISTS "Owners and admins can update properties" ON properties;
CREATE POLICY "Owners and admins can update properties"
  ON properties FOR UPDATE
  TO authenticated
  USING (
    EXISTS (
      SELECT 1 FROM user_profiles
      WHERE user_profiles.id = auth.uid()
      AND user_profiles.role IN ('owner', 'admin')
    )
  )
  WITH CHECK (
    EXISTS (
      SELECT 1 FROM user_profiles
      WHERE user_profiles.id = auth.uid()
      AND user_profiles.role IN ('owner', 'admin')
    )
  );

DROP POLICY IF EXISTS "Owners and admins can delete properties" ON properties;
CREATE POLICY "Owners and admins can delete properties"
  ON properties FOR DELETE
  TO authenticated
  USING (
    EXISTS (
      SELECT 1 FROM user_profiles
      WHERE user_profiles.id = auth.uid()
      AND user_profiles.role IN ('owner', 'admin')
    )
  );

DROP POLICY IF EXISTS "Users can view whitelist for accessible properties" ON whitelist;
CREATE POLICY "Users can view whitelist for accessible properties"
  ON whitelist FOR SELECT
  TO authenticated
  USING (
    EXISTS (
      SELECT 1 FROM user_profiles
      WHERE user_profiles.id = auth.uid()
      AND (
        user_profiles.role IN ('owner', 'admin')
        OR user_profiles.property_id = whitelist.property_id
      )
    )
  );

DROP POLICY IF EXISTS "Owners and admins can insert whitelist" ON whitelist;
CREATE POLICY "Owners and admins can insert whitelist"
  ON whitelist FOR INSERT
  TO authenticated
  WITH CHECK (
    EXISTS (
      SELECT 1 FROM user_profiles
      WHERE user_profiles.id = auth.uid()
      AND user_profiles.role IN ('owner', 'admin')
    )
  );

DROP POLICY IF EXISTS "Managers can insert whitelist for their property" ON whitelist;
CREATE POLICY "Managers can insert whitelist for their property"
  ON whitelist FOR INSERT
  TO authenticated
  WITH CHECK (
    EXISTS (
      SELECT 1 FROM user_profiles
      WHERE user_profiles.id = auth.uid()
      AND user_profiles.role = 'manager'
      AND user_profiles.property_id = whitelist.property_id
    )
  );

DROP POLICY IF EXISTS "Owners and admins can update whitelist" ON whitelist;
CREATE POLICY "Owners and admins can update whitelist"
  ON whitelist FOR UPDATE
  TO authenticated
  USING (
    EXISTS (
      SELECT 1 FROM user_profiles
      WHERE user_profiles.id = auth.uid()
      AND user_profiles.role IN ('owner', 'admin')
    )
  )
  WITH CHECK (
    EXISTS (
      SELECT 1 FROM user_profiles
      WHERE user_profiles.id = auth.uid()
      AND user_profiles.role IN ('owner', 'admin')
    )
  );

DROP POLICY IF EXISTS "Managers can update whitelist for their property" ON whitelist;
CREATE POLICY "Managers can update whitelist for their property"
  ON whitelist FOR UPDATE
  TO authenticated
  USING (
    EXISTS (
      SELECT 1 FROM user_profiles
      WHERE user_profiles.id = auth.uid()
      AND user_profiles.role = 'manager'
      AND user_profiles.property_id = whitelist.property_id
    )
  )
  WITH CHECK (
    EXISTS (
      SELECT 1 FROM user_profiles
      WHERE user_profiles.id = auth.uid()
      AND user_profiles.role = 'manager'
      AND user_profiles.property_id = whitelist.property_id
    )
  );

DROP POLICY IF EXISTS "Owners and admins can delete whitelist" ON whitelist;
CREATE POLICY "Owners and admins can delete whitelist"
  ON whitelist FOR DELETE
  TO authenticated
  USING (
    EXISTS (
      SELECT 1 FROM user_profiles
      WHERE user_profiles.id = auth.uid()
      AND user_profiles.role IN ('owner', 'admin')
    )
  );

DROP POLICY IF EXISTS "Managers can delete whitelist for their property" ON whitelist;
CREATE POLICY "Managers can delete whitelist for their property"
  ON whitelist FOR DELETE
  TO authenticated
  USING (
    EXISTS (
      SELECT 1 FROM user_profiles
      WHERE user_profiles.id = auth.uid()
      AND user_profiles.role = 'manager'
      AND user_profiles.property_id = whitelist.property_id
    )
  );

DROP POLICY IF EXISTS "Users can view audit logs for accessible properties" ON audit;
CREATE POLICY "Users can view audit logs for accessible properties"
  ON audit FOR SELECT
  TO authenticated
  USING (
    EXISTS (
      SELECT 1 FROM user_profiles
      WHERE user_profiles.id = auth.uid()
      AND (
        user_profiles.role IN ('owner', 'admin')
        OR user_profiles.property_id = audit.property_id
      )
    )
  );

DROP POLICY IF EXISTS "Users can view their own profile" ON user_profiles;
CREATE POLICY "Users can view their own profile"
  ON user_profiles FOR SELECT
  TO authenticated
  USING (id = auth.uid());

DROP POLICY IF EXISTS "Owners and admins can view all profiles" ON user_profiles;
CREATE POLICY "Owners and admins can view all profiles"
  ON user_profiles FOR SELECT
  TO authenticated
  USING (
    EXISTS (
      SELECT 1 FROM user_profiles up
      WHERE up.id = auth.uid()
      AND up.role IN ('owner', 'admin')
    )
  );

DROP POLICY IF EXISTS "Owners and admins can insert profiles" ON user_profiles;
CREATE POLICY "Owners and admins can insert profiles"
  ON user_profiles FOR INSERT
  TO authenticated
  WITH CHECK (
    EXISTS (
      SELECT 1 FROM user_profiles
      WHERE user_profiles.id = auth.uid()
      AND user_profiles.role IN ('owner', 'admin')
    )
  );

DROP POLICY IF EXISTS "Owners and admins can update profiles" ON user_profiles;
CREATE POLICY "Owners and admins can update profiles"
  ON user_profiles FOR UPDATE
  TO authenticated
  USING (
    EXISTS (
      SELECT 1 FROM user_profiles up
      WHERE up.id = auth.uid()
      AND up.role IN ('owner', 'admin')
    )
  )
  WITH CHECK (
    EXISTS (
      SELECT 1 FROM user_profiles up
      WHERE up.id = auth.uid()
      AND up.role IN ('owner', 'admin')
    )
  );

DROP POLICY IF EXISTS "Owners and admins can delete profiles" ON user_profiles;
CREATE POLICY "Owners and admins can delete profiles"
  ON user_profiles FOR DELETE
  TO authenticated
  USING (
    EXISTS (
      SELECT 1 FROM user_profiles up
      WHERE up.id = auth.uid()
      AND up.role IN ('owner', 'admin')
    )
  );

CREATE OR REPLACE FUNCTION update_updated_at_column()
RETURNS TRIGGER AS $$
BEGIN
  NEW.updated_at = now();
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS update_properties_updated_at ON properties;
CREATE TRIGGER update_properties_updated_at BEFORE UPDATE ON properties
  FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();

DROP TRIGGER IF EXISTS update_whitelist_updated_at ON whitelist;
CREATE TRIGGER update_whitelist_updated_at BEFORE UPDATE ON whitelist
  FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();

DROP TRIGGER IF EXISTS update_user_profiles_updated_at ON user_profiles;
CREATE TRIGGER update_user_profiles_updated_at BEFORE UPDATE ON user_profiles
  FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();

CREATE OR REPLACE FUNCTION handle_new_user()
RETURNS TRIGGER AS $$
BEGIN
  INSERT INTO user_profiles (id, role)
  VALUES (NEW.id, 'viewer');
  RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

DROP TRIGGER IF EXISTS on_auth_user_created ON auth.users;
CREATE TRIGGER on_auth_user_created
  AFTER INSERT ON auth.users
  FOR EACH ROW EXECUTE FUNCTION handle_new_user();