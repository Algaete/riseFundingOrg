import { useState } from 'react'
import { useQuery } from '@tanstack/react-query'
import { useTranslation } from 'react-i18next'
import { Link, useNavigate, useSearchParams } from 'react-router-dom'
import { Button } from '@/components/ui/button'
import { useAuth } from '@/features/auth/use-auth'
import { organizationApi } from '@/features/organizations/organization-api'
import { SearchForm } from './search-form'
import { SearchResults, SearchSignIn } from './search-results'
import { readSearchCriteria, searchQueryPolicy, searchSources, unifiedSearchUrl, type SearchCriteria } from './search-model'

function OrganizationResults({ criteria, actor }: { criteria: SearchCriteria; actor: string }) {
  const { t } = useTranslation()
  const navigate = useNavigate()
  const [selected, setSelected] = useState('')
  const memberships = useQuery({ queryKey: ['unified-search', 'memberships', actor],
    queryFn: ({ signal }) => organizationApi.list(signal), ...searchQueryPolicy })
  const organizations = memberships.data ?? []
  const organizationId = organizations.some(item => item.publicId === selected) ? selected
    : organizations.length === 1 ? organizations[0].publicId : ''
  if (memberships.isPending) return <p role="status">{t('unifiedSearch.loadingOrganizations')}</p>
  if (memberships.isError) return <section className="space-y-3 rounded-xl border p-5" role="alert">
    <h2 className="text-xl font-bold">{t('unifiedSearch.sources.organizations')}</h2>
    <p>{t('unifiedSearch.membershipError')}</p><Button variant="outline" onClick={() => void memberships.refetch()}>{t('unifiedSearch.retry')}</Button>
  </section>
  if (organizations.length === 0) return <section className="space-y-3 rounded-xl border p-5">
    <h2 className="text-xl font-bold">{t('unifiedSearch.sources.organizations')}</h2><p>{t('unifiedSearch.organizationRequired')}</p>
    <Button asChild variant="outline"><Link to="/onboarding">{t('unifiedSearch.createOrganization')}</Link></Button>
  </section>
  return <div className="space-y-3">
    <label className="grid gap-2 text-sm font-semibold">{t('unifiedSearch.organizationContext')}
      <select className="w-full max-w-lg rounded-lg border bg-background p-2" value={organizationId} onChange={e => {
        setSelected(e.target.value)
        if (criteria.page !== 1) navigate(unifiedSearchUrl(criteria.scope, criteria.q, criteria.countryId, criteria.categoryId))
      }}><option value="">{t('unifiedSearch.chooseOrganization')}</option>{organizations.map(item => <option key={item.publicId} value={item.publicId}>{item.name}</option>)}</select>
    </label>
    {organizationId ? <SearchResults key={organizationId} source="organizations" criteria={criteria} actor={actor} organizationId={organizationId} />
      : <p role="status">{t('unifiedSearch.chooseOrganizationHelp')}</p>}
  </div>
}

export function UnifiedSearchPage() {
  const auth = useAuth()
  const actor = auth.status === 'authenticated' ? auth.session?.user.publicId : undefined
  // Private results and pending requests never carry over to another session identity.
  return <SearchWorkspace key={actor ?? 'anonymous'} actor={actor} initializing={auth.status === 'initializing'} />
}

function SearchWorkspace({ actor, initializing }: { actor?: string; initializing: boolean }) {
  const { t } = useTranslation()
  const [params] = useSearchParams()
  const { criteria, valid, submitted } = readSearchCriteria(params)
  const sources = criteria.scope === 'all' ? searchSources : [criteria.scope]
  return <div className="mx-auto max-w-6xl space-y-6 px-4 py-8 sm:px-6">
    <header className="space-y-3"><h1 className="text-3xl font-bold">{t('unifiedSearch.title')}</h1><p className="text-muted-foreground">{t('unifiedSearch.intro')}</p></header>
    <SearchForm key={params.toString()} criteria={criteria} />
    {!valid ? <p role="alert" className="rounded-lg border border-destructive/40 p-4">{t('unifiedSearch.invalidFilters')}</p>
      : !submitted ? <p role="status">{t('unifiedSearch.start')}</p> : <>
        <p className="text-sm text-muted-foreground">{t('unifiedSearch.visibility')}</p>
        {sources.map(source => source === 'projects' || source === 'funding'
          ? <SearchResults key={source} source={source} criteria={criteria} actor="public" />
          : !actor ? <SearchSignIn key={source} source={source} initializing={initializing} />
            : source === 'organizations' ? <OrganizationResults key={source} criteria={criteria} actor={actor} />
              : <SearchResults key={source} source={source} criteria={criteria} actor={actor} />)}
      </>}
  </div>
}
