'use client';

import { createContext, useContext, useEffect, useState, ReactNode } from 'react';
import { supabase } from './supabase';
import { useAuth } from './auth-context';

interface Company {
  id: string;
  name: string;
  is_active: boolean;
}

interface Membership {
  id: string;
  company_id: string;
  role: string;
  companies: Company | Company[];
}

interface CompanyContextType {
  activeCompanyId: string | null;
  setActiveCompanyId: (id: string) => void;
  memberships: Membership[];
  activeCompany: Company | null;
  activeRole: string | null;
  effectiveRole: string | null;
  loading: boolean;
  refreshMemberships: () => Promise<void>;
}

const CompanyContext = createContext<CompanyContextType | undefined>(undefined);

export function CompanyProvider({ children }: { children: ReactNode }) {
  const { user, loading: authLoading, effectiveRole: authEffectiveRole } = useAuth();
  const [activeCompanyId, setActiveCompanyIdState] = useState<string | null>(null);
  const [memberships, setMemberships] = useState<Membership[]>([]);
  const [loading, setLoading] = useState(true);

  const fetchMemberships = async () => {
    if (!user) {
      setMemberships([]);
      setLoading(false);
      return;
    }

    setLoading(true);

    const { data } = await supabase
      .from('memberships')
      .select(`
        id,
        company_id,
        role,
        companies (
          id,
          name,
          is_active
        )
      `)
      .eq('user_id', user.id)
      .order('created_at');

    if (data && data.length > 0) {
      setMemberships(data as Membership[]);

      const stored = localStorage.getItem('activeCompanyId');
      if (stored && data.find(m => m.company_id === stored)) {
        setActiveCompanyIdState(stored);
      } else {
        setActiveCompanyIdState(data[0].company_id);
      }
    } else {
      setMemberships([]);
      setActiveCompanyIdState(null);
    }

    setLoading(false);
  };

  useEffect(() => {
    if (!authLoading) {
      fetchMemberships();
    }
  }, [user, authLoading]);

  const setActiveCompanyId = (id: string) => {
    setActiveCompanyIdState(id);
    localStorage.setItem('activeCompanyId', id);
  };

  const membership = memberships.find(m => m.company_id === activeCompanyId);
  const activeCompany = membership ? (Array.isArray(membership.companies) ? membership.companies[0] : membership.companies) : null;
  const activeRole = membership?.role || null;

  return (
    <CompanyContext.Provider
      value={{
        activeCompanyId,
        setActiveCompanyId,
        memberships,
        activeCompany,
        activeRole,
        effectiveRole: authEffectiveRole,
        loading,
        refreshMemberships: fetchMemberships,
      }}
    >
      {children}
    </CompanyContext.Provider>
  );
}

export function useCompany() {
  const context = useContext(CompanyContext);
  if (context === undefined) {
    throw new Error('useCompany must be used within a CompanyProvider');
  }
  return context;
}

export const CommunityProvider = CompanyProvider;
export const useCommunity = useCompany;
