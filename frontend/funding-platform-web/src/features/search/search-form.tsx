import { useState, type FormEvent } from 'react'
import { useTranslation } from 'react-i18next'
import { useQuery } from '@tanstack/react-query'
import { useNavigate } from 'react-router-dom'
import { marketplaceApi } from '@/features/marketplace/marketplace-api'
import { catalogName, catalogLanguage } from '@/i18n/catalog-display'
import { Button } from '@/components/ui/button'
import { Input } from '@/components/ui/input'
import { searchSources, unifiedSearchUrl, type SearchCriteria, type SearchScope } from './search-model'

export function SearchForm({ criteria }: { criteria: SearchCriteria }) {
  const { t } = useTranslation()
  const navigate = useNavigate()
  const [draft, setDraft] = useState(criteria)
  const catalogs = useQuery({ queryKey: ['marketplace', 'catalogs'], queryFn: ({ signal }) => marketplaceApi.catalogs(signal),
    staleTime: 60 * 60 * 1000, retry: false, refetchOnWindowFocus: false, refetchOnReconnect: false })
  function submit(event: FormEvent<HTMLFormElement>) {
    event.preventDefault()
    navigate(unifiedSearchUrl(draft.scope, draft.q, draft.countryId, draft.categoryId))
  }
  const control = 'min-w-0 w-full rounded-lg border bg-background px-3 py-2 text-sm'
  return <form role="search" aria-label={t('unifiedSearch.title')} onSubmit={submit} className="space-y-4 rounded-xl border bg-card p-4 sm:p-6">
    <label className="grid gap-2 text-sm font-semibold">{t('home.search.query')}
      <Input type="search" maxLength={200} value={draft.q} onChange={e => setDraft({ ...draft, q: e.target.value })} placeholder={t('unifiedSearch.placeholder')} />
    </label>
    <div className="grid gap-4 sm:grid-cols-3">
      <label className="grid gap-2 text-sm font-semibold">{t('home.search.scope')}
        <select className={control} value={draft.scope} onChange={e => setDraft({ ...draft, scope: e.target.value as SearchScope })}>
          {(['all', ...searchSources] as const).map(scope => <option key={scope} value={scope}>{t(`unifiedSearch.sources.${scope}`)}</option>)}
        </select>
      </label>
      {(['countryId', 'categoryId'] as const).map(key => {
        const country = key === 'countryId'
        const items = country ? catalogs.data?.countries : catalogs.data?.fundingCategories
        const catalog = country ? 'countries' : 'fundingCategories'
        return <label key={key} className="grid gap-2 text-sm font-semibold">{t(country ? 'home.search.country' : 'home.search.sector')}
          <select className={control} value={draft[key]} onChange={e => setDraft({ ...draft, [key]: e.target.value })}>
            <option value="">{t(country ? 'home.search.allCountries' : 'home.search.allSectors')}</option>
            {draft[key] && !items?.some(item => String(item.id) === draft[key]) && <option value={draft[key]}>{t('unifiedSearch.selectedFilter', { id: draft[key] })}</option>}
            {items?.map(item => <option key={item.id} value={item.id} lang={catalogLanguage(catalog, item)}>{catalogName(catalog, item)}</option>)}
          </select>
        </label>
      })}
    </div>
    <p className="text-xs text-muted-foreground">{t('unifiedSearch.countryHelp')}</p>
    {catalogs.isError && <p role="status" className="text-sm">{t('home.search.catalogsError')} <Button type="button" variant="outline" onClick={() => void catalogs.refetch()}>{t('home.search.retry')}</Button></p>}
    <Button type="submit">{t('home.search.submit')}</Button>
  </form>
}
