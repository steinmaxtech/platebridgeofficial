/*
  # Restructure to Companies → Sites → Whitelist

  1. Rename Tables
    - Rename `communities` to `companies` (property management companies)
    - Rename `properties` to `sites` (individual locations/communities with pods)

  2. Update Relationships
    - `memberships` now maps users to companies
    - `sites` belong to companies
    - `whitelist` belongs to sites
    - `audit` tracks both company and site

  3. Update Foreign Keys
    - Rename all `community_id` to `company_id`
    - Rename `property_id` to `site_id` (uuid version)
*/

-- Rename communities table to companies
ALTER TABLE IF EXISTS public.communities RENAME TO companies;

-- Rename properties table to sites
ALTER TABLE IF EXISTS public.properties RENAME TO sites;

-- Rename columns in memberships
DO $$
BEGIN
  IF EXISTS (
    SELECT 1 FROM information_schema.columns 
    WHERE table_name = 'memberships' AND column_name = 'community_id'
  ) THEN
    ALTER TABLE public.memberships RENAME COLUMN community_id TO company_id;
  END IF;
END $$;

-- Rename columns in sites (formerly properties)
DO $$
BEGIN
  IF EXISTS (
    SELECT 1 FROM information_schema.columns 
    WHERE table_name = 'sites' AND column_name = 'community_id'
  ) THEN
    ALTER TABLE public.sites RENAME COLUMN community_id TO company_id;
  END IF;
END $$;

-- Update audit table - drop old site_id text column, rename property_id to site_id
ALTER TABLE public.audit DROP COLUMN IF EXISTS site_id;

DO $$
BEGIN
  IF EXISTS (
    SELECT 1 FROM information_schema.columns 
    WHERE table_name = 'audit' AND column_name = 'property_id'
  ) THEN
    ALTER TABLE public.audit RENAME COLUMN property_id TO site_id;
  END IF;
  
  IF EXISTS (
    SELECT 1 FROM information_schema.columns 
    WHERE table_name = 'audit' AND column_name = 'community_id'
  ) THEN
    ALTER TABLE public.audit RENAME COLUMN community_id TO company_id;
  END IF;
END $$;

-- Rename columns in whitelist
DO $$
BEGIN
  IF EXISTS (
    SELECT 1 FROM information_schema.columns 
    WHERE table_name = 'whitelist' AND column_name = 'property_id'
  ) THEN
    ALTER TABLE public.whitelist RENAME COLUMN property_id TO site_id;
  END IF;
END $$;

-- Update constraint names for clarity
ALTER TABLE public.memberships DROP CONSTRAINT IF EXISTS memberships_community_id_fkey;
ALTER TABLE public.memberships DROP CONSTRAINT IF EXISTS memberships_company_id_fkey;
ALTER TABLE public.memberships ADD CONSTRAINT memberships_company_id_fkey 
  FOREIGN KEY (company_id) REFERENCES public.companies(id) ON DELETE CASCADE;

ALTER TABLE public.sites DROP CONSTRAINT IF EXISTS properties_community_id_fkey;
ALTER TABLE public.sites DROP CONSTRAINT IF EXISTS sites_company_id_fkey;
ALTER TABLE public.sites ADD CONSTRAINT sites_company_id_fkey 
  FOREIGN KEY (company_id) REFERENCES public.companies(id) ON DELETE CASCADE;

ALTER TABLE public.audit DROP CONSTRAINT IF EXISTS audit_community_id_fkey;
ALTER TABLE public.audit DROP CONSTRAINT IF EXISTS audit_property_id_fkey;
ALTER TABLE public.audit DROP CONSTRAINT IF EXISTS audit_company_id_fkey;
ALTER TABLE public.audit DROP CONSTRAINT IF EXISTS audit_site_id_fkey;
ALTER TABLE public.audit ADD CONSTRAINT audit_company_id_fkey 
  FOREIGN KEY (company_id) REFERENCES public.companies(id);
ALTER TABLE public.audit ADD CONSTRAINT audit_site_id_fkey 
  FOREIGN KEY (site_id) REFERENCES public.sites(id);

ALTER TABLE public.whitelist DROP CONSTRAINT IF EXISTS whitelist_property_id_fkey;
ALTER TABLE public.whitelist DROP CONSTRAINT IF EXISTS whitelist_site_id_fkey;
ALTER TABLE public.whitelist ADD CONSTRAINT whitelist_site_id_fkey 
  FOREIGN KEY (site_id) REFERENCES public.sites(id) ON DELETE CASCADE;

-- Rename indexes
DROP INDEX IF EXISTS idx_memberships_community_id;
DROP INDEX IF EXISTS idx_properties_community_id;
DROP INDEX IF EXISTS idx_audit_events_community_id;
DROP INDEX IF EXISTS idx_memberships_company_id;
DROP INDEX IF EXISTS idx_sites_company_id;
DROP INDEX IF EXISTS idx_audit_company_id;
DROP INDEX IF EXISTS idx_whitelist_site_id;

CREATE INDEX IF NOT EXISTS idx_memberships_company_id ON public.memberships(company_id);
CREATE INDEX IF NOT EXISTS idx_sites_company_id ON public.sites(company_id);
CREATE INDEX IF NOT EXISTS idx_audit_company_id ON public.audit(company_id);
CREATE INDEX IF NOT EXISTS idx_whitelist_site_id ON public.whitelist(site_id);

-- Update the default company name
UPDATE public.companies SET name = 'Default Company' WHERE name = 'Default Community';
