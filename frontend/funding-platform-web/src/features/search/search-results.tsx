import { useQuery } from '@tanstack/react-query'
import { useTranslation } from 'react-i18next'
import { Link, useLocation } from 'react-router-dom'
import { Button } from '@/components/ui/button'
import { searchSource } from './search-api'
import { searchQueryPolicy, unifiedSearchUrl, type SearchCriteria, type SearchSource } from './search-model'

export function SearchSignIn({ source, initializing }: { source: SearchSource; initializing: boolean }) {
  const { t } = useTranslation()
  const location = useLocation()
  return <section className="space-y-3 rounded-xl border bg-card p-5" aria-labelledby={`search-${source}`}>
    <h2 id={`search-${source}`} className="text-xl font-bold">{t(`unifiedSearch.sources.${source}`)}</h2>
    <p role="status">{t(initializing ? 'status.checkingSession' : 'unifiedSearch.signInRequired')}</p>
    {!initializing && <Button asChild variant="outline"><Link to="/login" state={{ from: location.pathname + location.search }}>{t('actions.signIn')}</Link></Button>}
  </section>
}

export function SearchResults({ source, criteria, actor, organizationId }: {
  source: SearchSource; criteria: SearchCriteria; actor: string; organizationId?: string
}) {
  const { t, i18n } = useTranslation()
  const privateSource = source === 'organizations' || source === 'professionals'
  const query = useQuery({ queryKey: ['unified-search', source, privateSource ? actor : 'public', organizationId ?? '', criteria],
    queryFn: ({ signal }) => searchSource(source, criteria, signal, organizationId), ...searchQueryPolicy })
  const href = (page = 1) => unifiedSearchUrl(source, criteria.q, criteria.countryId, criteria.categoryId, page)
  const count = (value: number) => new Intl.NumberFormat(i18n.resolvedLanguage ?? 'es').format(value)
  return <section aria-labelledby={`search-${source}`} className="min-w-0 space-y-4 rounded-xl border bg-card p-4 sm:p-6">
    <header className="flex flex-wrap items-center justify-between gap-3">
      <h2 id={`search-${source}`} className="text-xl font-bold">{t(`unifiedSearch.sources.${source}`)}</h2>
      {criteria.scope === 'all' && <Link className="text-sm font-semibold text-primary underline" to={href()}>{t('unifiedSearch.viewAll')}</Link>}
    </header>
    {query.isPending ? <p role="status">{t('unifiedSearch.loading')}</p> : query.isError ? <div role="alert" className="space-y-3">
      <p>{t('unifiedSearch.error')}</p><Button variant="outline" onClick={() => void query.refetch()}>{t('unifiedSearch.retry')}</Button>
    </div> : <>
      <p className="text-sm text-muted-foreground" role="status">{t('unifiedSearch.count', { total: count(query.data.totalCount) })}</p>
      {query.data.items.length === 0 ? <p>{t('unifiedSearch.empty')}</p> : <div className="grid gap-4 md:grid-cols-2">
        {query.data.items.map(item => <article key={item.id} className="min-w-0 space-y-2 rounded-lg border p-4 [overflow-wrap:anywhere]">
          <h3 className="font-bold">{item.href ? <Link to={item.href} className="underline underline-offset-4">{item.title}</Link> : item.title}</h3>
          {item.subtitle && <p className="text-xs text-muted-foreground">{item.subtitle}</p>}
          {item.summary && <p className="line-clamp-3 text-sm">{item.summary}</p>}
          {source === 'professionals' && <details className="text-sm">
            <summary className="cursor-pointer font-semibold text-primary">{t('unifiedSearch.profileDetails')}</summary>
            {item.biography && <p className="mt-3 whitespace-pre-wrap">{item.biography}</p>}
            {item.skills && item.skills.length > 0 && <ul className="mt-3 list-inside list-disc">{item.skills.map((skill, index) => <li key={index}>{skill}</li>)}</ul>}
            {!item.biography && !item.skills?.length && <p className="mt-3">{t('unifiedSearch.noProfileDetails')}</p>}
          </details>}
        </article>)}
      </div>}
      {criteria.scope !== 'all' && <nav className="flex flex-wrap items-center gap-3" aria-label={t('unifiedSearch.pagination')}>
        {criteria.page > 1 ? <Button asChild variant="outline"><Link to={href(criteria.page - 1)}>{t('unifiedSearch.previous')}</Link></Button>
          : <Button disabled variant="outline">{t('unifiedSearch.previous')}</Button>}
        <span className="text-sm">{t('unifiedSearch.page', { page: count(criteria.page) })}</span>
        {criteria.page < 10000 && criteria.page * query.data.pageSize < query.data.totalCount
          ? <Button asChild variant="outline"><Link to={href(criteria.page + 1)}>{t('unifiedSearch.next')}</Link></Button>
          : <Button disabled variant="outline">{t('unifiedSearch.next')}</Button>}
      </nav>}
    </>}
  </section>
}
