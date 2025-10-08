/*
  # Update RLS Policies for Companies → Sites Structure

  Update all RLS policies to use the new naming:
  - companies (formerly communities)
  - sites (formerly properties)
  - company_id (formerly community_id)
  - site_id (formerly property_id)
*/

-- Drop all existing policies
DROP POLICY IF EXISTS "communities_select" ON public.companies;
DROP POLICY IF EXISTS "communities_insert" ON public.companies;
DROP POLICY IF EXISTS "communities_update" ON public.companies;
DROP POLICY IF EXISTS "communities_delete" ON public.companies;
DROP POLICY IF EXISTS "companies_select" ON public.companies;
DROP POLICY IF EXISTS "companies_insert" ON public.companies;
DROP POLICY IF EXISTS "companies_update" ON public.companies;
DROP POLICY IF EXISTS "companies_delete" ON public.companies;

DROP POLICY IF EXISTS "properties_select" ON public.sites;
DROP POLICY IF EXISTS "properties_insert" ON public.sites;
DROP POLICY IF EXISTS "properties_update" ON public.sites;
DROP POLICY IF EXISTS "properties_delete" ON public.sites;
DROP POLICY IF EXISTS "sites_select" ON public.sites;
DROP POLICY IF EXISTS "sites_insert" ON public.sites;
DROP POLICY IF EXISTS "sites_update" ON public.sites;
DROP POLICY IF EXISTS "sites_delete" ON public.sites;

DROP POLICY IF EXISTS "whitelist_select" ON public.whitelist;
DROP POLICY IF EXISTS "whitelist_insert" ON public.whitelist;
DROP POLICY IF EXISTS "whitelist_update" ON public.whitelist;
DROP POLICY IF EXISTS "whitelist_delete" ON public.whitelist;

DROP POLICY IF EXISTS "audit_select" ON public.audit;
DROP POLICY IF EXISTS "audit_insert" ON public.audit;

-- Companies policies
CREATE POLICY "companies_select" ON public.companies
  FOR SELECT
  TO authenticated
  USING (
    public.jwt_role() IN ('owner', 'admin') OR
    EXISTS (
      SELECT 1 FROM public.memberships m
      WHERE m.user_id = public.jwt_user_id() 
        AND m.company_id = companies.id
    )
  );

CREATE POLICY "companies_insert" ON public.companies
  FOR INSERT
  TO authenticated
  WITH CHECK (public.jwt_role() IN ('owner', 'admin'));

CREATE POLICY "companies_update" ON public.companies
  FOR UPDATE
  TO authenticated
  USING (public.jwt_role() IN ('owner', 'admin'))
  WITH CHECK (public.jwt_role() IN ('owner', 'admin'));

CREATE POLICY "companies_delete" ON public.companies
  FOR DELETE
  TO authenticated
  USING (public.jwt_role() IN ('owner', 'admin'));

-- Sites policies
CREATE POLICY "sites_select" ON public.sites
  FOR SELECT
  TO authenticated
  USING (
    public.jwt_role() IN ('owner', 'admin') OR
    EXISTS (
      SELECT 1 FROM public.memberships m
      WHERE m.user_id = public.jwt_user_id()
        AND m.company_id = sites.company_id
    )
  );

CREATE POLICY "sites_insert" ON public.sites
  FOR INSERT
  TO authenticated
  WITH CHECK (
    public.jwt_role() IN ('owner', 'admin') OR
    EXISTS (
      SELECT 1 FROM public.memberships m
      WHERE m.user_id = public.jwt_user_id()
        AND m.company_id = sites.company_id
        AND m.role = 'community_admin'
    )
  );

CREATE POLICY "sites_update" ON public.sites
  FOR UPDATE
  TO authenticated
  USING (
    public.jwt_role() IN ('owner', 'admin') OR
    EXISTS (
      SELECT 1 FROM public.memberships m
      WHERE m.user_id = public.jwt_user_id()
        AND m.company_id = sites.company_id
        AND m.role = 'community_admin'
    )
  )
  WITH CHECK (
    public.jwt_role() IN ('owner', 'admin') OR
    EXISTS (
      SELECT 1 FROM public.memberships m
      WHERE m.user_id = public.jwt_user_id()
        AND m.company_id = sites.company_id
        AND m.role = 'community_admin'
    )
  );

CREATE POLICY "sites_delete" ON public.sites
  FOR DELETE
  TO authenticated
  USING (
    public.jwt_role() IN ('owner', 'admin') OR
    EXISTS (
      SELECT 1 FROM public.memberships m
      WHERE m.user_id = public.jwt_user_id()
        AND m.company_id = sites.company_id
        AND m.role = 'community_admin'
    )
  );

-- Whitelist policies
CREATE POLICY "whitelist_select" ON public.whitelist
  FOR SELECT
  TO authenticated
  USING (
    public.jwt_role() IN ('owner', 'admin') OR
    EXISTS (
      SELECT 1
      FROM public.sites s
      JOIN public.memberships m ON m.company_id = s.company_id
      WHERE s.id = whitelist.site_id
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
      FROM public.sites s
      JOIN public.memberships m ON m.company_id = s.company_id
      WHERE s.id = whitelist.site_id
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
      FROM public.sites s
      JOIN public.memberships m ON m.company_id = s.company_id
      WHERE s.id = whitelist.site_id
        AND m.user_id = public.jwt_user_id()
        AND m.role IN ('community_admin', 'manager')
    )
  )
  WITH CHECK (
    public.jwt_role() IN ('owner', 'admin') OR
    EXISTS (
      SELECT 1
      FROM public.sites s
      JOIN public.memberships m ON m.company_id = s.company_id
      WHERE s.id = whitelist.site_id
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
      FROM public.sites s
      JOIN public.memberships m ON m.company_id = s.company_id
      WHERE s.id = whitelist.site_id
        AND m.user_id = public.jwt_user_id()
        AND m.role IN ('community_admin', 'manager')
    )
  );

-- Audit policies
CREATE POLICY "audit_select" ON public.audit
  FOR SELECT
  TO authenticated
  USING (
    public.jwt_role() IN ('owner', 'admin') OR
    EXISTS (
      SELECT 1 FROM public.memberships m
      WHERE m.user_id = public.jwt_user_id()
        AND m.company_id = audit.company_id
    )
  );

CREATE POLICY "audit_insert" ON public.audit
  FOR INSERT
  TO authenticated
  WITH CHECK (true);
