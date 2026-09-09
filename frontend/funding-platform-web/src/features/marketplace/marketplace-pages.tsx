import { formatDateValue, formatMoneyValue } from '@/i18n/formats'
import { keepPreviousData, useQuery } from '@tanstack/react-query'
import {
  ArrowLeft,
  Building2,
  CalendarDays,
  ChevronLeft,
  ChevronRight,
  CircleAlert,
  ExternalLink,
  ListFilter,
  LoaderCircle,
  MapPin,
  Search,
  Target,
  WalletCards,
} from 'lucide-react'
import { useCallback, useEffect, useMemo, useState } from 'react'
import { Link, useParams, useSearchParams } from 'react-router-dom'

import { useTranslation } from 'react-i18next'
import { catalogName, catalogLanguage } from '@/i18n/catalog-labels'
import i18n from '@/i18n'
import { workspaceLocale } from '@/i18n/workspace-messages'
import { discoveryErrorMessage } from '@/i18n/discovery-feedback'
import { Button } from '@/components/ui/button'
import { Card, CardContent, CardHeader, CardTitle } from '@/components/ui/card'
import {
  marketplaceApi,
  marketplaceSortValues,
  type MarketplaceProjectItem,
  type MarketplaceProjectListResponse,
  type MarketplaceSort,
} from '@/features/marketplace/marketplace-api'
import { PublicProjectView } from '@/features/projects/project-publication-pages'

const projectStatusKeys = [
  'projects.statusIdea', 'projects.statusDesign', 'projects.statusSeeking',
  'projects.statusPartial', 'projects.statusFunded', 'projects.statusRunning', 'projects.statusFinished',
] as const
const defaultPageSize = 12
const selectClass = 'h-10 w-full rounded-lg border bg-background px-3 text-sm'

function parsePositiveInteger(value: string | null, fallback: number) {
  const parsed = Number(value)
  return Number.isSafeInteger(parsed) && parsed > 0 ? parsed : fallback
}

function parseOptionalId(value: string | null) {
  if (!value) return undefined
  const parsed = Number(value)
  return Number.isSafeInteger(parsed) && parsed > 0 ? parsed : undefined
}

function parseOptionalStatus(value: string | null) {
  if (!value) return undefined
  const parsed = Number(value)
  return Number.isSafeInteger(parsed) && parsed >= 0 && parsed <= 6 ? parsed : undefined
}

function parseSort(value: string | null): MarketplaceSort {
  return marketplaceSortValues.includes(value as MarketplaceSort)
    ? value as MarketplaceSort
    : 'newest'
}

function parsePageSize(value: string | null) {
  const parsed = Number(value)
  return [12, 24, 48].includes(parsed) ? parsed : defaultPageSize
}

function errorMessage(error: unknown) {
  return discoveryErrorMessage(error, 'marketplace.loadHelp')
}

function formatDate(value: string | null) {
  if (!value) return null
  const dateOnly = /^(\d{4})-(\d{2})-(\d{2})$/.exec(value)
  const date = dateOnly
    ? new Date(Number(dateOnly[1]), Number(dateOnly[2]) - 1, Number(dateOnly[3]), 12)
    : new Date(value)
  if (Number.isNaN(date.getTime())) return null
  return formatDateValue(value, { dateStyle: 'medium' })
}

function formatMoney(value: number | null, currency: string | null) {
  return formatMoneyValue(value, currency, i18n.t('marketplace.noAmount'))
}

function MarketplaceProjectCard({ project }: { project: MarketplaceProjectItem }) {
  const { t } = useTranslation()
  return (
    <Card className="flex h-full flex-col overflow-hidden">
      <CardHeader className="space-y-3">
        <div className="flex flex-wrap items-start justify-between gap-2">
          <Link
            className="inline-flex items-center gap-1 text-xs font-bold uppercase tracking-[0.12em] text-primary hover:underline"
            to={`/marketplace/organizations/${project.organization.publicId}`}
          >
            <Building2 className="size-3.5" /> {project.organization.name}
          </Link>
          <span className="rounded-full bg-accent px-2.5 py-1 text-xs font-semibold text-accent-foreground">
            {t(projectStatusKeys[project.status] ?? 'projects.active')}
          </span>
        </div>
        <CardTitle className="text-xl leading-7">
          <Link className="hover:text-primary hover:underline" to={`/marketplace/projects/${project.slug}`}>
            {project.title}
          </Link>
        </CardTitle>
      </CardHeader>
      <CardContent className="flex flex-1 flex-col gap-5">
        <p className="line-clamp-3 text-sm leading-6 text-muted-foreground">
          {project.summary ?? i18n.t('marketplace.noSummary')}
        </p>
        <dl className="mt-auto grid gap-2 border-t pt-4 text-sm">
          <div className="flex items-center justify-between gap-3">
            <dt className="text-muted-foreground">{t('marketplace.gap')}</dt>
            <dd className="font-bold text-primary">{formatMoney(project.fundingGap, project.currency)}</dd>
          </div>
          {(project.startDate || project.endDate) && (
            <div className="flex items-center justify-between gap-3">
              <dt className="text-muted-foreground">{t('marketplace.period')}</dt>
              <dd className="text-right font-medium">{formatDate(project.startDate) ?? i18n.t('marketplace.noStart')} — {formatDate(project.endDate) ?? i18n.t('marketplace.noEnd')}</dd>
            </div>
          )}
        </dl>
        <Button asChild variant="outline">
          <Link to={`/marketplace/projects/${project.slug}`}>{t('marketplace.viewProject')}</Link>
        </Button>
      </CardContent>
    </Card>
  )
}

function MarketplacePagination({
  result,
  page,
  disabled,
  onPage,
}: {
  result: MarketplaceProjectListResponse
  page: number
  disabled: boolean
  onPage: (page: number) => void
}) {
  const { t } = useTranslation()
  const lastPage = Math.max(1, Math.ceil(result.totalCount / result.pageSize))
  if (lastPage <= 1) return null
  return (
    <nav aria-label={t('marketplace.pagination')} className="flex flex-wrap items-center justify-between gap-3 rounded-xl border bg-card p-3 sm:justify-end">
      <Button disabled={page <= 1 || disabled} onClick={() => onPage(page - 1)} variant="outline">
        <ChevronLeft className="size-4" />{t('marketplace.previous')}</Button>
      <p className="text-sm text-muted-foreground">{t('marketplace.page', { page: result.pageNumber, total: lastPage })}</p>
      <Button disabled={page >= lastPage || disabled} onClick={() => onPage(page + 1)} variant="outline">{t('marketplace.next')}<ChevronRight className="size-4" />
      </Button>
    </nav>
  )
}

export function MarketplacePage() {
  const { t } = useTranslation()
  const [searchParams, setSearchParams] = useSearchParams()
  const urlQuery = searchParams.get('q') ?? ''
  const [draftQuery, setDraftQuery] = useState(urlQuery)
  const page = parsePositiveInteger(searchParams.get('page'), 1)
  const pageSize = parsePageSize(searchParams.get('pageSize'))
  const countryId = parseOptionalId(searchParams.get('countryId'))
  const categoryId = parseOptionalId(searchParams.get('categoryId'))
  const projectTypeId = parseOptionalId(searchParams.get('projectTypeId'))
  const projectStatus = parseOptionalStatus(searchParams.get('status'))
  const rawCurrency = searchParams.get('currency')?.trim().toUpperCase()
  const currency = rawCurrency && /^[A-Z]{3}$/.test(rawCurrency) ? rawCurrency : undefined
  const requestedSort = parseSort(searchParams.get('sort'))
  const sort = requestedSort === 'funding-gap-desc' && !currency ? 'newest' : requestedSort

  const replaceParameter = useCallback((key: string, value?: string, resetPage = true) => {
    setSearchParams((current) => {
      const next = new URLSearchParams(current)
      if (value?.trim()) next.set(key, value.trim())
      else next.delete(key)
      if (resetPage) next.delete('page')
      return next
    }, { replace: true })
  }, [setSearchParams])

  useEffect(() => {
    setDraftQuery(urlQuery)
  }, [urlQuery])

  useEffect(() => {
    if (draftQuery.trim() === urlQuery.trim()) return
    const timer = window.setTimeout(() => replaceParameter('q', draftQuery), 350)
    return () => window.clearTimeout(timer)
  }, [draftQuery, replaceParameter, urlQuery])

  const criteria = useMemo(() => ({
    query: urlQuery,
    countryIds: countryId ? [countryId] : [],
    categoryIds: categoryId ? [categoryId] : [],
    projectTypeIds: projectTypeId ? [projectTypeId] : [],
    projectStatus,
    currency,
    sort,
    page,
    pageSize,
  }), [urlQuery, countryId, categoryId, projectTypeId, projectStatus, currency, sort, page, pageSize])

  const projects = useQuery({
    queryKey: ['marketplace', 'projects', criteria],
    queryFn: ({ signal }) => marketplaceApi.search(criteria, signal),
    placeholderData: keepPreviousData,
  })
  const catalogs = useQuery({
    queryKey: ['marketplace', 'catalogs'],
    queryFn: ({ signal }) => marketplaceApi.catalogs(signal),
    staleTime: 60 * 60 * 1000,
    retry: false,
  })

  const hasFilters = Boolean(urlQuery || countryId || categoryId || projectTypeId || projectStatus !== undefined || currency)
  const clearFilters = () => {
    setDraftQuery('')
    setSearchParams({}, { replace: true })
  }
  const visibleProjects = projects.data?.items.filter((item) => (
    !('publicationStatus' in item) || item.publicationStatus === 2
  )) ?? []

  return (
    <div className="mx-auto max-w-7xl space-y-7 px-4 py-10 sm:px-6 sm:py-14">
      <header className="rounded-2xl border bg-card p-6 sm:p-8">
        <p className="text-sm font-bold uppercase tracking-[0.16em] text-primary">{t('marketplace.eyebrow')}</p>
        <h1 className="mt-2 text-3xl font-bold tracking-tight sm:text-4xl">{t('marketplace.title')}</h1>
        <Link className="mt-3 inline-block text-primary underline" to="/marketplace/map">{t('marketplace.map')}</Link>
        <p className="mt-3 max-w-3xl leading-7 text-muted-foreground">{t('marketplace.description')}</p>
        <label className="relative mt-6 block max-w-3xl" htmlFor="marketplace-search">
          <Search className="pointer-events-none absolute left-3 top-3 size-4 text-muted-foreground" />
          <span className="sr-only">{t('marketplace.search')}</span>
          <input
            className="h-10 w-full rounded-lg border bg-background pl-10 pr-3 text-sm"
            id="marketplace-search"
            onChange={(event) => setDraftQuery(event.target.value)}
            placeholder={t('marketplace.searchPlaceholder')}
            type="search"
            value={draftQuery}
          />
        </label>
      </header>

      <section aria-label={t('marketplace.filters')} className="grid gap-3 rounded-xl border bg-card p-4 sm:grid-cols-2 lg:grid-cols-3 xl:grid-cols-6">
        <label className="grid gap-1 text-xs font-semibold">{t('marketplace.country')}<select className={selectClass} onChange={(event) => replaceParameter('countryId', event.target.value)} value={countryId ?? ''}>
            <option value="">{t('marketplace.all')}</option>
            {catalogs.data?.countries.map((item) => <option lang={catalogLanguage('countries', item)} key={item.id} value={item.id}>{catalogName('countries', item)}</option>)}
          </select>
        </label>
        <label className="grid gap-1 text-xs font-semibold">{t('marketplace.category')}<select className={selectClass} onChange={(event) => replaceParameter('categoryId', event.target.value)} value={categoryId ?? ''}>
            <option value="">{t('marketplace.allFeminine')}</option>
            {catalogs.data?.fundingCategories.map((item) => <option lang={catalogLanguage('fundingCategories', item)} key={item.id} value={item.id}>{catalogName('fundingCategories', item)}</option>)}
          </select>
        </label>
        <label className="grid gap-1 text-xs font-semibold">{t('marketplace.projectType')}<select className={selectClass} onChange={(event) => replaceParameter('projectTypeId', event.target.value)} value={projectTypeId ?? ''}>
            <option value="">{t('marketplace.all')}</option>
            {catalogs.data?.projectTypes.map((item) => <option lang={catalogLanguage('projectTypes', item)} key={item.id} value={item.id}>{catalogName('projectTypes', item)}</option>)}
          </select>
        </label>
        <label className="grid gap-1 text-xs font-semibold">{t('marketplace.status')}<select className={selectClass} onChange={(event) => replaceParameter('status', event.target.value)} value={projectStatus ?? ''}>
            <option value="">{t('marketplace.all')}</option>
            {projectStatusKeys.map((key, value) => <option key={key} value={value}>{t(key)}</option>)}
          </select>
        </label>
        <label className="grid gap-1 text-xs font-semibold">{t('marketplace.currency')}<select className={selectClass} onChange={(event) => replaceParameter('currency', event.target.value)} value={currency ?? ''}>
            <option value="">{t('marketplace.allFeminine')}</option>
            {catalogs.data?.currencies.map((item) => <option lang={catalogLanguage('currencies', item)} key={item.code} value={item.code}>{item.code} · {catalogName('currencies', item)}</option>)}
          </select>
        </label>
        <label className="grid gap-1 text-xs font-semibold">{t('marketplace.sort')}<select className={selectClass} onChange={(event) => replaceParameter('sort', event.target.value)} value={sort}>
            <option value="newest">{t('marketplace.newest')}</option>
            <option value="title">{t('marketplace.sortTitle')}</option>
            <option disabled={!currency} value="funding-gap-desc">{t('marketplace.sortGap')}</option>
          </select>
        </label>
      </section>

      <div className="flex flex-wrap items-center justify-between gap-3">
        <p aria-live="polite" className="text-sm text-muted-foreground">
          {projects.data ? <><strong className="text-foreground">{projects.data.totalCount.toLocaleString(workspaceLocale())}</strong> {t('marketplace.published', { count: projects.data.totalCount })}</> : i18n.t('marketplace.preparing')}
          {projects.isFetching && <span> · {t('marketplace.refreshing')}</span>}
        </p>
        {hasFilters && <Button onClick={clearFilters} variant="ghost">{t('marketplace.clear')}</Button>}
      </div>

      {projects.isPending && <Card><CardContent className="flex items-center gap-3 p-8" role="status"><LoaderCircle className="size-5 animate-spin" />{t('marketplace.loading')}</CardContent></Card>}
      {projects.isError && <Card className="border-destructive/40"><CardContent className="space-y-4 p-8" role="alert"><CircleAlert className="size-8 text-destructive" /><h2 className="text-xl font-bold">{t('marketplace.loadFailed')}</h2><p className="text-sm text-muted-foreground">{errorMessage(projects.error)}</p><Button onClick={() => void projects.refetch()} variant="outline">{t('marketplace.retry')}</Button></CardContent></Card>}
      {projects.data && visibleProjects.length === 0 && <Card><CardContent className="space-y-3 p-10 text-center"><ListFilter className="mx-auto size-9 text-muted-foreground" /><h2 className="text-xl font-bold">{t('marketplace.emptyTitle')}</h2><p className="text-sm text-muted-foreground">{t('marketplace.emptyHelp')}</p>{hasFilters && <Button onClick={clearFilters} variant="outline">{t('marketplace.clear')}</Button>}</CardContent></Card>}
      {visibleProjects.length > 0 && <div className="grid gap-5 md:grid-cols-2 xl:grid-cols-3">{visibleProjects.map((project) => <MarketplaceProjectCard key={project.publicId} project={project} />)}</div>}
      {projects.data && <MarketplacePagination disabled={projects.isFetching} onPage={(value) => replaceParameter('page', String(value), false)} page={page} result={projects.data} />}
    </div>
  )
}

export function MarketplaceProjectDetailPage() {
  const { slug = '' } = useParams()
  const project = useQuery({
    queryKey: ['marketplace', 'project', slug],
    queryFn: ({ signal }) => marketplaceApi.getProject(slug, signal),
    enabled: Boolean(slug),
    retry: false,
  })
  return <PublicProjectView backTo="/marketplace" project={project} />
}

export function MarketplaceOrganizationPage() {
  const { t } = useTranslation()
  const { organizationId = '' } = useParams()
  const organization = useQuery({
    queryKey: ['marketplace', 'organization', organizationId],
    queryFn: ({ signal }) => marketplaceApi.getOrganization(organizationId, signal),
    enabled: Boolean(organizationId),
    retry: false,
  })

  if (organization.isPending) return <div className="mx-auto grid min-h-[60vh] max-w-6xl place-items-center px-4"><p className="flex items-center gap-2" role="status"><LoaderCircle className="size-5 animate-spin" />{t('marketplace.organizationLoading')}</p></div>
  if (organization.isError || !organization.data) return <section className="mx-auto max-w-3xl px-4 py-20 text-center"><CircleAlert className="mx-auto size-10 text-muted-foreground" /><h1 className="mt-4 text-3xl font-bold">{t('marketplace.organizationUnavailable')}</h1><p className="mt-3 text-muted-foreground">{t('marketplace.organizationUnavailableHelp')}</p><Button className="mt-6" asChild variant="outline"><Link to="/marketplace"><ArrowLeft className="size-4" />{t('marketplace.back')}</Link></Button></section>

  const data = organization.data
  const website = data.websiteUrl && /^https?:\/\//i.test(data.websiteUrl) ? data.websiteUrl : null
  const projects = data.projects.filter((item) => !('publicationStatus' in item) || item.publicationStatus === 2)
  return (
    <div className="mx-auto max-w-6xl space-y-8 px-4 py-10 sm:px-6 sm:py-14">
      <Button asChild variant="ghost"><Link to="/marketplace"><ArrowLeft className="size-4" />{t('marketplace.back')}</Link></Button>
      <header className="rounded-2xl border bg-card p-6 sm:p-9">
        <div className="flex flex-wrap items-start justify-between gap-5">
          <div className="max-w-3xl">
            <p className="text-sm font-bold uppercase tracking-[0.16em] text-primary">{t('marketplace.organizationProfile')}</p>
            <h1 className="mt-2 text-3xl font-bold tracking-tight sm:text-4xl">{data.name}</h1>
            <p className="mt-4 whitespace-pre-line leading-7 text-muted-foreground">{data.description ?? i18n.t('marketplace.organizationNoDescription')}</p>
          </div>
          <div className="grid gap-2 text-sm">
            {data.homeCountry && <p className="flex items-center gap-2"><MapPin className="size-4 text-primary" /><span lang={catalogLanguage('countries', data.homeCountry)}>{catalogName('countries', data.homeCountry)}</span></p>}
            {data.establishedYear && <p className="flex items-center gap-2"><CalendarDays className="size-4 text-primary" />{t('marketplace.since', { year: data.establishedYear })}</p>}
            {data.organizationType && <p className="flex items-center gap-2"><Building2 className="size-4 text-primary" /><span lang={catalogLanguage('organizationTypes', data.organizationType)}>{catalogName('organizationTypes', data.organizationType)}</span></p>}
            {website && <Button asChild size="sm" variant="outline"><a href={website} rel="noopener noreferrer" target="_blank">{t('marketplace.officialSite')}<ExternalLink className="size-4" /></a></Button>}
          </div>
        </div>
        {(data.categories.length > 0 || data.projectTypes.length > 0) && <div className="mt-6 flex flex-wrap gap-2 border-t pt-5">{[{ catalog: 'fundingCategories' as const, values: data.categories }, { catalog: 'projectTypes' as const, values: data.projectTypes }].flatMap(({ catalog, values }) => values.map(item => <span className="rounded-full border px-3 py-1.5 text-xs" key={`${catalog}-${item.id}`} lang={catalogLanguage(catalog, item)}>{catalogName(catalog, item)}</span>))}</div>}
      </header>

      <section className="space-y-5">
        <div className="flex flex-wrap items-end justify-between gap-3"><div><p className="text-sm font-bold uppercase tracking-[0.14em] text-primary">{t('marketplace.publicInitiatives')}</p><h2 className="mt-1 text-2xl font-bold">{t('marketplace.organizationProjects', { name: data.name })}</h2></div><span className="text-sm text-muted-foreground">{t('marketplace.organizationPublished', { count: projects.length })}</span></div>
        {projects.length === 0
          ? <Card><CardContent className="p-10 text-center"><Target className="mx-auto size-9 text-muted-foreground" /><h3 className="mt-3 text-lg font-bold">{t('marketplace.noProjects')}</h3><p className="mt-2 text-sm text-muted-foreground">{t('marketplace.noProjectsHelp')}</p></CardContent></Card>
          : <div className="grid gap-5 md:grid-cols-2 xl:grid-cols-3">{projects.map((project) => <MarketplaceProjectCard key={project.publicId} project={project} />)}</div>}
      </section>

      <Card><CardContent className="flex items-start gap-3 p-5 text-sm text-muted-foreground"><WalletCards className="mt-0.5 size-5 shrink-0 text-primary" /><p>{t('marketplace.organizationDisclaimer')}</p></CardContent></Card>
    </div>
  )
}
