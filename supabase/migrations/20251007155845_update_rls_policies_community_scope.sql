/*
  # Update RLS Policies for Community-Scoped Access

  1. Properties Table
    - Drop existing policies
    - Create new community-scoped policies
    - Global owner/admin can access all
    - Community members can only access properties in their communities

  2. Whitelist Table
    - Drop existing policies
    - Create new community-scoped policies via property → community join
    - Managers can write, viewers can only read

  3. Audit Table
    - Drop existing policies
    - Create new community-scoped policies
    - Filter by community_id
*/

-- Drop existing policies on properties
DROP POLICY IF EXISTS "properties_select" ON public.properties;
DROP POLICY IF EXISTS "properties_insert" ON public.properties;
DROP POLICY IF EXISTS "properties_update" ON public.properties;
DROP POLICY IF EXISTS "properties_delete" ON public.properties;

-- Create new community-scoped policies for properties
CREATE POLICY "properties_select" ON public.properties
  FOR SELECT
  TO authenticated
  USING (
    public.jwt_role() IN ('owner', 'admin') OR
    EXISTS (
      SELECT 1 FROM public.memberships m
      WHERE m.user_id = public.jwt_user_id()
        AND m.community_id = properties.community_id
    )
  );

CREATE POLICY "properties_insert" ON public.properties
  FOR INSERT
  TO authenticated
  WITH CHECK (
    public.jwt_role() IN ('owner', 'admin') OR
    EXISTS (
      SELECT 1 FROM public.memberships m
      WHERE m.user_id = public.jwt_user_id()
        AND m.community_id = properties.community_id
        AND m.role = 'community_admin'
    )
  );

CREATE POLICY "properties_update" ON public.properties
  FOR UPDATE
  TO authenticated
  USING (
    public.jwt_role() IN ('owner', 'admin') OR
    EXISTS (
      SELECT 1 FROM public.memberships m
      WHERE m.user_id = public.jwt_user_id()
        AND m.community_id = properties.community_id
        AND m.role = 'community_admin'
    )
  )
  WITH CHECK (
    public.jwt_role() IN ('owner', 'admin') OR
    EXISTS (
      SELECT 1 FROM public.memberships m
      WHERE m.user_id = public.jwt_user_id()
        AND m.community_id = properties.community_id
        AND m.role = 'community_admin'
    )
  );

CREATE POLICY "properties_delete" ON public.properties
  FOR DELETE
  TO authenticated
  USING (
    public.jwt_role() IN ('owner', 'admin') OR
    EXISTS (
      SELECT 1 FROM public.memberships m
      WHERE m.user_id = public.jwt_user_id()
        AND m.community_id = properties.community_id
        AND m.role = 'community_admin'
    )
  );

-- Drop existing policies on whitelist
DROP POLICY IF EXISTS "whitelist_select" ON public.whitelist;
DROP POLICY IF EXISTS "whitelist_insert" ON public.whitelist;
DROP POLICY IF EXISTS "whitelist_update" ON public.whitelist;
DROP POLICY IF EXISTS "whitelist_delete" ON public.whitelist;

-- Create new community-scoped policies for whitelist
CREATE POLICY "whitelist_select" ON public.whitelist
  FOR SELECT
  TO authenticated
  USING (
    public.jwt_role() IN ('owner', 'admin') OR
    EXISTS (
      SELECT 1
      FROM public.properties p
      JOIN public.memberships m ON m.community_id = p.community_id
      WHERE p.id = whitelist.property_id
        AND m.user_id = public.jwt_user_id()
    )
  );

CREATE POLICY "whitelist_insert" ON public.whitelist
  FOR INSERT
  TO authenticated
  WITH CHECK (
    public.jwt_role() IN ('owner', 'admin') OR
    EXISTS (
      SELECT 1
      FROM public.properties p
      JOIN public.memberships m ON m.community_id = p.community_id
      WHERE p.id = whitelist.property_id
        AND m.user_id = public.jwt_user_id()
        AND m.role IN ('community_admin', 'manager')
    )
  );

CREATE POLICY "whitelist_update" ON public.whitelist
  FOR UPDATE
  TO authenticated
  USING (
    public.jwt_role() IN ('owner', 'admin') OR
    EXISTS (
      SELECT 1
      FROM public.properties p
      JOIN public.memberships m ON m.community_id = p.community_id
      WHERE p.id = whitelist.property_id
        AND m.user_id = public.jwt_user_id()
        AND m.role IN ('community_admin', 'manager')
    )
  )
  WITH CHECK (
    public.jwt_role() IN ('owner', 'admin') OR
    EXISTS (
      SELECT 1
      FROM public.properties p
      JOIN public.memberships m ON m.community_id = p.community_id
      WHERE p.id = whitelist.property_id
        AND m.user_id = public.jwt_user_id()
        AND m.role IN ('community_admin', 'manager')
    )
  );

CREATE POLICY "whitelist_delete" ON public.whitelist
  FOR DELETE
  TO authenticated
  USING (
    public.jwt_role() IN ('owner', 'admin') OR
    EXISTS (
      SELECT 1
      FROM public.properties p
      JOIN public.memberships m ON m.community_id = p.community_id
      WHERE p.id = whitelist.property_id
        AND m.user_id = public.jwt_user_id()
        AND m.role IN ('community_admin', 'manager')
    )
  );

-- Drop existing policies on audit
DROP POLICY IF EXISTS "audit_select" ON public.audit;
DROP POLICY IF EXISTS "audit_insert" ON public.audit;

-- Create new community-scoped policies for audit
CREATE POLICY "audit_select" ON public.audit
  FOR SELECT
  TO authenticated
  USING (
    public.jwt_role() IN ('owner', 'admin') OR
    EXISTS (
      SELECT 1 FROM public.memberships m
      WHERE m.user_id = public.jwt_user_id()
        AND m.community_id = audit.community_id
    )
  );

-- Audit inserts should be handled by API/edge functions with service role
CREATE POLICY "audit_insert" ON public.audit
  FOR INSERT
  TO authenticated
  WITH CHECK (true);
