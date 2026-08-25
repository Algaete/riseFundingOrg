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

import { ApiError } from '@/api/http-client'
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

const projectStatusNames = [
  'Idea',
  'Diseño',
  'Buscando financiamiento',
  'Financiado parcialmente',
  'Financiado',
  'En ejecución',
  'Completado',
]
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

function errorMessage(error: unknown, fallback: string) {
  if (!(error instanceof ApiError)) return fallback
  return Object.values(error.problem.errors ?? {}).flat()[0]
    ?? error.problem.detail
    ?? error.problem.title
}

function formatDate(value: string | null) {
  if (!value) return null
  const dateOnly = /^(\d{4})-(\d{2})-(\d{2})$/.exec(value)
  const date = dateOnly
    ? new Date(Number(dateOnly[1]), Number(dateOnly[2]) - 1, Number(dateOnly[3]), 12)
    : new Date(value)
  if (Number.isNaN(date.getTime())) return null
  return new Intl.DateTimeFormat('es-CL', { dateStyle: 'medium' }).format(date)
}

function formatMoney(value: number | null, currency: string | null) {
  if (value === null || !currency) return 'Monto no informado'
  try {
    return new Intl.NumberFormat('es-CL', {
      style: 'currency',
      currency,
      maximumFractionDigits: currency === 'CLP' ? 0 : 2,
    }).format(value)
  } catch {
    return `${value.toLocaleString('es-CL')} ${currency}`
  }
}

function MarketplaceProjectCard({ project }: { project: MarketplaceProjectItem }) {
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
            {projectStatusNames[project.status] ?? 'Proyecto activo'}
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
          {project.summary ?? 'La organización no publicó un resumen.'}
        </p>
        <dl className="mt-auto grid gap-2 border-t pt-4 text-sm">
          <div className="flex items-center justify-between gap-3">
            <dt className="text-muted-foreground">Brecha declarada</dt>
            <dd className="font-bold text-primary">{formatMoney(project.fundingGap, project.currency)}</dd>
          </div>
          {(project.startDate || project.endDate) && (
            <div className="flex items-center justify-between gap-3">
              <dt className="text-muted-foreground">Periodo</dt>
              <dd className="text-right font-medium">{formatDate(project.startDate) ?? 'Sin inicio'} — {formatDate(project.endDate) ?? 'Sin término'}</dd>
            </div>
          )}
        </dl>
        <Button asChild variant="outline">
          <Link to={`/marketplace/projects/${project.slug}`}>Ver proyecto</Link>
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
  const lastPage = Math.max(1, Math.ceil(result.totalCount / result.pageSize))
  if (lastPage <= 1) return null
  return (
    <nav aria-label="Paginación del marketplace" className="flex flex-wrap items-center justify-between gap-3 rounded-xl border bg-card p-3 sm:justify-end">
      <Button disabled={page <= 1 || disabled} onClick={() => onPage(page - 1)} variant="outline">
        <ChevronLeft className="size-4" /> Anterior
      </Button>
      <p className="text-sm text-muted-foreground">Página <strong className="text-foreground">{result.pageNumber}</strong> de {lastPage}</p>
      <Button disabled={page >= lastPage || disabled} onClick={() => onPage(page + 1)} variant="outline">
        Siguiente <ChevronRight className="size-4" />
      </Button>
    </nav>
  )
}

export function MarketplacePage() {
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
        <p className="text-sm font-bold uppercase tracking-[0.16em] text-primary">Proyectos con propósito</p>
        <h1 className="mt-2 text-3xl font-bold tracking-tight sm:text-4xl">Marketplace de proyectos</h1>
        <p className="mt-3 max-w-3xl leading-7 text-muted-foreground">
          Conoce iniciativas publicadas por organizaciones. La información es declarada por cada organización y no representa una promesa de financiamiento o elegibilidad.
        </p>
        <label className="relative mt-6 block max-w-3xl" htmlFor="marketplace-search">
          <Search className="pointer-events-none absolute left-3 top-3 size-4 text-muted-foreground" />
          <span className="sr-only">Buscar proyectos</span>
          <input
            className="h-10 w-full rounded-lg border bg-background pl-10 pr-3 text-sm"
            id="marketplace-search"
            onChange={(event) => setDraftQuery(event.target.value)}
            placeholder="Buscar por proyecto u organización"
            type="search"
            value={draftQuery}
          />
        </label>
      </header>

      <section aria-label="Filtros del marketplace" className="grid gap-3 rounded-xl border bg-card p-4 sm:grid-cols-2 lg:grid-cols-3 xl:grid-cols-6">
        <label className="grid gap-1 text-xs font-semibold">País
          <select className={selectClass} onChange={(event) => replaceParameter('countryId', event.target.value)} value={countryId ?? ''}>
            <option value="">Todos</option>
            {catalogs.data?.countries.map((item) => <option key={item.id} value={item.id}>{item.name}</option>)}
          </select>
        </label>
        <label className="grid gap-1 text-xs font-semibold">Área de impacto
          <select className={selectClass} onChange={(event) => replaceParameter('categoryId', event.target.value)} value={categoryId ?? ''}>
            <option value="">Todas</option>
            {catalogs.data?.fundingCategories.map((item) => <option key={item.id} value={item.id}>{item.name}</option>)}
          </select>
        </label>
        <label className="grid gap-1 text-xs font-semibold">Tipo de proyecto
          <select className={selectClass} onChange={(event) => replaceParameter('projectTypeId', event.target.value)} value={projectTypeId ?? ''}>
            <option value="">Todos</option>
            {catalogs.data?.projectTypes.map((item) => <option key={item.id} value={item.id}>{item.name}</option>)}
          </select>
        </label>
        <label className="grid gap-1 text-xs font-semibold">Estado
          <select className={selectClass} onChange={(event) => replaceParameter('status', event.target.value)} value={projectStatus ?? ''}>
            <option value="">Todos</option>
            {projectStatusNames.map((name, value) => <option key={name} value={value}>{name}</option>)}
          </select>
        </label>
        <label className="grid gap-1 text-xs font-semibold">Moneda
          <select className={selectClass} onChange={(event) => replaceParameter('currency', event.target.value)} value={currency ?? ''}>
            <option value="">Todas</option>
            {catalogs.data?.currencies.map((item) => <option key={item.code} value={item.code}>{item.code} · {item.name}</option>)}
          </select>
        </label>
        <label className="grid gap-1 text-xs font-semibold">Ordenar
          <select className={selectClass} onChange={(event) => replaceParameter('sort', event.target.value)} value={sort}>
            <option value="newest">Publicados recientemente</option>
            <option value="title">Título</option>
            <option disabled={!currency} value="funding-gap-desc">Mayor brecha declarada (misma moneda)</option>
          </select>
        </label>
      </section>

      <div className="flex flex-wrap items-center justify-between gap-3">
        <p aria-live="polite" className="text-sm text-muted-foreground">
          {projects.data ? <><strong className="text-foreground">{projects.data.totalCount}</strong> proyectos publicados</> : 'Preparando proyectos…'}
          {projects.isFetching && <span> · Actualizando…</span>}
        </p>
        {hasFilters && <Button onClick={clearFilters} variant="ghost">Limpiar filtros</Button>}
      </div>

      {projects.isPending && <Card><CardContent className="flex items-center gap-3 p-8" role="status"><LoaderCircle className="size-5 animate-spin" /> Cargando proyectos publicados…</CardContent></Card>}
      {projects.isError && <Card className="border-destructive/40"><CardContent className="space-y-4 p-8" role="alert"><CircleAlert className="size-8 text-destructive" /><h2 className="text-xl font-bold">No pudimos cargar el marketplace</h2><p className="text-sm text-muted-foreground">{errorMessage(projects.error, 'Comprueba la conexión e intenta nuevamente.')}</p><Button onClick={() => void projects.refetch()} variant="outline">Reintentar</Button></CardContent></Card>}
      {projects.data && visibleProjects.length === 0 && <Card><CardContent className="space-y-3 p-10 text-center"><ListFilter className="mx-auto size-9 text-muted-foreground" /><h2 className="text-xl font-bold">No encontramos proyectos</h2><p className="text-sm text-muted-foreground">Prueba con una búsqueda más amplia o limpia los filtros.</p>{hasFilters && <Button onClick={clearFilters} variant="outline">Limpiar filtros</Button>}</CardContent></Card>}
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
  const { organizationId = '' } = useParams()
  const organization = useQuery({
    queryKey: ['marketplace', 'organization', organizationId],
    queryFn: ({ signal }) => marketplaceApi.getOrganization(organizationId, signal),
    enabled: Boolean(organizationId),
    retry: false,
  })

  if (organization.isPending) return <div className="mx-auto grid min-h-[60vh] max-w-6xl place-items-center px-4"><p className="flex items-center gap-2" role="status"><LoaderCircle className="size-5 animate-spin" /> Cargando organización pública…</p></div>
  if (organization.isError || !organization.data) return <section className="mx-auto max-w-3xl px-4 py-20 text-center"><CircleAlert className="mx-auto size-10 text-muted-foreground" /><h1 className="mt-4 text-3xl font-bold">Organización no disponible</h1><p className="mt-3 text-muted-foreground">El perfil no existe o todavía no está disponible públicamente.</p><Button className="mt-6" asChild variant="outline"><Link to="/marketplace"><ArrowLeft className="size-4" />Volver al marketplace</Link></Button></section>

  const data = organization.data
  const website = data.websiteUrl && /^https?:\/\//i.test(data.websiteUrl) ? data.websiteUrl : null
  const projects = data.projects.filter((item) => !('publicationStatus' in item) || item.publicationStatus === 2)
  return (
    <div className="mx-auto max-w-6xl space-y-8 px-4 py-10 sm:px-6 sm:py-14">
      <Button asChild variant="ghost"><Link to="/marketplace"><ArrowLeft className="size-4" />Volver al marketplace</Link></Button>
      <header className="rounded-2xl border bg-card p-6 sm:p-9">
        <div className="flex flex-wrap items-start justify-between gap-5">
          <div className="max-w-3xl">
            <p className="text-sm font-bold uppercase tracking-[0.16em] text-primary">Perfil público de organización</p>
            <h1 className="mt-2 text-3xl font-bold tracking-tight sm:text-4xl">{data.name}</h1>
            <p className="mt-4 whitespace-pre-line leading-7 text-muted-foreground">{data.description ?? 'La organización todavía no publicó una descripción.'}</p>
          </div>
          <div className="grid gap-2 text-sm">
            {data.homeCountry && <p className="flex items-center gap-2"><MapPin className="size-4 text-primary" />{data.homeCountry.name}</p>}
            {data.establishedYear && <p className="flex items-center gap-2"><CalendarDays className="size-4 text-primary" />Desde {data.establishedYear}</p>}
            {data.organizationType && <p className="flex items-center gap-2"><Building2 className="size-4 text-primary" />{data.organizationType.name}</p>}
            {website && <Button asChild size="sm" variant="outline"><a href={website} rel="noopener noreferrer" target="_blank">Sitio oficial <ExternalLink className="size-4" /></a></Button>}
          </div>
        </div>
        {(data.categories.length > 0 || data.projectTypes.length > 0) && <div className="mt-6 flex flex-wrap gap-2 border-t pt-5">{[...data.categories, ...data.projectTypes].map((item) => <span className="rounded-full border px-3 py-1.5 text-xs" key={`${item.code}-${item.id}`}>{item.name}</span>)}</div>}
      </header>

      <section className="space-y-5">
        <div className="flex items-end justify-between gap-3"><div><p className="text-sm font-bold uppercase tracking-[0.14em] text-primary">Iniciativas públicas</p><h2 className="mt-1 text-2xl font-bold">Proyectos de {data.name}</h2></div><span className="text-sm text-muted-foreground">{projects.length} publicados</span></div>
        {projects.length === 0
          ? <Card><CardContent className="p-10 text-center"><Target className="mx-auto size-9 text-muted-foreground" /><h3 className="mt-3 text-lg font-bold">Sin proyectos publicados</h3><p className="mt-2 text-sm text-muted-foreground">Los borradores y proyectos en revisión nunca aparecen aquí.</p></CardContent></Card>
          : <div className="grid gap-5 md:grid-cols-2 xl:grid-cols-3">{projects.map((project) => <MarketplaceProjectCard key={project.publicId} project={project} />)}</div>}
      </section>

      <Card><CardContent className="flex items-start gap-3 p-5 text-sm text-muted-foreground"><WalletCards className="mt-0.5 size-5 shrink-0 text-primary" /><p>Los montos y antecedentes son declarados por la organización. FundingPlatform no verifica legalmente el perfil ni procesa aportes desde esta vista.</p></CardContent></Card>
    </div>
  )
}
