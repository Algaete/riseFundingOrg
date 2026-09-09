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
  Save,
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
import { useTranslation } from 'react-i18next'
import { catalogName, catalogLanguage, type CatalogKind } from '@/i18n/catalog-labels'
import { Link, useParams, useSearchParams } from 'react-router-dom'

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
import i18n from '@/i18n'
import { organizationFundingErrorMessage } from '@/i18n/organization-funding-feedback'
import { workspaceLocale } from '@/i18n/workspace-messages'

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
  const { t } = useTranslation()
  return (
    <Card>
      <CardContent className="space-y-4 p-8 text-center">
        <h1 className="text-2xl font-bold">{t('organizationFunding.requiredTitle')}</h1>
        <p className="text-sm text-muted-foreground">
          {t('organizationFunding.requiredHelp')}
        </p>
        <Button asChild><Link to="/onboarding">{t('organizationFunding.createOrganization')}</Link></Button>
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
  const { t } = useTranslation()
  const queryClient = useQueryClient()
  const [feedback, setFeedback] = useState<'' | 'organizationFunding.favoriteFailed' | 'organizationFunding.favoriteAdded' | 'organizationFunding.favoriteRemoved'>('')
  const mutation = useMutation({
    mutationFn: (nextFavoriteState: boolean) => nextFavoriteState
      ? organizationFundingApi.addFavorite(organizationId, opportunity.publicId)
      : organizationFundingApi.removeFavorite(organizationId, opportunity.publicId),
    onMutate: async (nextFavoriteState) => {
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
      setFeedback('organizationFunding.favoriteFailed')
    },
    onSuccess: (_data, nextFavoriteState) => {
      setFeedback(nextFavoriteState ? 'organizationFunding.favoriteAdded' : 'organizationFunding.favoriteRemoved')
    },
    onSettled: async () => {
      await queryClient.invalidateQueries({ queryKey: ['organization-funding', organizationId] })
    },
  })

  const label = opportunity.isFavorite ? t('organizationFunding.removeFavorite') : t('organizationFunding.saveFavorite')
  return (
    <div className={fullWidth ? 'grid gap-2' : 'grid gap-1'}>
      <Button
        aria-pressed={opportunity.isFavorite}
        className={fullWidth ? 'w-full' : undefined}
        disabled={mutation.isPending}
        onClick={() => mutation.mutate(!opportunity.isFavorite)}
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
          {t(feedback)}
        </p>
      )}
    </div>
  )
}

function CatalogSelect({
  catalog,
  id,
  label,
  description,
  items,
  value,
  onChange,
}: {
  catalog: CatalogKind
  id: string
  label: string
  description?: string
  items: CatalogOption<number>[]
  value: string
  onChange: (value: string) => void
}) {
  const { t } = useTranslation()
  return (
    <label className="grid gap-1.5 text-sm font-semibold" htmlFor={id}>
      {label}
      <select className={selectClass} id={id} onChange={(event) => onChange(event.target.value)} value={value}>
        <option value="">{t('organizationFunding.all')}</option>
        {items.map((item) => <option key={item.id} lang={catalogLanguage(catalog, item)} value={item.id}>{catalogName(catalog, item)}</option>)}
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
  const { t } = useTranslation()
  const lastPage = Math.max(1, Math.ceil(response.totalCount / response.pageSize))
  if (lastPage <= 1) return null
  return (
    <nav aria-label={t('organizationFunding.pagination')} className="flex flex-wrap items-center justify-between gap-3 rounded-xl border bg-card p-3 sm:justify-end">
      <Button disabled={page <= 1 || disabled} onClick={() => setPage(page - 1)} type="button" variant="outline">
        <ChevronLeft className="size-4" /> {t('organizationFunding.previous')}
      </Button>
      <p className="text-sm text-muted-foreground">
        {t('organizationFunding.page', { page: response.pageNumber, total: lastPage })}
      </p>
      <Button disabled={page >= lastPage || disabled} onClick={() => setPage(page + 1)} type="button" variant="outline">
        {t('organizationFunding.next')} <ChevronRight className="size-4" />
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
          action={<div className="grid"><FavoriteButton organizationId={organization.publicId} opportunity={opportunity} /></div>}
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

function catalogChip(catalog: CatalogKind, item: CatalogOption<number>) {
  return { key: item.id, name: catalogName(catalog, item), language: catalogLanguage(catalog, item) }
}

function catalogChips(catalog: CatalogKind, ids: readonly number[], items: readonly CatalogOption<number>[] = []) {
  const options = new Map(items.map((item) => [item.id, item]))
  // Keep identity separate from the translated label: distinct options can share a name.
  return [...new Set(ids)].flatMap(id => {
    const item = options.get(id)
    return item?.name ? [catalogChip(catalog, item)] : []
  })
}

type DetailChip = ReturnType<typeof catalogChip> & { suffix?: string }

function DetailChips({ label, values }: { label: string; values: readonly DetailChip[] }) {
  if (values.length === 0) return null
  return (
    <div>
      <h3 className="text-sm font-bold">{label}</h3>
      <ul className="mt-2 flex flex-wrap gap-2">
        {values.map((value) => (
          <li className="rounded-full border bg-background px-3 py-1.5 text-xs" key={value.key}>
            <span lang={value.language}>{value.name}</span>{value.suffix && <> · {value.suffix}</>}
          </li>
        ))}
      </ul>
    </div>
  )
}

function yesNoUnknown(value: boolean | null) {
  return value === null ? i18n.t('organizationFunding.notReported') : value ? i18n.t('organizationFunding.yes') : i18n.t('organizationFunding.no')
}

function formatUtcDateTime(value: string | null) {
  if (!value) return null
  const date = new Date(value)
  if (Number.isNaN(date.getTime())) return null
  return `${new Intl.DateTimeFormat(workspaceLocale(), {
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
  const { t } = useTranslation()
  const textConditions = [
    [t('organizationFunding.allowedActivities'), item.allowedActivities],
    [t('organizationFunding.excludedActivities'), item.excludedActivities],
    [t('organizationFunding.restrictions'), item.restrictions],
    [t('organizationFunding.targetOrganizations'), item.targetOrganizationsDescription],
    [t('organizationFunding.targetPopulations'), item.targetPopulationsDescription],
  ].filter((entry): entry is [string, string] => Boolean(entry[1]))
  const organizationTypes = item.organizationTypes.map((value) => {
    const option = catalogs?.organizationTypes.find((option) => option.id === value.id)
    return option?.name ? { ...catalogChip('organizationTypes', option), suffix: value.eligibilityMode === 1 ? t('organizationFunding.admitted') : t('organizationFunding.excluded') } : null
  }).filter((value) => value !== null)
  const legalEntityTypes = item.legalEntityTypes.map((value) => {
    const option = catalogs?.legalEntityTypes.find((option) => option.id === value.id)
    return option?.name ? { ...catalogChip('legalEntityTypes', option), suffix: value.eligibilityMode === 1 ? t('organizationFunding.admittedFeminine') : t('organizationFunding.excludedFeminine') } : null
  }).filter((value) => value !== null)
  const languages = catalogChips('languages', item.languages.map((value) => value.id), catalogs?.languages)
  const classifications = [
    catalogChips('countries', item.countryIds, catalogs?.countries),
    catalogChips('regions', item.regionIds, catalogs?.regions),
    catalogChips('fundingCategories', item.categoryIds, catalogs?.fundingCategories),
    catalogChips('beneficiaryTypes', item.beneficiaryTypeIds, catalogs?.beneficiaryTypes),
    catalogChips('projectTypes', item.projectTypeIds, catalogs?.projectTypes),
    catalogChips('tags', item.tagIds, catalogs?.tags),
    organizationTypes,
    legalEntityTypes,
    languages,
  ].some((values) => values.length > 0)
  const fundingType = catalogs?.fundingTypes.find((value) => value.id === item.fundingTypeId)
  const issuerCountry = catalogs?.countries.find((value) => value.id === item.issuerCountryId)
  const deadline = item.deadlineType === 2 ? t('organizationFunding.continuous')
    : item.deadlineType === 1 ? t('organizationFunding.fixedDeadline') : t('organizationFunding.notReported')
  const deadlinePrecision = item.deadlinePrecision === 2 ? t('organizationFunding.dateTime')
    : item.deadlinePrecision === 1 ? t('organizationFunding.date') : t('organizationFunding.notReportedFeminine')
  const exactClose = formatUtcDateTime(item.closeAtUtc)
  const geography = item.geographicScope === 2 ? t('organizationFunding.global')
    : item.geographicScope === 1 ? t('organizationFunding.specifiedTerritories') : t('organizationFunding.notReported')
  const remote = item.remoteApplication === 2 ? t('organizationFunding.yes')
    : item.remoteApplication === 1 ? t('organizationFunding.no') : t('organizationFunding.notReported')

  return (
    <>
      <section className="space-y-4 rounded-xl border p-5">
        <div>
          <h2 className="text-xl font-bold">{t('organizationFunding.publishedConditions')}</h2>
          <p className="mt-1 text-xs leading-5 text-muted-foreground">
            {t('organizationFunding.conditionsHelp')}
          </p>
        </div>
        <dl className="grid gap-3 text-sm sm:grid-cols-2">
          <div><dt className="font-semibold">{t('organizationFunding.fundingType')}</dt><dd className="mt-1 text-muted-foreground">{fundingType ? <span lang={catalogLanguage('fundingTypes', fundingType)}>{catalogName('fundingTypes', fundingType)}</span> : t('organizationFunding.notReported')}</dd></div>
          <div><dt className="font-semibold">{t('organizationFunding.issuerCountry')}</dt><dd className="mt-1 text-muted-foreground">{issuerCountry ? <span lang={catalogLanguage('countries', issuerCountry)}>{catalogName('countries', issuerCountry)}</span> : t('organizationFunding.notReported')}</dd></div>
          <div><dt className="font-semibold">{t('organizationFunding.deadlineType')}</dt><dd className="mt-1 text-muted-foreground">{deadline}</dd></div>
          <div><dt className="font-semibold">{t('organizationFunding.deadlinePrecision')}</dt><dd className="mt-1 text-muted-foreground">{deadlinePrecision}</dd></div>
          {exactClose && <div><dt className="font-semibold">{t('organizationFunding.exactClose')}</dt><dd className="mt-1 text-muted-foreground">{exactClose}</dd></div>}
          <div><dt className="font-semibold">{t('organizationFunding.geography')}</dt><dd className="mt-1 text-muted-foreground">{geography}</dd></div>
          <div><dt className="font-semibold">{t('organizationFunding.remote')}</dt><dd className="mt-1 text-muted-foreground">{remote}</dd></div>
          <div><dt className="font-semibold">{t('organizationFunding.minimumYears')}</dt><dd className="mt-1 text-muted-foreground">{item.minimumOperatingYears ?? t('organizationFunding.notReported')}</dd></div>
          <div><dt className="font-semibold">{t('organizationFunding.legalRequired')}</dt><dd className="mt-1 text-muted-foreground">{yesNoUnknown(item.requiresLegalEntity)}</dd></div>
          <div><dt className="font-semibold">{t('organizationFunding.experienceRequired')}</dt><dd className="mt-1 text-muted-foreground">{yesNoUnknown(item.requiresPriorExperience)}</dd></div>
          <div><dt className="font-semibold">{t('organizationFunding.cofundingPercentage')}</dt><dd className="mt-1 text-muted-foreground">{item.cofundingPercentage === null ? t('organizationFunding.notReported') : `${item.cofundingPercentage.toLocaleString(workspaceLocale())}%`}</dd></div>
          {item.deadlineTimeZoneId && <div><dt className="font-semibold">{t('organizationFunding.deadlineZone')}</dt><dd className="mt-1 text-muted-foreground">{item.deadlineTimeZoneId}</dd></div>}
        </dl>
        {textConditions.map(([label, value]) => (
          <div key={label}>
            <h3 className="text-sm font-bold">{label}</h3>
            <p className="mt-1 whitespace-pre-line text-sm leading-6 text-muted-foreground" lang="es">{value}</p>
          </div>
        ))}
      </section>

      {classifications && (
        <section className="space-y-4">
          <h2 className="text-xl font-bold">{t('organizationFunding.classifications')}</h2>
          <DetailChips label={t('organizationFunding.countries')} values={catalogChips('countries', item.countryIds, catalogs?.countries)} />
          <DetailChips label={t('organizationFunding.regions')} values={catalogChips('regions', item.regionIds, catalogs?.regions)} />
          <DetailChips label={t('organizationFunding.categories')} values={catalogChips('fundingCategories', item.categoryIds, catalogs?.fundingCategories)} />
          <DetailChips label={t('organizationFunding.beneficiaries')} values={catalogChips('beneficiaryTypes', item.beneficiaryTypeIds, catalogs?.beneficiaryTypes)} />
          <DetailChips label={t('organizationFunding.projectTypes')} values={catalogChips('projectTypes', item.projectTypeIds, catalogs?.projectTypes)} />
          <DetailChips label={t('organizationFunding.topics')} values={catalogChips('tags', item.tagIds, catalogs?.tags)} />
          <DetailChips label={t('organizationFunding.organizationTypes')} values={organizationTypes} />
          <DetailChips label={t('organizationFunding.legalTypes')} values={legalEntityTypes} />
          <DetailChips label={t('organizationFunding.languages')} values={languages} />
        </section>
      )}

      {item.sources.length > 0 && (
        <section>
          <h2 className="text-xl font-bold">{t('organizationFunding.sources')}</h2>
          <ul className="mt-3 grid gap-2">
            {item.sources.map((source) => (
              <li className="rounded-lg border px-4 py-3 text-sm" key={`${source.fundingSourceId}-${source.externalId ?? source.sourceUrl}`}>
                <a className="font-semibold text-primary underline underline-offset-2" href={source.sourceUrl} lang="es" rel="noopener noreferrer" target="_blank">
                  {source.sourceName}
                </a>
                {source.externalId && <span className="ml-2 text-xs text-muted-foreground">{t('organizationFunding.reference', { id: source.externalId })}</span>}
                {source.isPrimary && <span className="ml-2 text-xs text-muted-foreground">{t('organizationFunding.primarySource')}</span>}
              </li>
            ))}
          </ul>
        </section>
      )}
    </>
  )
}

export function OrganizationFundingCatalogPage() {
  const { t } = useTranslation()
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
  const hasInvalidFilters = amountError || amountCurrencyError || amountSortCurrencyError || dateError

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
    enabled: Boolean(organization) && !hasInvalidFilters,
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

  if (organizations.isPending || catalogs.isPending) return <PageLoading label={t('organizationFunding.preparing')} />
  if (organizations.isError || catalogs.isError || !catalogs.data) {
    return (
      <Card><CardContent className="p-8" role="alert">
        <h1 className="text-xl font-bold">{t('organizationFunding.prepareFailed')}</h1>
        <p className="mt-2 text-sm text-muted-foreground">{t('organizationFunding.loadHelp')}</p>
      </CardContent></Card>
    )
  }
  if (!organization) return <OrganizationRequired />

  const filterCount = [
    'countryIds', 'regionIds', 'categoryIds', 'tagIds', 'beneficiaryTypeIds', 'projectTypeIds',
    'fundingTypeIds', 'organizationTypeIds', 'currency', 'minAmount', 'maxAmount', 'closingFrom',
    'closingTo', 'sponsor',
  ].filter((key) => searchParams.has(key)).length + (searchParams.get('onlyOpen') === 'false' ? 1 : 0)
  const savedSearchParameters = new URLSearchParams(searchParams)
  savedSearchParameters.delete('page')
  savedSearchParameters.delete('pageSize')
  savedSearchParameters.set('new', 'true')

  return (
    <div className="space-y-6">
      <header className="space-y-2">
        <p className="text-sm font-bold uppercase tracking-[0.16em] text-primary">{t('organizationFunding.eyebrow')}</p>
        <h1 className="text-3xl font-bold tracking-tight">{t('organizationFunding.title')}</h1>
        <p className="text-muted-foreground">
          {t('organizationFunding.description', { name: organization.name })}
        </p>
      </header>

      <Card>
        <CardContent className="space-y-5 p-5 sm:p-6">
          <form className="flex flex-col gap-2 sm:flex-row" onSubmit={submitSearch}>
            <label className="sr-only" htmlFor="organization-funding-search">{t('organizationFunding.searchLabel')}</label>
            <div className="relative flex-1">
              <Search className="absolute left-3 top-1/2 size-4 -translate-y-1/2 text-muted-foreground" />
              <input
                className="h-11 w-full rounded-lg border bg-background pl-10 pr-10 text-sm"
                id="organization-funding-search"
                maxLength={300}
                onChange={(event) => setDraftQuery(event.target.value)}
                placeholder={t('organizationFunding.searchPlaceholder')}
                value={draftQuery}
              />
              {draftQuery && (
                <button
                  aria-label={t('organizationFunding.clearSearch')}
                  className="absolute right-2 top-1/2 grid size-8 -translate-y-1/2 place-items-center rounded-md text-muted-foreground hover:bg-muted"
                  onClick={() => { setDraftQuery(''); replaceParameter('q', '') }}
                  type="button"
                >
                  <X className="size-4" />
                </button>
              )}
            </div>
            <Button type="submit">{t('organizationFunding.search')}</Button>
          </form>

          <details className="rounded-xl border p-4" open={filterCount > 0 || hasInvalidFilters}>
            <summary className="flex cursor-pointer list-none items-center justify-between gap-3 font-semibold">
              <span className="flex items-center gap-2"><SlidersHorizontal className="size-4" /> {t('organizationFunding.advanced')}</span>
              {filterCount > 0 && <span className="rounded-full bg-accent px-2 py-1 text-xs">{t('organizationFunding.active', { count: filterCount })}</span>}
            </summary>
            <div className="mt-5 grid gap-4 md:grid-cols-2 xl:grid-cols-3">
              <CatalogSelect catalog="countries" id="filter-country" items={catalogs.data.countries} label={t('organizationFunding.country')} onChange={(value) => replaceParameter('countryIds', value)} value={firstId(searchParams.get('countryIds'))} />
              <CatalogSelect catalog="regions" id="filter-region" items={catalogs.data.regions} label={t('organizationFunding.region')} onChange={(value) => replaceParameter('regionIds', value)} value={firstId(searchParams.get('regionIds'))} />
              <CatalogSelect catalog="fundingCategories" id="filter-category" items={catalogs.data.fundingCategories} label={t('organizationFunding.category')} onChange={(value) => replaceParameter('categoryIds', value)} value={firstId(searchParams.get('categoryIds'))} />
              <CatalogSelect catalog="tags" id="filter-tag" items={catalogs.data.tags} label={t('organizationFunding.topic')} onChange={(value) => replaceParameter('tagIds', value)} value={firstId(searchParams.get('tagIds'))} />
              <CatalogSelect catalog="fundingTypes" id="filter-funding-type" items={catalogs.data.fundingTypes} label={t('organizationFunding.fundingType')} onChange={(value) => replaceParameter('fundingTypeIds', value)} value={firstId(searchParams.get('fundingTypeIds'))} />
              <CatalogSelect
                description={t('organizationFunding.organizationTypeHelp')}
                id="filter-organization-type"
                catalog="organizationTypes" items={catalogs.data.organizationTypes}
                label={t('organizationFunding.admittedOrganizationType')}
                onChange={(value) => replaceParameter('organizationTypeIds', value)}
                value={firstId(searchParams.get('organizationTypeIds'))}
              />
              <CatalogSelect catalog="beneficiaryTypes" id="filter-beneficiary" items={catalogs.data.beneficiaryTypes} label={t('organizationFunding.beneficiary')} onChange={(value) => replaceParameter('beneficiaryTypeIds', value)} value={firstId(searchParams.get('beneficiaryTypeIds'))} />
              <CatalogSelect catalog="projectTypes" id="filter-project-type" items={catalogs.data.projectTypes} label={t('organizationFunding.projectType')} onChange={(value) => replaceParameter('projectTypeIds', value)} value={firstId(searchParams.get('projectTypeIds'))} />
              <label className="grid gap-1.5 text-sm font-semibold" htmlFor="filter-sponsor">{t('organizationFunding.sponsor')}
                <input className={inputClass} id="filter-sponsor" maxLength={250} onChange={(event) => replaceParameter('sponsor', event.target.value)} placeholder={t('organizationFunding.sponsorPlaceholder')} value={searchParams.get('sponsor') ?? ''} />
              </label>
              <label className="grid gap-1.5 text-sm font-semibold" htmlFor="filter-currency">{t('organizationFunding.currency')}
                <select className={selectClass} id="filter-currency" onChange={(event) => replaceParameter('currency', event.target.value)} value={currency}>
                  <option value="">{t('organizationFunding.allCurrencies')}</option>
                  {catalogs.data.currencies.map((item) => <option key={item.code} lang={catalogLanguage('currencies', item)} value={item.code}>{item.code} · {catalogName('currencies', item)}</option>)}
                </select>
              </label>
              <label className="grid gap-1.5 text-sm font-semibold" htmlFor="filter-minimum">{t('organizationFunding.minimumAmount')}
                <input className={inputClass} id="filter-minimum" min="0" onChange={(event) => replaceParameter('minAmount', event.target.value)} step="1" type="number" value={searchParams.get('minAmount') ?? ''} />
              </label>
              <label className="grid gap-1.5 text-sm font-semibold" htmlFor="filter-maximum">{t('organizationFunding.maximumAmount')}
                <input className={inputClass} id="filter-maximum" min="0" onChange={(event) => replaceParameter('maxAmount', event.target.value)} step="1" type="number" value={searchParams.get('maxAmount') ?? ''} />
              </label>
              <label className="grid gap-1.5 text-sm font-semibold" htmlFor="filter-closing-from">{t('organizationFunding.closingFrom')}
                <input className={inputClass} id="filter-closing-from" onChange={(event) => replaceParameter('closingFrom', event.target.value)} type="date" value={closingFrom} />
              </label>
              <label className="grid gap-1.5 text-sm font-semibold" htmlFor="filter-closing-to">{t('organizationFunding.closingTo')}
                <input className={inputClass} id="filter-closing-to" onChange={(event) => replaceParameter('closingTo', event.target.value)} type="date" value={closingTo} />
              </label>
              <label className="flex items-center gap-2 self-end rounded-lg border px-3 py-2.5 text-sm font-semibold">
                <input checked={criteria.onlyOpen} onChange={(event) => replaceParameter('onlyOpen', event.target.checked ? '' : 'false')} type="checkbox" />
                {t('organizationFunding.onlyOpen')}
              </label>
            </div>
            <Button className="mt-4" onClick={resetFilters} size="sm" type="button" variant="ghost">
              <X className="size-4" /> {t('organizationFunding.clearFilters')}
            </Button>
          </details>
          {hasInvalidFilters && (
            <div className="rounded-lg bg-destructive/10 p-3 text-sm text-foreground" role="alert">
              {amountError && t('organizationFunding.amountRangeError')}
              {amountCurrencyError && t('organizationFunding.amountCurrencyError')}
              {amountSortCurrencyError && t('organizationFunding.sortCurrencyError')}
              {dateError && t('organizationFunding.dateRangeError')}
            </div>
          )}
        </CardContent>
      </Card>

      <div className="flex flex-wrap items-end justify-between gap-3">
        <p aria-live="polite" className="text-sm text-muted-foreground">
          {hasInvalidFilters ? t('organizationFunding.correctFilters') : opportunities.data
            ? <><strong className="text-foreground">{opportunities.data.totalCount.toLocaleString(workspaceLocale())}</strong> {t('organizationFunding.found', { count: opportunities.data.totalCount })}</>
            : t('organizationFunding.preparingResults')}
          {opportunities.isFetching && <span> · {t('organizationFunding.refreshing')}</span>}
        </p>
        <div className="flex flex-wrap gap-2">
          <Button asChild variant="outline">
            <Link to={`/alerts?${savedSearchParameters.toString()}`}><Save className="size-4" /> {t('organizationFunding.saveSearch')}</Link>
          </Button>
          <label className="grid gap-1 text-xs font-semibold" htmlFor="funding-sort">{t('organizationFunding.sort')}
            <select className={selectClass} id="funding-sort" onChange={(event) => replaceParameter('sort', event.target.value)} value={criteria.sort}>
              <option disabled={!urlQuery.trim()} value="relevance">{t('organizationFunding.relevance')}</option>
              <option value="closing-soon">{t('organizationFunding.closingSoon')}</option>
              <option value="newest">{t('organizationFunding.newest')}</option>
              <option value="amount-asc">{t('organizationFunding.amountAsc')}</option>
              <option value="amount-desc">{t('organizationFunding.amountDesc')}</option>
            </select>
          </label>
          <label className="grid gap-1 text-xs font-semibold" htmlFor="funding-page-size">{t('organizationFunding.perPage')}
            <select className={selectClass} id="funding-page-size" onChange={(event) => replaceParameter('pageSize', event.target.value)} value={pageSize}>
              <option value="12">12</option><option value="24">24</option><option value="48">48</option>
            </select>
          </label>
        </div>
      </div>

      {opportunities.isPending && !hasInvalidFilters && <PageLoading label={t('organizationFunding.searching')} />}
      {opportunities.isError && (
        <Card className="border-destructive/40"><CardContent className="space-y-3 p-6" role="alert">
          <h2 className="font-bold">{t('organizationFunding.searchFailed')}</h2>
          <p className="text-sm text-muted-foreground">{organizationFundingErrorMessage(opportunities.error, 'organizationFunding.loadHelp')}</p>
          <Button onClick={() => void opportunities.refetch()} variant="outline">{t('organizationFunding.retry')}</Button>
        </CardContent></Card>
      )}
      {opportunities.data && opportunities.data.items.length === 0 && (
        <Card><CardContent className="space-y-3 p-8 text-center">
          <ListFilter className="mx-auto size-8 text-muted-foreground" />
          <h2 className="font-bold">{t('organizationFunding.emptyTitle')}</h2>
          <p className="text-sm text-muted-foreground">{t('organizationFunding.emptyHelp')}</p>
          <Button onClick={resetFilters} variant="outline">{t('organizationFunding.clearAll')}</Button>
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
  const { t } = useTranslation()
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

  if (organizations.isPending) return <PageLoading label={t('organizationFunding.organizationLoading')} />
  if (organizations.isError) return <Card><CardContent className="p-8" role="alert">{t('organizationFunding.organizationFailed')}</CardContent></Card>
  if (!organization) return <OrganizationRequired />
  if (opportunity.isPending) return <PageLoading label={t('organizationFunding.detailLoading')} />
  if (opportunity.isError || !opportunity.data) {
    return (
      <Card><CardContent className="space-y-4 p-8" role="alert">
        <h1 className="text-2xl font-bold">{t('organizationFunding.detailFailed')}</h1>
        <p className="text-sm text-muted-foreground">{organizationFundingErrorMessage(opportunity.error, 'organizationFunding.notAvailable')}</p>
        <Button asChild variant="outline"><Link to="/opportunities">{t('organizationFunding.back')}</Link></Button>
      </CardContent></Card>
    )
  }

  return (
    <FundingOpportunityDetailView
      action={(
        <Card>
          <CardHeader><CardTitle>{t('organizationFunding.yourSelection')}</CardTitle></CardHeader>
          <CardContent>
            <div className="grid gap-3">
              <FavoriteButton fullWidth organizationId={organization.publicId} opportunity={opportunity.data} />
              <Button asChild className="w-full">
                <Link to={`/applications?new=1&fundingOpportunityId=${encodeURIComponent(opportunity.data.publicId)}`}>
                  {t('organizationFunding.startApplication')}
                </Link>
              </Button>
              <p className="text-xs leading-5 text-muted-foreground">{t('organizationFunding.applicationHelp')}</p>
            </div>
          </CardContent>
        </Card>
      )}
      additionalDetails={<div><OrganizationSpecificDetails catalogs={catalogs.data} item={opportunity.data} /></div>}
      backTo="/opportunities"
      item={toDisplayDetail(opportunity.data)}
    />
  )
}

export function OrganizationFavoritesPage() {
  const { t } = useTranslation()
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

  if (organizations.isPending) return <PageLoading label={t('organizationFunding.favoritesLoading')} />
  if (organizations.isError) return <Card><CardContent className="p-8" role="alert">{t('organizationFunding.organizationFailed')}</CardContent></Card>
  if (!organization) return <OrganizationRequired />

  return (
    <div className="space-y-6">
      <header className="flex flex-wrap items-end justify-between gap-4">
        <div>
          <p className="text-sm font-bold uppercase tracking-[0.16em] text-primary">{t('organizationFunding.yourOrganization')}</p>
          <h1 className="mt-1 text-3xl font-bold tracking-tight">{t('organizationFunding.favoritesTitle')}</h1>
          <p className="mt-2 text-muted-foreground">{t('organizationFunding.favoritesDescription', { name: organization.name })}</p>
        </div>
        <Button asChild variant="outline"><Link to="/opportunities"><Search className="size-4" /> {t('organizationFunding.browse')}</Link></Button>
      </header>

      {favorites.isPending && <PageLoading label={t('organizationFunding.favoritesLoading')} />}
      {favorites.isError && (
        <Card className="border-destructive/40"><CardContent className="space-y-3 p-6" role="alert">
          <h2 className="font-bold">{t('organizationFunding.favoritesFailed')}</h2>
          <p className="text-sm text-muted-foreground">{organizationFundingErrorMessage(favorites.error, 'organizationFunding.loadHelp')}</p>
          <Button onClick={() => void favorites.refetch()} variant="outline">{t('organizationFunding.retry')}</Button>
        </CardContent></Card>
      )}
      {favorites.data && favorites.data.totalCount === 0 && (
        <Card><CardContent className="space-y-4 p-8 text-center">
          <Heart className="mx-auto size-9 text-muted-foreground" />
          <h2 className="text-xl font-bold">{t('organizationFunding.favoritesEmpty')}</h2>
          <p className="text-sm text-muted-foreground">{t('organizationFunding.favoritesEmptyHelp')}</p>
          <Button asChild><Link to="/opportunities">{t('organizationFunding.explore')}</Link></Button>
        </CardContent></Card>
      )}
      {favorites.data && favorites.data.totalCount > 0 && favorites.data.items.length === 0 && (
        <PageLoading label={t('organizationFunding.returning')} />
      )}
      {favorites.data && favorites.data.items.length > 0 && (
        <>
          <p aria-live="polite" className="text-sm text-muted-foreground"><strong className="text-foreground">{favorites.data.totalCount.toLocaleString(workspaceLocale())}</strong> {t('organizationFunding.favoritesCount', { count: favorites.data.totalCount })}</p>
          <FundingGrid items={favorites.data.items} organization={organization} />
        </>
      )}
      {favorites.data && <ResultsPagination disabled={favorites.isFetching} page={page} response={favorites.data} setPage={setPage} />}
    </div>
  )
}
