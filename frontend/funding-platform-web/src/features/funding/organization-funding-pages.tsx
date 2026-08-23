import {
  keepPreviousData,
  useMutation,
  useQuery,
  useQueryClient,
} from '@tanstack/react-query'
import {
  ChevronLeft,
  ChevronRight,
  Heart,
  ListFilter,
  LoaderCircle,
  Search,
  SlidersHorizontal,
  X,
} from 'lucide-react'
import {
  type FormEvent,
  useCallback,
  useEffect,
  useMemo,
  useState,
} from 'react'
import { Link, useParams, useSearchParams } from 'react-router-dom'

import { ApiError } from '@/api/http-client'
import { Button } from '@/components/ui/button'
import { Card, CardContent, CardHeader, CardTitle } from '@/components/ui/card'
import {
  FundingCard,
  FundingOpportunityDetailView,
} from '@/features/funding/funding-pages'
import type { FundingOpportunityDetail } from '@/features/funding/funding-opportunities-api'
import {
  fundingSortValues,
  organizationFundingApi,
  type FundingSort,
  type OrganizationFundingOpportunityDetail,
  type OrganizationFundingOpportunityListItem,
  type OrganizationFundingOpportunityListResponse,
} from '@/features/funding/organization-funding-api'
import {
  organizationApi,
  type CatalogOption,
  type OrganizationCatalogs,
  type OrganizationSummary,
} from '@/features/organizations/organization-api'

const defaultPageSize = 12
const selectClass = 'h-10 w-full rounded-lg border bg-background px-3 text-sm'
const inputClass = 'h-10 w-full rounded-lg border bg-background px-3 text-sm'

function parsePositiveInteger(value: string | null, fallback: number) {
  const parsed = Number(value)
  return Number.isSafeInteger(parsed) && parsed > 0 ? parsed : fallback
}

function parseOptionalNumber(value: string | null) {
  if (!value?.trim()) return undefined
  const parsed = Number(value)
  return Number.isFinite(parsed) && parsed >= 0 ? parsed : undefined
}

function parseIds(value: string | null) {
  if (!value) return []
  return [...new Set(value.split(',')
    .map((item) => Number(item))
    .filter((item) => Number.isSafeInteger(item) && item > 0))]
}

function parseSort(value: string | null, hasQuery: boolean): FundingSort {
  if (value === 'relevance' && !hasQuery) return 'closing-soon'
  return fundingSortValues.includes(value as FundingSort)
    ? value as FundingSort
    : hasQuery ? 'relevance' : 'closing-soon'
}

function firstId(value: string | null) {
  return parseIds(value)[0]?.toString() ?? ''
}

function apiErrorMessage(error: unknown, fallback: string) {
  if (!(error instanceof ApiError)) return fallback
  return Object.values(error.problem.errors ?? {}).flat()[0]
    ?? error.problem.detail
    ?? error.problem.title
}

function useOrganization() {
  const organizations = useQuery({
    queryKey: ['organizations'],
    queryFn: ({ signal }) => organizationApi.list(signal),
  })
  return {
    organizations,
    organization: organizations.data?.[0],
  }
}

function OrganizationRequired() {
  return (
    <Card>
      <CardContent className="space-y-4 p-8 text-center">
        <h1 className="text-2xl font-bold">Primero crea tu organización</h1>
        <p className="text-sm text-muted-foreground">
          Los favoritos y filtros de trabajo se guardan dentro del espacio de tu organización.
        </p>
        <Button asChild><Link to="/onboarding">Crear organización</Link></Button>
      </CardContent>
    </Card>
  )
}

function PageLoading({ label }: { label: string }) {
  return (
    <Card>
      <CardContent className="flex items-center gap-3 p-8 text-muted-foreground" role="status">
        <LoaderCircle className="size-5 animate-spin" /> {label}
      </CardContent>
    </Card>
  )
}

type CachedFundingValue =
  | OrganizationFundingOpportunityListResponse
  | OrganizationFundingOpportunityDetail
  | undefined

function updateFavoriteInCache(
  value: CachedFundingValue,
  opportunityId: string,
  isFavorite: boolean,
): CachedFundingValue {
  if (!value) return value
  if ('items' in value) {
    return {
      ...value,
      items: value.items.map((item) => item.publicId === opportunityId
        ? { ...item, isFavorite }
        : item),
    }
  }
  return value.publicId === opportunityId ? { ...value, isFavorite } : value
}

function FavoriteButton({
  organizationId,
  opportunity,
  fullWidth = false,
}: {
  organizationId: string
  opportunity: OrganizationFundingOpportunityListItem
  fullWidth?: boolean
}) {
  const queryClient = useQueryClient()
  const [feedback, setFeedback] = useState('')
  const nextFavoriteState = !opportunity.isFavorite
  const mutation = useMutation({
    mutationFn: () => nextFavoriteState
      ? organizationFundingApi.addFavorite(organizationId, opportunity.publicId)
      : organizationFundingApi.removeFavorite(organizationId, opportunity.publicId),
    onMutate: async () => {
      setFeedback('')
      await queryClient.cancelQueries({ queryKey: ['organization-funding', organizationId] })
      const previous = queryClient.getQueriesData<CachedFundingValue>({
        queryKey: ['organization-funding', organizationId],
      })
      queryClient.setQueriesData<CachedFundingValue>(
        { queryKey: ['organization-funding', organizationId] },
        (value) => updateFavoriteInCache(value, opportunity.publicId, nextFavoriteState),
      )
      return { previous }
    },
    onError: (_error, _variables, context) => {
      context?.previous.forEach(([queryKey, value]) => queryClient.setQueryData(queryKey, value))
      setFeedback('No pudimos actualizar el favorito. Intenta nuevamente.')
    },
    onSuccess: () => {
      setFeedback(nextFavoriteState ? 'Oportunidad guardada en favoritos.' : 'Oportunidad eliminada de favoritos.')
    },
    onSettled: async () => {
      await queryClient.invalidateQueries({ queryKey: ['organization-funding', organizationId] })
    },
  })

  const label = opportunity.isFavorite ? 'Quitar de favoritos' : 'Guardar en favoritos'
  return (
    <div className={fullWidth ? 'grid gap-2' : 'grid gap-1'}>
      <Button
        aria-pressed={opportunity.isFavorite}
        className={fullWidth ? 'w-full' : undefined}
        disabled={mutation.isPending}
        onClick={() => mutation.mutate()}
        size="sm"
        type="button"
        variant={opportunity.isFavorite ? 'default' : 'outline'}
      >
        {mutation.isPending
          ? <LoaderCircle className="size-4 animate-spin" />
          : <Heart className={`size-4 ${opportunity.isFavorite ? 'fill-current' : ''}`} />}
        {label}
      </Button>
      {feedback && (
        <p
          className={`${fullWidth ? 'text-sm' : 'sr-only'} ${mutation.isError ? 'text-destructive' : 'text-muted-foreground'}`}
          role={mutation.isError ? 'alert' : 'status'}
        >
          {feedback}
        </p>
      )}
    </div>
  )
}

function CatalogSelect({
  id,
  label,
  description,
  items,
  value,
  onChange,
}: {
  id: string
  label: string
  description?: string
  items: CatalogOption<number>[]
  value: string
  onChange: (value: string) => void
}) {
  return (
    <label className="grid gap-1.5 text-sm font-semibold" htmlFor={id}>
      {label}
      <select className={selectClass} id={id} onChange={(event) => onChange(event.target.value)} value={value}>
        <option value="">Todos</option>
        {items.map((item) => <option key={item.id} value={item.id}>{item.name}</option>)}
      </select>
      {description && <span className="text-xs font-normal text-muted-foreground">{description}</span>}
    </label>
  )
}

function ResultsPagination({
  page,
  response,
  disabled,
  setPage,
}: {
  page: number
  response: OrganizationFundingOpportunityListResponse
  disabled: boolean
  setPage: (page: number) => void
}) {
  const lastPage = Math.max(1, Math.ceil(response.totalCount / response.pageSize))
  if (lastPage <= 1) return null
  return (
    <nav aria-label="Paginación de oportunidades" className="flex flex-wrap items-center justify-between gap-3 rounded-xl border bg-card p-3 sm:justify-end">
      <Button disabled={page <= 1 || disabled} onClick={() => setPage(page - 1)} type="button" variant="outline">
        <ChevronLeft className="size-4" /> Anterior
      </Button>
      <p className="text-sm text-muted-foreground">
        Página <strong className="text-foreground">{response.pageNumber}</strong> de {lastPage}
      </p>
      <Button disabled={page >= lastPage || disabled} onClick={() => setPage(page + 1)} type="button" variant="outline">
        Siguiente <ChevronRight className="size-4" />
      </Button>
    </nav>
  )
}

function FundingGrid({
  organization,
  items,
}: {
  organization: OrganizationSummary
  items: OrganizationFundingOpportunityListItem[]
}) {
  return (
    <div className="grid gap-5 md:grid-cols-2 xl:grid-cols-3">
      {items.map((opportunity) => (
        <FundingCard
          action={<FavoriteButton organizationId={organization.publicId} opportunity={opportunity} />}
          detailHref={`/opportunities/${opportunity.slug}`}
          key={opportunity.publicId}
          opportunity={opportunity}
        />
      ))}
    </div>
  )
}

function toDisplayDetail(item: OrganizationFundingOpportunityDetail): FundingOpportunityDetail {
  return {
    ...item,
    externalId: item.externalId
      ?? item.sources.find((source) => source.isPrimary && source.isActive)?.externalId
      ?? null,
  }
}

function catalogNames(ids: readonly number[], items: readonly CatalogOption<number>[] = []) {
  const names = new Map(items.map((item) => [item.id, item.name]))
  return [...new Set(ids.map((id) => names.get(id)).filter((name): name is string => Boolean(name)))]
}

function DetailChips({ label, values }: { label: string; values: readonly string[] }) {
  if (values.length === 0) return null
  return (
    <div>
      <h3 className="text-sm font-bold">{label}</h3>
      <ul className="mt-2 flex flex-wrap gap-2">
        {values.map((value) => (
          <li className="rounded-full border bg-background px-3 py-1.5 text-xs" key={value}>{value}</li>
        ))}
      </ul>
    </div>
  )
}

function yesNoUnknown(value: boolean | null) {
  return value === null ? 'No informado' : value ? 'Sí' : 'No'
}

function formatUtcDateTime(value: string | null) {
  if (!value) return null
  const date = new Date(value)
  if (Number.isNaN(date.getTime())) return null
  return `${new Intl.DateTimeFormat('es-CL', {
    dateStyle: 'medium',
    timeStyle: 'short',
    timeZone: 'UTC',
  }).format(date)} UTC`
}

function OrganizationSpecificDetails({
  item,
  catalogs,
}: {
  item: OrganizationFundingOpportunityDetail
  catalogs?: OrganizationCatalogs
}) {
  const textConditions = [
    ['Actividades permitidas', item.allowedActivities],
    ['Actividades excluidas', item.excludedActivities],
    ['Restricciones', item.restrictions],
    ['Organizaciones objetivo', item.targetOrganizationsDescription],
    ['Poblaciones objetivo', item.targetPopulationsDescription],
  ].filter((entry): entry is [string, string] => Boolean(entry[1]))
  const organizationTypes = item.organizationTypes.map((value) => {
    const name = catalogs?.organizationTypes.find((option) => option.id === value.id)?.name
    return name ? `${name} · ${value.eligibilityMode === 1 ? 'admitido' : 'excluido'}` : null
  }).filter((value): value is string => Boolean(value))
  const legalEntityTypes = item.legalEntityTypes.map((value) => {
    const name = catalogs?.legalEntityTypes.find((option) => option.id === value.id)?.name
    return name ? `${name} · ${value.eligibilityMode === 1 ? 'admitida' : 'excluida'}` : null
  }).filter((value): value is string => Boolean(value))
  const languages = catalogNames(item.languages.map((value) => value.id), catalogs?.languages)
  const classifications = [
    catalogNames(item.countryIds, catalogs?.countries),
    catalogNames(item.regionIds, catalogs?.regions),
    catalogNames(item.categoryIds, catalogs?.fundingCategories),
    catalogNames(item.beneficiaryTypeIds, catalogs?.beneficiaryTypes),
    catalogNames(item.projectTypeIds, catalogs?.projectTypes),
    catalogNames(item.tagIds, catalogs?.tags),
    organizationTypes,
    legalEntityTypes,
    languages,
  ].some((values) => values.length > 0)
  const fundingType = catalogs?.fundingTypes.find((value) => value.id === item.fundingTypeId)?.name
  const issuerCountry = catalogs?.countries.find((value) => value.id === item.issuerCountryId)?.name
  const deadline = item.deadlineType === 2 ? 'Convocatoria continua'
    : item.deadlineType === 1 ? 'Fecha de cierre fija' : 'No informado'
  const deadlinePrecision = item.deadlinePrecision === 2 ? 'Fecha y hora'
    : item.deadlinePrecision === 1 ? 'Fecha' : 'No informada'
  const exactClose = formatUtcDateTime(item.closeAtUtc)
  const geography = item.geographicScope === 2 ? 'Global'
    : item.geographicScope === 1 ? 'Territorios especificados en las bases' : 'No informado'
  const remote = item.remoteApplication === 2 ? 'Sí'
    : item.remoteApplication === 1 ? 'No' : 'No informado'

  return (
    <>
      <section className="space-y-4 rounded-xl border p-5">
        <div>
          <h2 className="text-xl font-bold">Condiciones publicadas</h2>
          <p className="mt-1 text-xs leading-5 text-muted-foreground">
            Estos datos provienen de las bases y no confirman por sí solos que tu organización sea elegible.
          </p>
        </div>
        <dl className="grid gap-3 text-sm sm:grid-cols-2">
          <div><dt className="font-semibold">Tipo de financiamiento</dt><dd className="mt-1 text-muted-foreground">{fundingType ?? 'No informado'}</dd></div>
          <div><dt className="font-semibold">País emisor</dt><dd className="mt-1 text-muted-foreground">{issuerCountry ?? 'No informado'}</dd></div>
          <div><dt className="font-semibold">Modalidad de cierre</dt><dd className="mt-1 text-muted-foreground">{deadline}</dd></div>
          <div><dt className="font-semibold">Precisión del cierre</dt><dd className="mt-1 text-muted-foreground">{deadlinePrecision}</dd></div>
          {exactClose && <div><dt className="font-semibold">Cierre exacto</dt><dd className="mt-1 text-muted-foreground">{exactClose}</dd></div>}
          <div><dt className="font-semibold">Alcance geográfico</dt><dd className="mt-1 text-muted-foreground">{geography}</dd></div>
          <div><dt className="font-semibold">Postulación remota</dt><dd className="mt-1 text-muted-foreground">{remote}</dd></div>
          <div><dt className="font-semibold">Años mínimos de operación</dt><dd className="mt-1 text-muted-foreground">{item.minimumOperatingYears ?? 'No informado'}</dd></div>
          <div><dt className="font-semibold">Exige entidad legal</dt><dd className="mt-1 text-muted-foreground">{yesNoUnknown(item.requiresLegalEntity)}</dd></div>
          <div><dt className="font-semibold">Exige experiencia previa</dt><dd className="mt-1 text-muted-foreground">{yesNoUnknown(item.requiresPriorExperience)}</dd></div>
          <div><dt className="font-semibold">Porcentaje de cofinanciamiento</dt><dd className="mt-1 text-muted-foreground">{item.cofundingPercentage === null ? 'No informado' : `${item.cofundingPercentage}%`}</dd></div>
          {item.deadlineTimeZoneId && <div><dt className="font-semibold">Zona horaria del cierre</dt><dd className="mt-1 text-muted-foreground">{item.deadlineTimeZoneId}</dd></div>}
        </dl>
        {textConditions.map(([label, value]) => (
          <div key={label}>
            <h3 className="text-sm font-bold">{label}</h3>
            <p className="mt-1 whitespace-pre-line text-sm leading-6 text-muted-foreground">{value}</p>
          </div>
        ))}
      </section>

      {classifications && (
        <section className="space-y-4">
          <h2 className="text-xl font-bold">Cobertura y clasificaciones de las bases</h2>
          <DetailChips label="Países" values={catalogNames(item.countryIds, catalogs?.countries)} />
          <DetailChips label="Regiones" values={catalogNames(item.regionIds, catalogs?.regions)} />
          <DetailChips label="Categorías" values={catalogNames(item.categoryIds, catalogs?.fundingCategories)} />
          <DetailChips label="Poblaciones beneficiarias" values={catalogNames(item.beneficiaryTypeIds, catalogs?.beneficiaryTypes)} />
          <DetailChips label="Tipos de proyecto" values={catalogNames(item.projectTypeIds, catalogs?.projectTypes)} />
          <DetailChips label="Temas" values={catalogNames(item.tagIds, catalogs?.tags)} />
          <DetailChips label="Tipos de organización" values={organizationTypes} />
          <DetailChips label="Personalidades jurídicas" values={legalEntityTypes} />
          <DetailChips label="Idiomas indicados" values={languages} />
        </section>
      )}

      {item.sources.length > 0 && (
        <section>
          <h2 className="text-xl font-bold">Fuentes vinculadas</h2>
          <ul className="mt-3 grid gap-2">
            {item.sources.map((source) => (
              <li className="rounded-lg border px-4 py-3 text-sm" key={`${source.fundingSourceId}-${source.externalId ?? source.sourceUrl}`}>
                <a className="font-semibold text-primary underline underline-offset-2" href={source.sourceUrl} rel="noopener noreferrer" target="_blank">
                  {source.sourceName}
                </a>
                {source.externalId && <span className="ml-2 text-xs text-muted-foreground">Referencia {source.externalId}</span>}
                {source.isPrimary && <span className="ml-2 text-xs text-muted-foreground">Fuente principal</span>}
              </li>
            ))}
          </ul>
        </section>
      )}
    </>
  )
}

export function OrganizationFundingCatalogPage() {
  const [searchParams, setSearchParams] = useSearchParams()
  const { organizations, organization } = useOrganization()
  const catalogs = useQuery({
    queryKey: ['organization-catalogs'],
    queryFn: ({ signal }) => organizationApi.catalogs(signal),
    staleTime: 60 * 60 * 1000,
  })
  const urlQuery = searchParams.get('q') ?? ''
  const [draftQuery, setDraftQuery] = useState(urlQuery)

  const replaceParameter = useCallback((key: string, value?: string, resetPage = true) => {
    const next = new URLSearchParams(searchParams)
    if (value?.trim()) next.set(key, value.trim())
    else next.delete(key)
    if (resetPage) next.delete('page')
    setSearchParams(next, { replace: true })
  }, [searchParams, setSearchParams])

  useEffect(() => {
    if (draftQuery === urlQuery) return
    const timeout = window.setTimeout(() => replaceParameter('q', draftQuery), 450)
    return () => window.clearTimeout(timeout)
  }, [draftQuery, replaceParameter, urlQuery])

  useEffect(() => setDraftQuery(urlQuery), [urlQuery])

  const page = parsePositiveInteger(searchParams.get('page'), 1)
  const pageSize = Math.min(48, parsePositiveInteger(searchParams.get('pageSize'), defaultPageSize))
  const minimumAmount = parseOptionalNumber(searchParams.get('minAmount'))
  const maximumAmount = parseOptionalNumber(searchParams.get('maxAmount'))
  const closingFrom = searchParams.get('closingFrom') ?? ''
  const closingTo = searchParams.get('closingTo') ?? ''
  const currency = searchParams.get('currency') ?? ''
  const sort = parseSort(searchParams.get('sort'), Boolean(urlQuery.trim()))
  const amountError = minimumAmount !== undefined && maximumAmount !== undefined && minimumAmount > maximumAmount
  const amountCurrencyError = (minimumAmount !== undefined || maximumAmount !== undefined) && !currency
  const amountSortCurrencyError = (sort === 'amount-asc' || sort === 'amount-desc') && !currency
  const dateError = Boolean(closingFrom && closingTo && closingFrom > closingTo)

  const criteria = useMemo(() => ({
    query: urlQuery,
    countryIds: parseIds(searchParams.get('countryIds')),
    regionIds: parseIds(searchParams.get('regionIds')),
    categoryIds: parseIds(searchParams.get('categoryIds')),
    tagIds: parseIds(searchParams.get('tagIds')),
    beneficiaryTypeIds: parseIds(searchParams.get('beneficiaryTypeIds')),
    projectTypeIds: parseIds(searchParams.get('projectTypeIds')),
    fundingTypeIds: parseIds(searchParams.get('fundingTypeIds')),
    organizationTypeIds: parseIds(searchParams.get('organizationTypeIds')),
    sponsor: searchParams.get('sponsor') ?? undefined,
    minimumAmount,
    maximumAmount,
    currency: currency || undefined,
    closingFrom: closingFrom || undefined,
    closingTo: closingTo || undefined,
    onlyOpen: searchParams.get('onlyOpen') !== 'false',
    sort,
    pageNumber: page,
    pageSize,
  }), [searchParams, urlQuery, minimumAmount, maximumAmount, currency, closingFrom, closingTo, sort, page, pageSize])

  const opportunities = useQuery({
    queryKey: ['organization-funding', organization?.publicId, 'search', criteria],
    queryFn: ({ signal }) => organizationFundingApi.search(organization!.publicId, criteria, signal),
    enabled: Boolean(organization) && !amountError && !amountCurrencyError && !amountSortCurrencyError && !dateError,
    placeholderData: keepPreviousData,
  })

  function submitSearch(event: FormEvent<HTMLFormElement>) {
    event.preventDefault()
    replaceParameter('q', draftQuery)
  }

  function resetFilters() {
    setDraftQuery('')
    setSearchParams(new URLSearchParams(), { replace: true })
  }

  if (organizations.isPending || catalogs.isPending) return <PageLoading label="Preparando oportunidades…" />
  if (organizations.isError || catalogs.isError || !catalogs.data) {
    return (
      <Card><CardContent className="p-8" role="alert">
        <h1 className="text-xl font-bold">No pudimos preparar el catálogo</h1>
        <p className="mt-2 text-sm text-muted-foreground">Comprueba la conexión e intenta nuevamente.</p>
      </CardContent></Card>
    )
  }
  if (!organization) return <OrganizationRequired />

  const filterCount = [
    'countryIds', 'regionIds', 'categoryIds', 'tagIds', 'beneficiaryTypeIds', 'projectTypeIds',
    'fundingTypeIds', 'organizationTypeIds', 'currency', 'minAmount', 'maxAmount', 'closingFrom',
    'closingTo', 'sponsor',
  ].filter((key) => searchParams.has(key)).length + (searchParams.get('onlyOpen') === 'false' ? 1 : 0)

  return (
    <div className="space-y-6">
      <header className="space-y-2">
        <p className="text-sm font-bold uppercase tracking-[0.16em] text-primary">Catálogo de fondos</p>
        <h1 className="text-3xl font-bold tracking-tight">Concursos disponibles</h1>
        <p className="text-muted-foreground">
          Busca fondos publicados para {organization.name}. Los filtros y la paginación se procesan en el servidor.
        </p>
      </header>

      <Card>
        <CardContent className="space-y-5 p-5 sm:p-6">
          <form className="flex flex-col gap-2 sm:flex-row" onSubmit={submitSearch}>
            <label className="sr-only" htmlFor="organization-funding-search">Buscar oportunidades</label>
            <div className="relative flex-1">
              <Search className="absolute left-3 top-1/2 size-4 -translate-y-1/2 text-muted-foreground" />
              <input
                className="h-11 w-full rounded-lg border bg-background pl-10 pr-10 text-sm"
                id="organization-funding-search"
                maxLength={300}
                onChange={(event) => setDraftQuery(event.target.value)}
                placeholder="Título, organismo o descripción"
                value={draftQuery}
              />
              {draftQuery && (
                <button
                  aria-label="Limpiar búsqueda"
                  className="absolute right-2 top-1/2 grid size-8 -translate-y-1/2 place-items-center rounded-md text-muted-foreground hover:bg-muted"
                  onClick={() => { setDraftQuery(''); replaceParameter('q', '') }}
                  type="button"
                >
                  <X className="size-4" />
                </button>
              )}
            </div>
            <Button type="submit">Buscar</Button>
          </form>

          <details className="rounded-xl border p-4" open={filterCount > 0}>
            <summary className="flex cursor-pointer list-none items-center justify-between gap-3 font-semibold">
              <span className="flex items-center gap-2"><SlidersHorizontal className="size-4" /> Filtros avanzados</span>
              {filterCount > 0 && <span className="rounded-full bg-accent px-2 py-1 text-xs">{filterCount} activos</span>}
            </summary>
            <div className="mt-5 grid gap-4 md:grid-cols-2 xl:grid-cols-3">
              <CatalogSelect id="filter-country" items={catalogs.data.countries} label="País" onChange={(value) => replaceParameter('countryIds', value)} value={firstId(searchParams.get('countryIds'))} />
              <CatalogSelect id="filter-region" items={catalogs.data.regions} label="Región" onChange={(value) => replaceParameter('regionIds', value)} value={firstId(searchParams.get('regionIds'))} />
              <CatalogSelect id="filter-category" items={catalogs.data.fundingCategories} label="Categoría" onChange={(value) => replaceParameter('categoryIds', value)} value={firstId(searchParams.get('categoryIds'))} />
              <CatalogSelect id="filter-tag" items={catalogs.data.tags} label="Tema" onChange={(value) => replaceParameter('tagIds', value)} value={firstId(searchParams.get('tagIds'))} />
              <CatalogSelect id="filter-funding-type" items={catalogs.data.fundingTypes} label="Tipo de financiamiento" onChange={(value) => replaceParameter('fundingTypeIds', value)} value={firstId(searchParams.get('fundingTypeIds'))} />
              <CatalogSelect
                description="Filtra lo indicado en las bases; no confirma elegibilidad."
                id="filter-organization-type"
                items={catalogs.data.organizationTypes}
                label="Tipo de organización admitido"
                onChange={(value) => replaceParameter('organizationTypeIds', value)}
                value={firstId(searchParams.get('organizationTypeIds'))}
              />
              <CatalogSelect id="filter-beneficiary" items={catalogs.data.beneficiaryTypes} label="Población beneficiaria" onChange={(value) => replaceParameter('beneficiaryTypeIds', value)} value={firstId(searchParams.get('beneficiaryTypeIds'))} />
              <CatalogSelect id="filter-project-type" items={catalogs.data.projectTypes} label="Tipo de proyecto" onChange={(value) => replaceParameter('projectTypeIds', value)} value={firstId(searchParams.get('projectTypeIds'))} />
              <label className="grid gap-1.5 text-sm font-semibold" htmlFor="filter-sponsor">Organismo convocante
                <input className={inputClass} id="filter-sponsor" maxLength={250} onChange={(event) => replaceParameter('sponsor', event.target.value)} placeholder="Nombre del organismo" value={searchParams.get('sponsor') ?? ''} />
              </label>
              <label className="grid gap-1.5 text-sm font-semibold" htmlFor="filter-currency">Moneda
                <select className={selectClass} id="filter-currency" onChange={(event) => replaceParameter('currency', event.target.value)} value={currency}>
                  <option value="">Todas</option>
                  {catalogs.data.currencies.map((item) => <option key={item.code} value={item.code}>{item.code} · {item.name}</option>)}
                </select>
              </label>
              <label className="grid gap-1.5 text-sm font-semibold" htmlFor="filter-minimum">Monto mínimo
                <input className={inputClass} id="filter-minimum" min="0" onChange={(event) => replaceParameter('minAmount', event.target.value)} step="1" type="number" value={searchParams.get('minAmount') ?? ''} />
              </label>
              <label className="grid gap-1.5 text-sm font-semibold" htmlFor="filter-maximum">Monto máximo
                <input className={inputClass} id="filter-maximum" min="0" onChange={(event) => replaceParameter('maxAmount', event.target.value)} step="1" type="number" value={searchParams.get('maxAmount') ?? ''} />
              </label>
              <label className="grid gap-1.5 text-sm font-semibold" htmlFor="filter-closing-from">Cierre desde
                <input className={inputClass} id="filter-closing-from" onChange={(event) => replaceParameter('closingFrom', event.target.value)} type="date" value={closingFrom} />
              </label>
              <label className="grid gap-1.5 text-sm font-semibold" htmlFor="filter-closing-to">Cierre hasta
                <input className={inputClass} id="filter-closing-to" onChange={(event) => replaceParameter('closingTo', event.target.value)} type="date" value={closingTo} />
              </label>
              <label className="flex items-center gap-2 self-end rounded-lg border px-3 py-2.5 text-sm font-semibold">
                <input checked={criteria.onlyOpen} onChange={(event) => replaceParameter('onlyOpen', event.target.checked ? '' : 'false')} type="checkbox" />
                Solo convocatorias abiertas
              </label>
            </div>
            {(amountError || amountCurrencyError || amountSortCurrencyError || dateError) && (
              <div className="mt-4 rounded-lg bg-destructive/10 p-3 text-sm text-destructive" role="alert">
                {amountError && 'El monto mínimo no puede superar al máximo.'}
                {amountCurrencyError && ' Selecciona una moneda para filtrar por monto.'}
                {amountSortCurrencyError && ' Selecciona una moneda para ordenar por monto.'}
                {dateError && ' La fecha inicial de cierre no puede ser posterior a la final.'}
              </div>
            )}
            <Button className="mt-4" onClick={resetFilters} size="sm" type="button" variant="ghost">
              <X className="size-4" /> Limpiar filtros
            </Button>
          </details>
        </CardContent>
      </Card>

      <div className="flex flex-wrap items-end justify-between gap-3">
        <p aria-live="polite" className="text-sm text-muted-foreground">
          {opportunities.data
            ? <><strong className="text-foreground">{opportunities.data.totalCount}</strong> oportunidades encontradas</>
            : 'Preparando resultados…'}
          {opportunities.isFetching && <span> · Actualizando…</span>}
        </p>
        <div className="flex flex-wrap gap-2">
          <label className="grid gap-1 text-xs font-semibold" htmlFor="funding-sort">Ordenar
            <select className={selectClass} id="funding-sort" onChange={(event) => replaceParameter('sort', event.target.value)} value={criteria.sort}>
              <option disabled={!urlQuery.trim()} value="relevance">Relevancia</option>
              <option value="closing-soon">Cierre más próximo</option>
              <option value="newest">Publicados recientemente</option>
              <option value="amount-asc">Monto máximo: menor a mayor</option>
              <option value="amount-desc">Monto máximo: mayor a menor</option>
            </select>
          </label>
          <label className="grid gap-1 text-xs font-semibold" htmlFor="funding-page-size">Por página
            <select className={selectClass} id="funding-page-size" onChange={(event) => replaceParameter('pageSize', event.target.value)} value={pageSize}>
              <option value="12">12</option><option value="24">24</option><option value="48">48</option>
            </select>
          </label>
        </div>
      </div>

      {opportunities.isPending && <PageLoading label="Buscando oportunidades…" />}
      {opportunities.isError && (
        <Card className="border-destructive/40"><CardContent className="space-y-3 p-6" role="alert">
          <h2 className="font-bold">No fue posible buscar oportunidades</h2>
          <p className="text-sm text-muted-foreground">{apiErrorMessage(opportunities.error, 'Comprueba la conexión e intenta nuevamente.')}</p>
          <Button onClick={() => void opportunities.refetch()} variant="outline">Reintentar</Button>
        </CardContent></Card>
      )}
      {opportunities.data && opportunities.data.items.length === 0 && (
        <Card><CardContent className="space-y-3 p-8 text-center">
          <ListFilter className="mx-auto size-8 text-muted-foreground" />
          <h2 className="font-bold">No encontramos concursos con esos criterios</h2>
          <p className="text-sm text-muted-foreground">Amplía la búsqueda o limpia algunos filtros.</p>
          <Button onClick={resetFilters} variant="outline">Limpiar búsqueda y filtros</Button>
        </CardContent></Card>
      )}
      {opportunities.data && opportunities.data.items.length > 0 && (
        <FundingGrid items={opportunities.data.items} organization={organization} />
      )}
      {opportunities.data && (
        <ResultsPagination disabled={opportunities.isFetching} page={page} response={opportunities.data} setPage={(value) => replaceParameter('page', String(value), false)} />
      )}
    </div>
  )
}

export function OrganizationFundingDetailPage() {
  const { slug = '' } = useParams()
  const { organizations, organization } = useOrganization()
  const opportunity = useQuery({
    queryKey: ['organization-funding', organization?.publicId, 'detail', slug],
    queryFn: ({ signal }) => organizationFundingApi.getByIdOrSlug(organization!.publicId, slug, signal),
    enabled: Boolean(organization && slug),
    retry: false,
  })
  const catalogs = useQuery({
    queryKey: ['organization-catalogs'],
    queryFn: ({ signal }) => organizationApi.catalogs(signal),
    staleTime: 60 * 60 * 1000,
  })

  useEffect(() => {
    if (!opportunity.data) return
    const previousTitle = document.title
    document.title = `${opportunity.data.title} · FundingPlatform`
    return () => { document.title = previousTitle }
  }, [opportunity.data])

  if (organizations.isPending) return <PageLoading label="Cargando organización…" />
  if (organizations.isError) return <Card><CardContent className="p-8" role="alert">No pudimos cargar tu organización.</CardContent></Card>
  if (!organization) return <OrganizationRequired />
  if (opportunity.isPending) return <PageLoading label="Cargando oportunidad…" />
  if (opportunity.isError || !opportunity.data) {
    return (
      <Card><CardContent className="space-y-4 p-8" role="alert">
        <h1 className="text-2xl font-bold">No pudimos abrir esta oportunidad</h1>
        <p className="text-sm text-muted-foreground">{apiErrorMessage(opportunity.error, 'La oportunidad no existe o ya no está publicada.')}</p>
        <Button asChild variant="outline"><Link to="/opportunities">Volver a concursos</Link></Button>
      </CardContent></Card>
    )
  }

  return (
    <FundingOpportunityDetailView
      action={(
        <Card>
          <CardHeader><CardTitle>Tu selección</CardTitle></CardHeader>
          <CardContent>
            <FavoriteButton fullWidth organizationId={organization.publicId} opportunity={opportunity.data} />
          </CardContent>
        </Card>
      )}
      additionalDetails={<OrganizationSpecificDetails catalogs={catalogs.data} item={opportunity.data} />}
      backTo="/opportunities"
      item={toDisplayDetail(opportunity.data)}
    />
  )
}

export function OrganizationFavoritesPage() {
  const [searchParams, setSearchParams] = useSearchParams()
  const { organizations, organization } = useOrganization()
  const page = parsePositiveInteger(searchParams.get('page'), 1)
  const favorites = useQuery({
    queryKey: ['organization-funding', organization?.publicId, 'favorites', page, defaultPageSize],
    queryFn: ({ signal }) => organizationFundingApi.favorites(organization!.publicId, page, defaultPageSize, signal),
    enabled: Boolean(organization),
    placeholderData: keepPreviousData,
  })

  const setPage = useCallback((value: number) => {
    const next = new URLSearchParams(searchParams)
    if (value <= 1) next.delete('page')
    else next.set('page', String(value))
    setSearchParams(next, { replace: true })
  }, [searchParams, setSearchParams])

  useEffect(() => {
    if (!favorites.data || favorites.data.totalCount === 0) return
    const lastPage = Math.max(1, Math.ceil(favorites.data.totalCount / favorites.data.pageSize))
    if (page > lastPage) setPage(lastPage)
  }, [favorites.data, page, setPage])

  if (organizations.isPending) return <PageLoading label="Cargando favoritos…" />
  if (organizations.isError) return <Card><CardContent className="p-8" role="alert">No pudimos cargar tu organización.</CardContent></Card>
  if (!organization) return <OrganizationRequired />

  return (
    <div className="space-y-6">
      <header className="flex flex-wrap items-end justify-between gap-4">
        <div>
          <p className="text-sm font-bold uppercase tracking-[0.16em] text-primary">Tu organización</p>
          <h1 className="mt-1 text-3xl font-bold tracking-tight">Favoritos</h1>
          <p className="mt-2 text-muted-foreground">Concursos guardados por tu cuenta en {organization.name}.</p>
        </div>
        <Button asChild variant="outline"><Link to="/opportunities"><Search className="size-4" /> Explorar concursos</Link></Button>
      </header>

      {favorites.isPending && <PageLoading label="Cargando favoritos…" />}
      {favorites.isError && (
        <Card className="border-destructive/40"><CardContent className="space-y-3 p-6" role="alert">
          <h2 className="font-bold">No fue posible cargar tus favoritos</h2>
          <p className="text-sm text-muted-foreground">{apiErrorMessage(favorites.error, 'Comprueba la conexión e intenta nuevamente.')}</p>
          <Button onClick={() => void favorites.refetch()} variant="outline">Reintentar</Button>
        </CardContent></Card>
      )}
      {favorites.data && favorites.data.totalCount === 0 && (
        <Card><CardContent className="space-y-4 p-8 text-center">
          <Heart className="mx-auto size-9 text-muted-foreground" />
          <h2 className="text-xl font-bold">Todavía no guardas concursos</h2>
          <p className="text-sm text-muted-foreground">Guarda los que te interesen para encontrarlos aquí rápidamente.</p>
          <Button asChild><Link to="/opportunities">Explorar oportunidades</Link></Button>
        </CardContent></Card>
      )}
      {favorites.data && favorites.data.totalCount > 0 && favorites.data.items.length === 0 && (
        <PageLoading label="Volviendo a la última página con favoritos…" />
      )}
      {favorites.data && favorites.data.items.length > 0 && (
        <>
          <p aria-live="polite" className="text-sm text-muted-foreground"><strong className="text-foreground">{favorites.data.totalCount}</strong> favoritos guardados</p>
          <FundingGrid items={favorites.data.items} organization={organization} />
        </>
      )}
      {favorites.data && <ResultsPagination disabled={favorites.isFetching} page={page} response={favorites.data} setPage={setPage} />}
    </div>
  )
}
