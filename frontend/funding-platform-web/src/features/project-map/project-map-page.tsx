import { useState } from 'react'
import { useQuery } from '@tanstack/react-query'
import { Link, useSearchParams } from 'react-router-dom'
import { useTranslation } from 'react-i18next'
import { apiClient } from '@/api/http-client'
import { Button } from '@/components/ui/button'
import { catalogName } from '@/i18n/catalog-labels'
import { formatMoneyValue, formatNumber } from '@/i18n/formats'
import type { MarketplaceCatalogs } from '@/features/marketplace/marketplace-api'
import { projectMapApi, mapQuery } from './project-map-api'
import { ProjectMapView } from './project-map-view'

export function ProjectMapPage() {
  const { t } = useTranslation()
  const [search, setSearch] = useSearchParams()
  const query = mapQuery(search)
  const [selected, setSelected] = useState<string[]>([])
  const projects = useQuery({ queryKey: ['project-map', query.toString()], queryFn: ({ signal }) => projectMapApi.search(query, signal) })
  const catalogs = useQuery({ queryKey: ['marketplace-catalogs'], queryFn: ({ signal }) => apiClient.get<MarketplaceCatalogs>('marketplace/catalogs', { signal }) })
  const changePage = (page: number) => { const next = new URLSearchParams(query); next.set('page', String(page)); setSearch(next); setSelected([]) }
  const items = projects.data?.items ?? []
  const listed = selected.length ? items.filter(p => selected.includes(p.publicId)) : items
  const stages = ['stageIdea', 'stagePilot', 'stageImplementation', 'stageScaling', 'stageConsolidation', 'stageEvaluation'] as const
  const statuses = ['statusIdea', 'statusDesign', 'statusSeeking', 'statusPartial', 'statusFunded', 'statusRunning', 'statusFinished'] as const
  return <div className="mx-auto max-w-7xl space-y-6 px-4 py-10">
    <header><Link className="text-primary underline" to="/marketplace">{t('projectMap.catalog')}</Link><h1 className="mt-3 text-3xl font-bold">{t('projectMap.title')}</h1><p className="mt-3 text-muted-foreground">{t('projectMap.help')}</p></header>
    <form key={query.toString()} className="grid gap-3 rounded-xl border bg-card p-4 sm:grid-cols-2 lg:grid-cols-3" onSubmit={event => {
      event.preventDefault(); const form = new FormData(event.currentTarget); const next = new URLSearchParams()
      for (const [key, value] of form) if (String(value).trim()) next.set(key, String(value))
      setSearch(mapQuery(next)); setSelected([])
    }}>
      <label className="grid gap-1 text-sm font-semibold">{t('projectMap.search')}<input name="q" maxLength={200} className="h-10 min-w-0 rounded-lg border bg-background px-3" defaultValue={query.get('q') ?? ''} /></label>
      {(['countryId', 'categoryId', 'sustainableDevelopmentGoalId'] as const).map(key => <label key={key} className="grid gap-1 text-sm font-semibold">{t(`projectMap.${key}`)}<select name={key} defaultValue={query.get(key) ?? ''} className="h-10 min-w-0 max-w-full rounded-lg border bg-background px-3"><option value="">{t('projectMap.all')}</option>{(key === 'countryId' ? catalogs.data?.countries : key === 'categoryId' ? catalogs.data?.fundingCategories : catalogs.data?.sustainableDevelopmentGoals)?.map(item => <option key={item.id} value={item.id}>{catalogName(key === 'countryId' ? 'countries' : key === 'categoryId' ? 'fundingCategories' : 'sustainableDevelopmentGoals', item)}</option>)}</select></label>)}
      {(['projectStage', 'projectStatus'] as const).map(key => <label key={key} className="grid gap-1 text-sm font-semibold">{t(`projectMap.${key}`)}<select className="h-10 min-w-0 rounded-lg border bg-background px-3" name={key} defaultValue={query.get(key) ?? ''}><option value="">{t('projectMap.all')}</option>{(key === 'projectStage' ? stages : statuses).map((label, value) => <option key={label} value={value}>{t(`projects.${label}`)}</option>)}</select></label>)}
      <Button type="submit">{t('projectMap.apply')}</Button><Button type="button" variant="outline" onClick={() => { setSearch({}); setSelected([]) }}>{t('projectMap.clear')}</Button>
    </form>
    {catalogs.isError && <p role="alert">{t('projectMap.catalogError')} <Button variant="outline" onClick={() => void catalogs.refetch()}>{t('projectMap.retry')}</Button></p>}
    {projects.isPending && <p role="status">{t('projectMap.loading')}</p>}
    {projects.isError && <div role="alert">{t('projectMap.error')} <Button variant="outline" onClick={() => void projects.refetch()}>{t('projectMap.retry')}</Button></div>}
    {projects.data && !projects.isError && <>
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
