import { useState } from 'react'
import { Link } from 'react-router-dom'
import { useQuery } from '@tanstack/react-query'
import { useTranslation } from 'react-i18next'
import { organizationApi } from '@/features/organizations/organization-api'
import { catalogName } from '@/i18n/catalog-labels'
import { collaborationApi } from './collaboration-api'
import { button, control, panel, CollaborationHeader, Field, LoadState, Paging, useCollaborationActor } from './collaboration-ui'

export function ProfessionalDirectoryPage() {
  const { t } = useTranslation()
  const actor = useCollaborationActor()
  const [search, setSearch] = useState('')
  const [filters, setFilters] = useState({ q: '', country: '', category: '', page: 1 })
  const query = useQuery({ queryKey: ['collaboration', actor, 'professionals', filters], queryFn: ({ signal }) => collaborationApi.professionals(filters.q, filters.country, filters.category, filters.page, signal) })
  const catalogs = useQuery({ queryKey: ['organization-catalogs'], queryFn: ({ signal }) => organizationApi.catalogs(signal) })
  return <div className="space-y-6"><CollaborationHeader title="directory" />
    <form className={panel} onSubmit={event => { event.preventDefault(); setFilters(current => ({ ...current, q: search.trim(), page: 1 })) }}>
      <Field label={t('collaboration.searchHint')}><input className={control} maxLength={200} value={search} onChange={e => setSearch(e.target.value)} /></Field>
      <div className="grid gap-4 sm:grid-cols-2">
        <Field label={t('collaboration.country')}><select className={control} value={filters.country} onChange={e => setFilters(current => ({ ...current, country: e.target.value, page: 1 }))}><option value="">{t('collaboration.allCountries')}</option>{catalogs.data?.countries.map(item => <option key={item.id} value={item.id}>{catalogName('countries', item)}</option>)}</select></Field>
        <Field label={t('collaboration.categories')}><select className={control} value={filters.category} onChange={e => setFilters(current => ({ ...current, category: e.target.value, page: 1 }))}><option value="">{t('collaboration.allCategories')}</option>{catalogs.data?.fundingCategories.map(item => <option key={item.id} value={item.id}>{catalogName('fundingCategories', item)}</option>)}</select></Field>
      </div><button className={button}>{t('collaboration.search')}</button>
    </form>
    <LoadState pending={query.isPending} error={query.error ?? catalogs.error} retry={() => Promise.all([query.refetch(), catalogs.refetch()])} />
    {query.data && <><div className="grid gap-4 lg:grid-cols-2">{query.data.items.map(profile => <article key={profile.profileId} className={panel}>
      <h2 className="text-lg font-semibold">{profile.data.displayName}</h2><p>{profile.data.headline}</p>
      {profile.data.biography && <p className="whitespace-pre-wrap break-words">{profile.data.biography}</p>}
      <p className="break-words">{profile.data.skills.join(' · ')}</p>
      <p className="text-sm">{t(profile.data.allowsInvitations ? 'collaboration.invitesEnabled' : 'collaboration.invitesDisabled')}</p>
      {profile.data.allowsInvitations && <Link className={button} to={`/collaboration/consortia?professionalId=${encodeURIComponent(profile.profileId)}`}>{t('collaboration.chooseConsortium')}</Link>}
    </article>)}</div>{query.data.items.length === 0 && <p>{t('collaboration.empty')}</p>}
    <Paging page={filters.page} total={query.data.totalCount} disabled={query.isFetching} setPage={page => setFilters(current => ({ ...current, page }))} /></>}
  </div>
}

