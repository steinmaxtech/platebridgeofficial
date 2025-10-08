/*
  # Optimize RLS Policies and Security Cleanup
  
  ## Changes Made
  
  ### 1. RLS Policy Optimization
  - Wrap all auth.uid() and auth.email() calls with SELECT to prevent re-evaluation per row
  - Improves query performance at scale by caching the auth function result
  
  ### 2. Remove Duplicate Policies
  - Remove old duplicate policies on companies, plates, properties, gatewise_config, system_metrics
  - Keep only the newer, properly scoped policies
  
  ### 3. Fix Function Search Paths
  - Set search_path for trigger functions to prevent security vulnerabilities
  
  ### 4. Remove Unused Indexes
  - Drop indexes that are not being used to reduce storage and maintenance overhead
  
  ## Security Improvements
  - Better performance at scale
  - Reduced policy confusion from duplicates
  - Secure function execution paths
*/

-- ============================================================================
-- STEP 1: Drop all existing RLS policies (we'll recreate them optimized)
-- ============================================================================

-- Properties policies
DROP POLICY IF EXISTS "Owners and admins can view all properties" ON properties;
DROP POLICY IF EXISTS "Managers and viewers can view their property" ON properties;
DROP POLICY IF EXISTS "Owners and admins can insert properties" ON properties;
DROP POLICY IF EXISTS "Owners and admins can update properties" ON properties;
DROP POLICY IF EXISTS "Owners and admins can delete properties" ON properties;

-- Plates policies (remove old whitelist-named ones, keep company-scoped ones)
DROP POLICY IF EXISTS "Owners and admins can insert whitelist" ON plates;
DROP POLICY IF EXISTS "Owners and admins can update whitelist" ON plates;
DROP POLICY IF EXISTS "Owners and admins can delete whitelist" ON plates;
DROP POLICY IF EXISTS "Users can view plates in their company communities" ON plates;
DROP POLICY IF EXISTS "Company owners and admins can insert plate entries" ON plates;
DROP POLICY IF EXISTS "Company owners and admins can update plate entries" ON plates;
DROP POLICY IF EXISTS "Company owners and admins can delete plate entries" ON plates;
DROP POLICY IF EXISTS "Residents can view their own plate entries" ON plates;

-- Audit policies
DROP POLICY IF EXISTS "Users can view audit logs for accessible properties" ON audit;

-- User profiles policies
DROP POLICY IF EXISTS "Users can insert their own profile" ON user_profiles;
DROP POLICY IF EXISTS "Users can update their own profile" ON user_profiles;
DROP POLICY IF EXISTS "Users can delete their own profile" ON user_profiles;

-- Communities policies
DROP POLICY IF EXISTS "Users can view communities in their companies" ON communities;
DROP POLICY IF EXISTS "Company owners and admins can insert communities" ON communities;
DROP POLICY IF EXISTS "Company owners and admins can update communities" ON communities;
DROP POLICY IF EXISTS "Company owners and admins can delete communities" ON communities;

-- Sites policies
DROP POLICY IF EXISTS "Users can view sites in their company communities" ON sites;
DROP POLICY IF EXISTS "Company owners and admins can insert sites" ON sites;
DROP POLICY IF EXISTS "Company owners and admins can update sites" ON sites;
DROP POLICY IF EXISTS "Company owners and admins can delete sites" ON sites;

-- Memberships policies
DROP POLICY IF EXISTS "Users can view their memberships" ON memberships;
DROP POLICY IF EXISTS "Users can update memberships" ON memberships;
DROP POLICY IF EXISTS "Users can delete memberships" ON memberships;

-- Companies policies (remove ALL duplicates)
DROP POLICY IF EXISTS "users_can_view_member_companies" ON companies;
DROP POLICY IF EXISTS "owners_admins_can_update_companies" ON companies;
DROP POLICY IF EXISTS "owners_can_delete_companies" ON companies;
DROP POLICY IF EXISTS "authenticated_users_can_insert_companies" ON companies;
DROP POLICY IF EXISTS "Owners and admins can update companies" ON companies;
DROP POLICY IF EXISTS "Owners can delete companies" ON companies;
DROP POLICY IF EXISTS "Users can view their companies" ON companies;
DROP POLICY IF EXISTS "Company owners can delete companies" ON companies;
DROP POLICY IF EXISTS "Authenticated users can create companies" ON companies;

-- Pod health policies
DROP POLICY IF EXISTS "Users can view pod health in their company communities" ON pod_health;
DROP POLICY IF EXISTS "Managers can update pod health for their sites" ON pod_health;
DROP POLICY IF EXISTS "Managers can insert pod health for their sites" ON pod_health;

-- Gatewise config policies
DROP POLICY IF EXISTS "Users can view gatewise config in their communities" ON gatewise_config;
DROP POLICY IF EXISTS "Managers can manage gatewise config for their communities" ON gatewise_config;

-- System metrics policies
DROP POLICY IF EXISTS "Users can view metrics for their company" ON system_metrics;
DROP POLICY IF EXISTS "Admins can manage metrics for their company" ON system_metrics;

-- ============================================================================
-- STEP 2: Create optimized RLS policies with SELECT wrappers
-- ============================================================================

-- COMPANIES: Single set of optimized policies
CREATE POLICY "users_can_view_companies"
  ON companies FOR SELECT
  TO authenticated
  USING (
    EXISTS (
      SELECT 1 FROM memberships m
      WHERE m.company_id = companies.id
      AND m.user_id = (SELECT auth.uid())
    )
  );

CREATE POLICY "authenticated_can_insert_companies"
  ON companies FOR INSERT
  TO authenticated
  WITH CHECK ((SELECT auth.uid()) IS NOT NULL);

CREATE POLICY "owners_admins_can_update_companies"
  ON companies FOR UPDATE
  TO authenticated
  USING (
    EXISTS (
      SELECT 1 FROM memberships m
      WHERE m.company_id = companies.id
      AND m.user_id = (SELECT auth.uid())
      AND m.role IN ('owner', 'admin')
    )
  )
  WITH CHECK (
    EXISTS (
      SELECT 1 FROM memberships m
      WHERE m.company_id = companies.id
      AND m.user_id = (SELECT auth.uid())
      AND m.role IN ('owner', 'admin')
    )
  );

CREATE POLICY "owners_can_delete_companies"
  ON companies FOR DELETE
  TO authenticated
  USING (
    EXISTS (
      SELECT 1 FROM memberships m
      WHERE m.company_id = companies.id
      AND m.user_id = (SELECT auth.uid())
      AND m.role = 'owner'
    )
  );

-- COMMUNITIES: Optimized policies
CREATE POLICY "users_can_view_communities"
  ON communities FOR SELECT
  TO authenticated
  USING (
    EXISTS (
      SELECT 1 FROM memberships m
      WHERE m.company_id = communities.company_id
      AND m.user_id = (SELECT auth.uid())
    )
  );

CREATE POLICY "admins_can_insert_communities"
  ON communities FOR INSERT
  TO authenticated
  WITH CHECK (
    EXISTS (
      SELECT 1 FROM memberships m
      WHERE m.company_id = communities.company_id
      AND m.user_id = (SELECT auth.uid())
      AND m.role IN ('owner', 'admin', 'manager')
    )
  );

CREATE POLICY "admins_can_update_communities"
  ON communities FOR UPDATE
  TO authenticated
  USING (
    EXISTS (
      SELECT 1 FROM memberships m
      WHERE m.company_id = communities.company_id
      AND m.user_id = (SELECT auth.uid())
      AND m.role IN ('owner', 'admin', 'manager')
    )
  )
  WITH CHECK (
    EXISTS (
      SELECT 1 FROM memberships m
      WHERE m.company_id = communities.company_id
      AND m.user_id = (SELECT auth.uid())
      AND m.role IN ('owner', 'admin', 'manager')
    )
  );

CREATE POLICY "admins_can_delete_communities"
  ON communities FOR DELETE
  TO authenticated
  USING (
    EXISTS (
      SELECT 1 FROM memberships m
      WHERE m.company_id = communities.company_id
      AND m.user_id = (SELECT auth.uid())
      AND m.role IN ('owner', 'admin')
    )
  );

-- SITES: Optimized policies
CREATE POLICY "users_can_view_sites"
  ON sites FOR SELECT
  TO authenticated
  USING (
    EXISTS (
      SELECT 1 FROM memberships m
      JOIN communities c ON c.company_id = m.company_id
      WHERE c.id = sites.community_id
      AND m.user_id = (SELECT auth.uid())
    )
  );

CREATE POLICY "admins_can_insert_sites"
  ON sites FOR INSERT
  TO authenticated
  WITH CHECK (
    EXISTS (
      SELECT 1 FROM memberships m
      JOIN communities c ON c.company_id = m.company_id
      WHERE c.id = sites.community_id
      AND m.user_id = (SELECT auth.uid())
      AND m.role IN ('owner', 'admin', 'manager')
    )
  );

CREATE POLICY "admins_can_update_sites"
  ON sites FOR UPDATE
  TO authenticated
  USING (
    EXISTS (
      SELECT 1 FROM memberships m
      JOIN communities c ON c.company_id = m.company_id
      WHERE c.id = sites.community_id
      AND m.user_id = (SELECT auth.uid())
      AND m.role IN ('owner', 'admin', 'manager')
    )
  )
  WITH CHECK (
    EXISTS (
      SELECT 1 FROM memberships m
      JOIN communities c ON c.company_id = m.company_id
      WHERE c.id = sites.community_id
      AND m.user_id = (SELECT auth.uid())
      AND m.role IN ('owner', 'admin', 'manager')
    )
  );

CREATE POLICY "admins_can_delete_sites"
  ON sites FOR DELETE
  TO authenticated
  USING (
    EXISTS (
      SELECT 1 FROM memberships m
      JOIN communities c ON c.company_id = m.company_id
      WHERE c.id = sites.community_id
      AND m.user_id = (SELECT auth.uid())
      AND m.role IN ('owner', 'admin')
    )
  );

-- PLATES: Optimized policies (single set, no duplicates)
CREATE POLICY "users_can_view_plates"
  ON plates FOR SELECT
  TO authenticated
  USING (
    EXISTS (
      SELECT 1 FROM memberships m
      JOIN communities c ON c.company_id = m.company_id
      WHERE c.id = plates.community_id
      AND m.user_id = (SELECT auth.uid())
    )
    OR
    (
      EXISTS (
        SELECT 1 FROM memberships m
        JOIN communities c ON c.company_id = m.company_id
        WHERE c.id = plates.community_id
        AND m.user_id = (SELECT auth.uid())
        AND m.role = 'resident'
      )
      AND plates.tenant = (SELECT auth.email())
    )
  );

CREATE POLICY "admins_can_insert_plates"
  ON plates FOR INSERT
  TO authenticated
  WITH CHECK (
    EXISTS (
      SELECT 1 FROM memberships m
      JOIN communities c ON c.company_id = m.company_id
      WHERE c.id = plates.community_id
      AND m.user_id = (SELECT auth.uid())
      AND m.role IN ('owner', 'admin', 'manager')
    )
  );

CREATE POLICY "admins_can_update_plates"
  ON plates FOR UPDATE
  TO authenticated
  USING (
    EXISTS (
      SELECT 1 FROM memberships m
      JOIN communities c ON c.company_id = m.company_id
      WHERE c.id = plates.community_id
      AND m.user_id = (SELECT auth.uid())
      AND m.role IN ('owner', 'admin', 'manager')
    )
  )
  WITH CHECK (
    EXISTS (
      SELECT 1 FROM memberships m
      JOIN communities c ON c.company_id = m.company_id
      WHERE c.id = plates.community_id
      AND m.user_id = (SELECT auth.uid())
      AND m.role IN ('owner', 'admin', 'manager')
    )
  );

CREATE POLICY "admins_can_delete_plates"
  ON plates FOR DELETE
  TO authenticated
  USING (
    EXISTS (
      SELECT 1 FROM memberships m
      JOIN communities c ON c.company_id = m.company_id
      WHERE c.id = plates.community_id
      AND m.user_id = (SELECT auth.uid())
      AND m.role IN ('owner', 'admin', 'manager')
    )
  );

-- MEMBERSHIPS: Optimized policies
CREATE POLICY "users_can_view_memberships"
  ON memberships FOR SELECT
  TO authenticated
  USING (
    user_id = (SELECT auth.uid())
    OR
    EXISTS (
      SELECT 1 FROM memberships m2
      WHERE m2.company_id = memberships.company_id
      AND m2.user_id = (SELECT auth.uid())
      AND m2.role IN ('owner', 'admin')
    )
  );

CREATE POLICY "admins_can_manage_memberships"
  ON memberships FOR ALL
  TO authenticated
  USING (
    EXISTS (
      SELECT 1 FROM memberships m2
      WHERE m2.company_id = memberships.company_id
      AND m2.user_id = (SELECT auth.uid())
      AND m2.role IN ('owner', 'admin')
    )
  )
  WITH CHECK (
    EXISTS (
      SELECT 1 FROM memberships m2
      WHERE m2.company_id = memberships.company_id
      AND m2.user_id = (SELECT auth.uid())
      AND m2.role IN ('owner', 'admin')
    )
  );

-- USER PROFILES: Optimized policies
CREATE POLICY "users_can_insert_profile"
  ON user_profiles FOR INSERT
  TO authenticated
  WITH CHECK (id = (SELECT auth.uid()));

CREATE POLICY "users_can_update_profile"
  ON user_profiles FOR UPDATE
  TO authenticated
  USING (id = (SELECT auth.uid()))
  WITH CHECK (id = (SELECT auth.uid()));

CREATE POLICY "users_can_delete_profile"
  ON user_profiles FOR DELETE
  TO authenticated
  USING (id = (SELECT auth.uid()));

-- PROPERTIES: Optimized policies (kept for backward compatibility)
CREATE POLICY "admins_can_view_properties"
  ON properties FOR SELECT
  TO authenticated
  USING (
    EXISTS (
      SELECT 1 FROM user_profiles
      WHERE user_profiles.id = (SELECT auth.uid())
      AND user_profiles.role IN ('owner', 'admin')
    )
    OR
    EXISTS (
      SELECT 1 FROM user_profiles
      WHERE user_profiles.id = (SELECT auth.uid())
      AND user_profiles.property_id = properties.id
    )
  );

CREATE POLICY "admins_can_insert_properties"
  ON properties FOR INSERT
  TO authenticated
  WITH CHECK (
    EXISTS (
      SELECT 1 FROM user_profiles
      WHERE user_profiles.id = (SELECT auth.uid())
      AND user_profiles.role IN ('owner', 'admin')
    )
  );

CREATE POLICY "admins_can_update_properties"
  ON properties FOR UPDATE
  TO authenticated
  USING (
    EXISTS (
      SELECT 1 FROM user_profiles
      WHERE user_profiles.id = (SELECT auth.uid())
      AND user_profiles.role IN ('owner', 'admin')
    )
  )
  WITH CHECK (
    EXISTS (
      SELECT 1 FROM user_profiles
      WHERE user_profiles.id = (SELECT auth.uid())
      AND user_profiles.role IN ('owner', 'admin')
    )
  );

CREATE POLICY "admins_can_delete_properties"
  ON properties FOR DELETE
  TO authenticated
  USING (
    EXISTS (
      SELECT 1 FROM user_profiles
      WHERE user_profiles.id = (SELECT auth.uid())
      AND user_profiles.role IN ('owner', 'admin')
    )
  );

-- AUDIT: Optimized policy
CREATE POLICY "users_can_view_audit"
  ON audit FOR SELECT
  TO authenticated
  USING (
    EXISTS (
      SELECT 1 FROM user_profiles
      WHERE user_profiles.id = (SELECT auth.uid())
      AND (
        user_profiles.role IN ('owner', 'admin')
        OR user_profiles.property_id = audit.property_id
      )
    )
    OR
    EXISTS (
      SELECT 1 FROM memberships m
      JOIN communities c ON c.company_id = m.company_id
      WHERE c.id = audit.community_id
      AND m.user_id = (SELECT auth.uid())
    )
  );

-- POD HEALTH: Optimized policies
CREATE POLICY "users_can_view_pod_health"
  ON pod_health FOR SELECT
  TO authenticated
  USING (
    EXISTS (
      SELECT 1 FROM memberships m
      JOIN communities c ON c.company_id = m.company_id
      JOIN sites s ON s.community_id = c.id
      WHERE s.id = pod_health.site_id
      AND m.user_id = (SELECT auth.uid())
    )
  );

CREATE POLICY "managers_can_manage_pod_health"
  ON pod_health FOR ALL
  TO authenticated
  USING (
    EXISTS (
      SELECT 1 FROM memberships m
      JOIN communities c ON c.company_id = m.company_id
      JOIN sites s ON s.community_id = c.id
      WHERE s.id = pod_health.site_id
      AND m.user_id = (SELECT auth.uid())
      AND m.role IN ('owner', 'admin', 'manager')
    )
  )
  WITH CHECK (
    EXISTS (
      SELECT 1 FROM memberships m
      JOIN communities c ON c.company_id = m.company_id
      JOIN sites s ON s.community_id = c.id
      WHERE s.id = pod_health.site_id
      AND m.user_id = (SELECT auth.uid())
      AND m.role IN ('owner', 'admin', 'manager')
    )
  );

-- GATEWISE CONFIG: Optimized policy (single policy for both view and manage)
CREATE POLICY "users_can_manage_gatewise"
  ON gatewise_config FOR ALL
  TO authenticated
  USING (
    EXISTS (
      SELECT 1 FROM memberships m
      JOIN communities c ON c.company_id = m.company_id
      WHERE c.id = gatewise_config.community_id
      AND m.user_id = (SELECT auth.uid())
    )
  )
  WITH CHECK (
    EXISTS (
      SELECT 1 FROM memberships m
      JOIN communities c ON c.company_id = m.company_id
      WHERE c.id = gatewise_config.community_id
      AND m.user_id = (SELECT auth.uid())
      AND m.role IN ('owner', 'admin', 'manager')
    )
  );

-- SYSTEM METRICS: Optimized policy (single policy)
CREATE POLICY "users_can_manage_metrics"
  ON system_metrics FOR ALL
  TO authenticated
  USING (
    EXISTS (
      SELECT 1 FROM memberships m
      WHERE m.company_id = system_metrics.company_id
      AND m.user_id = (SELECT auth.uid())
    )
  )
  WITH CHECK (
    EXISTS (
      SELECT 1 FROM memberships m
      WHERE m.company_id = system_metrics.company_id
      AND m.user_id = (SELECT auth.uid())
      AND m.role IN ('owner', 'admin', 'manager')
    )
  );

-- ============================================================================
-- STEP 3: Fix function search paths
-- ============================================================================

ALTER FUNCTION update_updated_at_column() SET search_path = pg_catalog, public;
ALTER FUNCTION update_pod_health_timestamp() SET search_path = pg_catalog, public;

-- ============================================================================
-- STEP 4: Drop unused indexes
-- ============================================================================

DROP INDEX IF EXISTS idx_plates_plate;
DROP INDEX IF EXISTS idx_plates_enabled;
DROP INDEX IF EXISTS idx_audit_property;
DROP INDEX IF EXISTS idx_audit_ts;
DROP INDEX IF EXISTS idx_user_profiles_role;
DROP INDEX IF EXISTS idx_user_profiles_property;
DROP INDEX IF EXISTS idx_plates_site_ids;
DROP INDEX IF EXISTS idx_pod_health_site_id;
DROP INDEX IF EXISTS idx_pod_health_status;
DROP INDEX IF EXISTS idx_pod_health_last_checkin;
DROP INDEX IF EXISTS idx_gatewise_config_enabled;
DROP INDEX IF EXISTS idx_system_metrics_date;
