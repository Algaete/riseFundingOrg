import { useState } from 'react'
import { useQuery } from '@tanstack/react-query'
import { Link, useSearchParams } from 'react-router-dom'
import { useTranslation } from 'react-i18next'
import { apiClient } from '@/api/http-client'
import { Button } from '@/components/ui/button'
import { formatMoneyValue, formatNumber } from '@/i18n/formats'
import type { MarketplaceCatalogs } from '@/features/marketplace/marketplace-api'
import { projectMapApi } from './project-map-api'
import { mapReadPolicy, readMapFilters } from './map-filters'
import { MapFiltersForm } from './map-filters-form'
import { ProjectMapView } from './project-map-view'

export function ProjectMapPage() {
  const { t } = useTranslation()
  const [search, setSearch] = useSearchParams()
  const { query, valid } = readMapFilters(search)
  const [selected, setSelected] = useState<string[]>([])
  const projects = useQuery({ queryKey: ['project-map', query.toString()], queryFn: ({ signal }) => projectMapApi.search(query, signal), enabled: valid, ...mapReadPolicy })
  const catalogs = useQuery({ queryKey: ['marketplace-catalogs'], queryFn: ({ signal }) => apiClient.get<MarketplaceCatalogs>('marketplace/catalogs', { signal }), ...mapReadPolicy, staleTime: 300_000 })
  const changePage = (page: number) => { const next = new URLSearchParams(query); next.set('page', String(page)); setSearch(next); setSelected([]) }
  const items = projects.data?.items ?? []
  const listed = selected.length ? items.filter(p => selected.includes(p.publicId)) : items
  return <div className="mx-auto max-w-7xl space-y-6 px-4 py-10">
    <header><Link className="text-primary underline" to="/marketplace">{t('projectMap.catalog')}</Link><h1 className="mt-3 text-3xl font-bold">{t('projectMap.title')}</h1><p className="mt-3 text-muted-foreground">{t('projectMap.help')}</p></header>
    <MapFiltersForm key={search.toString()} search={search} catalogs={catalogs.data} apply={next => { setSearch(next); setSelected([]) }} clear={() => { setSearch({}); setSelected([]) }} />
    {!valid && <p role="alert" className="rounded-lg border border-destructive/40 p-4">{t('projectMap.invalidFilters')}</p>}
    {valid && query.has('projectIds') && <aside className="space-y-2 rounded-lg border p-4"><p>{t('projectMap.selectionNotice', { count: query.getAll('projectIds').length })}</p><Button variant="outline" onClick={() => { const next = new URLSearchParams(query); next.delete('projectIds'); next.delete('page'); setSearch(next); setSelected([]) }}>{t('projectMap.removeSelection')}</Button></aside>}
    {catalogs.isError && <p role="alert">{t('projectMap.catalogError')} <Button variant="outline" onClick={() => void catalogs.refetch()}>{t('projectMap.retry')}</Button></p>}
    {valid && projects.isPending && <p role="status">{t('projectMap.loading')}</p>}
    {valid && projects.isError && <div role="alert">{t('projectMap.error')} <Button variant="outline" onClick={() => void projects.refetch()}>{t('projectMap.retry')}</Button></div>}
    {valid && projects.data && !projects.isError && <>
      <p role="status">{t('projectMap.counts', { total: formatNumber(projects.data.totalCount), hidden: formatNumber(projects.data.withoutPublicLocationCount) })}</p>
      <p className="text-sm text-muted-foreground">{t('projectMap.pageNotice', { count: items.length, page: projects.data.page })}</p>
      <ProjectMapView key={query.toString()} points={items} select={setSelected} />
      <section className="space-y-3" aria-label={t('projectMap.results')}>
        <div className="flex flex-wrap items-center gap-3"><h2 className="text-xl font-semibold">{t('projectMap.results')}</h2>{selected.length > 0 && <Button variant="outline" onClick={() => setSelected([])}>{t('projectMap.showAll')}</Button>}</div>
        {listed.length === 0 && <p>{t('projectMap.empty')}</p>}
        <ul className="grid gap-4 sm:grid-cols-2 lg:grid-cols-3">{listed.map(point => <li key={point.publicId} className="rounded-xl border bg-card p-4"><h3 className="font-semibold">{point.title}</h3><p className="text-sm text-muted-foreground">{point.organizationName}</p><p className="mt-2 text-sm">{point.summary}</p><p className="my-3 text-sm">{t('projectMap.gap')}: {formatMoneyValue(point.fundingGap, point.currency)}</p><Link className="text-primary underline" to={`/marketplace/projects/${encodeURIComponent(point.slug)}`}>{t('projectMap.details')}</Link></li>)}</ul>
      </section>
      <nav className="flex flex-wrap gap-3" aria-label={t('projectMap.pagination')}><Button variant="outline" disabled={projects.data.page <= 1} onClick={() => changePage(projects.data.page - 1)}>{t('projectMap.previous')}</Button><span className="self-center">{t('projectMap.page', { page: projects.data.page, total: Math.max(1, Math.ceil(projects.data.totalCount / projects.data.pageSize)) })}</span><Button variant="outline" disabled={projects.data.page * projects.data.pageSize >= projects.data.totalCount || projects.data.page >= 10000} onClick={() => changePage(projects.data.page + 1)}>{t('projectMap.next')}</Button></nav>
    </>}
  </div>
}
