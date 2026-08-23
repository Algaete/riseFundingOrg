import { apiClient } from '@/api/http-client'
import type {
  FundingOpportunityDetail,
  FundingOpportunityListItem,
  FundingOpportunityListResponse,
} from '@/features/funding/funding-opportunities-api'

export const fundingSortValues = [
  'relevance',
  'closing-soon',
  'newest',
  'amount-asc',
  'amount-desc',
] as const

export type FundingSort = (typeof fundingSortValues)[number]

export interface OrganizationFundingOpportunityListItem
  extends FundingOpportunityListItem {
  primaryFunderPublicId: string
  primaryFunderName: string
  closeAtUtc: string | null
  deadlineType: number
  deadlinePrecision: number
  isFavorite: boolean
}

export interface OrganizationFundingOpportunityDetail
  extends Omit<FundingOpportunityDetail, 'closeAtUtc' | 'deadlineType' | 'deadlinePrecision'>,
    OrganizationFundingOpportunityListItem {
  issuerCountryId: number | null
  fundingTypeId: number | null
  amountStatus: number
  deadlineTimeZoneId: string | null
  allowedActivities: string | null
  excludedActivities: string | null
  restrictions: string | null
  targetOrganizationsDescription: string | null
  targetPopulationsDescription: string | null
  minimumOperatingYears: number | null
  requiresLegalEntity: boolean | null
  requiresPriorExperience: boolean | null
  cofundingPercentage: number | null
  geographicScope: number
  remoteApplication: number
  contentVersion: number
  primaryFunderSlug: string
  countryIds: number[]
  regionIds: number[]
  categoryIds: number[]
  beneficiaryTypeIds: number[]
  projectTypeIds: number[]
  tagIds: number[]
  organizationTypes: FundingEligibilityItem[]
  legalEntityTypes: FundingEligibilityItem[]
  languages: FundingLanguageItem[]
  sources: FundingOpportunitySource[]
}

export interface FundingEligibilityItem {
  id: number
  eligibilityMode: number
}

export interface FundingLanguageItem {
  id: number
  languagePurpose: number
}

export interface FundingOpportunitySource {
  fundingSourceId: number
  sourceName: string
  externalId: string | null
  sourceUrl: string
  firstSeenAtUtc: string
  lastSeenAtUtc: string
  isPrimary: boolean
  isActive: boolean
}

export interface OrganizationFundingOpportunityListResponse
  extends Omit<FundingOpportunityListResponse, 'items'> {
  items: OrganizationFundingOpportunityListItem[]
  searchMode: 'full-text' | 'literal-fallback' | 'filtered' | 'none'
}

export interface OrganizationFundingSearch {
  query?: string
  countryIds?: number[]
  regionIds?: number[]
  categoryIds?: number[]
  tagIds?: number[]
  beneficiaryTypeIds?: number[]
  projectTypeIds?: number[]
  funderIds?: string[]
  sponsor?: string
  minimumAmount?: number
  maximumAmount?: number
  currency?: string
  closingFrom?: string
  closingTo?: string
  fundingTypeIds?: number[]
  organizationTypeIds?: number[]
  onlyOpen?: boolean
  sort?: FundingSort
  pageNumber: number
  pageSize: number
}

function organizationPath(organizationId: string, suffix: string) {
  return `organizations/${encodeURIComponent(organizationId)}/${suffix}`
}

function appendIds(parameters: URLSearchParams, key: string, values?: readonly (number | string)[]) {
  const validValues = values?.filter((value) => String(value).trim().length > 0)
  if (validValues?.length) parameters.set(key, validValues.join(','))
}

export function serializeFundingSearch(input: OrganizationFundingSearch) {
  const parameters = new URLSearchParams({
    page: String(input.pageNumber),
    pageSize: String(input.pageSize),
  })

  if (input.query?.trim()) parameters.set('q', input.query.trim())
  appendIds(parameters, 'countryIds', input.countryIds)
  appendIds(parameters, 'regionIds', input.regionIds)
  appendIds(parameters, 'categoryIds', input.categoryIds)
  appendIds(parameters, 'tagIds', input.tagIds)
  appendIds(parameters, 'beneficiaryTypeIds', input.beneficiaryTypeIds)
  appendIds(parameters, 'projectTypeIds', input.projectTypeIds)
  appendIds(parameters, 'funderIds', input.funderIds)
  appendIds(parameters, 'fundingTypeIds', input.fundingTypeIds)
  appendIds(parameters, 'organizationTypeIds', input.organizationTypeIds)
  if (input.sponsor?.trim()) parameters.set('sponsor', input.sponsor.trim())
  if (input.minimumAmount !== undefined) parameters.set('minAmount', String(input.minimumAmount))
  if (input.maximumAmount !== undefined) parameters.set('maxAmount', String(input.maximumAmount))
  if (input.currency) parameters.set('currency', input.currency)
  if (input.closingFrom) parameters.set('closingFrom', input.closingFrom)
  if (input.closingTo) parameters.set('closingTo', input.closingTo)
  if (input.onlyOpen !== undefined) parameters.set('onlyOpen', String(input.onlyOpen))
  if (input.sort) parameters.set('sort', input.sort)
  return parameters
}

export const organizationFundingApi = {
  search(
    organizationId: string,
    input: OrganizationFundingSearch,
    signal?: AbortSignal,
  ) {
    const parameters = serializeFundingSearch(input)
    return apiClient.get<OrganizationFundingOpportunityListResponse>(
      `${organizationPath(organizationId, 'funding-opportunities')}?${parameters.toString()}`,
      { cache: 'no-store', signal },
    )
  },

  getByIdOrSlug(organizationId: string, idOrSlug: string, signal?: AbortSignal) {
    return apiClient.get<OrganizationFundingOpportunityDetail>(
      organizationPath(
        organizationId,
        `funding-opportunities/${encodeURIComponent(idOrSlug)}`,
      ),
      { cache: 'no-store', signal },
    )
  },

  favorites(organizationId: string, pageNumber = 1, pageSize = 12, signal?: AbortSignal) {
    const parameters = new URLSearchParams({
      page: String(pageNumber),
      pageSize: String(pageSize),
    })
    return apiClient.get<OrganizationFundingOpportunityListResponse>(
      `${organizationPath(organizationId, 'favorites')}?${parameters.toString()}`,
      { cache: 'no-store', signal },
    )
  },

  addFavorite(organizationId: string, fundingOpportunityId: string) {
    return apiClient.put<void>(
      organizationPath(
        organizationId,
        `favorites/${encodeURIComponent(fundingOpportunityId)}`,
      ),
      undefined,
      { cache: 'no-store' },
    )
  },

  removeFavorite(organizationId: string, fundingOpportunityId: string) {
    return apiClient.delete<void>(
      organizationPath(
        organizationId,
        `favorites/${encodeURIComponent(fundingOpportunityId)}`,
      ),
      { cache: 'no-store' },
    )
  },
}
