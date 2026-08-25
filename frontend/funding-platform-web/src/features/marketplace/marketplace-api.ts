import { apiClient } from '@/api/http-client'

import type {
  PublicProject,
  PublicProjectCatalogItem,
} from '@/features/projects/project-api'

export const marketplaceSortValues = ['newest', 'title', 'funding-gap-desc'] as const
export type MarketplaceSort = typeof marketplaceSortValues[number]

export interface MarketplaceProjectSearch {
  query?: string
  countryIds?: number[]
  categoryIds?: number[]
  projectTypeIds?: number[]
  projectStatus?: number
  currency?: string
  sort?: MarketplaceSort
  page?: number
  pageSize?: number
}

export interface MarketplaceProjectItem {
  publicId: string
  slug: string
  title: string
  summary: string | null
  status: number
  startDate: string | null
  endDate: string | null
  budgetTotal: number | null
  confirmedFunding: number | null
  currency: string | null
  fundingGap: number | null
  publishedAtUtc: string
  organization: {
    publicId: string
    name: string
    websiteUrl: string | null
  }
  publicationStatus?: number
}

export interface MarketplaceProjectDetails extends MarketplaceProjectItem {
  description: string | null
  regions: Array<PublicProjectCatalogItem & { countryId: number }>
  countries: PublicProjectCatalogItem[]
  categories: PublicProjectCatalogItem[]
  beneficiaryTypes: PublicProjectCatalogItem[]
  projectTypes: PublicProjectCatalogItem[]
}

export interface MarketplaceProjectListResponse {
  items: MarketplaceProjectItem[]
  totalCount: number
  pageNumber: number
  pageSize: number
}

export interface MarketplaceCatalogs {
  countries: PublicProjectCatalogItem[]
  fundingCategories: PublicProjectCatalogItem[]
  projectTypes: PublicProjectCatalogItem[]
  currencies: Array<{ code: string; name: string; minorUnits: number }>
}

export interface PublicOrganizationProfile {
  publicId: string
  name: string
  description: string | null
  websiteUrl: string | null
  establishedYear: number | null
  homeCountry: PublicProjectCatalogItem | null
  organizationType: PublicProjectCatalogItem | null
  organizationSize: PublicProjectCatalogItem | null
  countries: PublicProjectCatalogItem[]
  regions: Array<PublicProjectCatalogItem & { countryId: number }>
  categories: PublicProjectCatalogItem[]
  beneficiaryTypes: PublicProjectCatalogItem[]
  projectTypes: PublicProjectCatalogItem[]
  projects: MarketplaceProjectItem[]
}

function appendIds(parameters: URLSearchParams, key: string, values?: number[]) {
  const unique = [...new Set(values?.filter((value) => Number.isSafeInteger(value) && value > 0) ?? [])]
  if (unique.length > 0) parameters.set(key, unique.join(','))
}

export function serializeMarketplaceSearch(input: MarketplaceProjectSearch) {
  const parameters = new URLSearchParams()
  if (input.query?.trim()) parameters.set('q', input.query.trim())
  appendIds(parameters, 'countryIds', input.countryIds)
  appendIds(parameters, 'categoryIds', input.categoryIds)
  appendIds(parameters, 'projectTypeIds', input.projectTypeIds)
  if (input.projectStatus !== undefined && Number.isSafeInteger(input.projectStatus) && input.projectStatus >= 0 && input.projectStatus <= 6) {
    parameters.set('projectStatus', String(input.projectStatus))
  }
  const currency = input.currency?.trim().toUpperCase()
  const validCurrency = currency && /^[A-Z]{3}$/.test(currency) ? currency : undefined
  if (validCurrency) parameters.set('currency', validCurrency)
  const requestedSort = input.sort ?? 'newest'
  parameters.set('sort', requestedSort === 'funding-gap-desc' && !validCurrency ? 'newest' : requestedSort)
  parameters.set('page', String(input.page ?? 1))
  parameters.set('pageSize', String(input.pageSize ?? 12))
  return parameters
}

export const marketplaceApi = {
  search(input: MarketplaceProjectSearch, signal?: AbortSignal) {
    const parameters = serializeMarketplaceSearch(input)
    return apiClient.get<MarketplaceProjectListResponse>(
      `marketplace/projects?${parameters.toString()}`,
      { signal },
    )
  },

  getProject(slug: string, signal?: AbortSignal) {
    return apiClient.get<MarketplaceProjectDetails>(
      `marketplace/projects/${encodeURIComponent(slug)}`,
      { signal },
    ).then((project): PublicProject => ({
      projectId: project.publicId,
      slug: project.slug,
      title: project.title,
      summary: project.summary,
      description: project.description,
      projectStatus: project.status,
      startDate: project.startDate,
      endDate: project.endDate,
      budgetTotal: project.budgetTotal,
      confirmedFunding: project.confirmedFunding,
      currency: project.currency,
      fundingGap: project.fundingGap,
      publishedAtUtc: project.publishedAtUtc,
      organization: project.organization,
      countries: project.countries,
      regions: project.regions,
      categories: project.categories,
      beneficiaryTypes: project.beneficiaryTypes,
      projectTypes: project.projectTypes,
    }))
  },

  getOrganization(organizationId: string, signal?: AbortSignal) {
    return apiClient.get<PublicOrganizationProfile>(
      `marketplace/organizations/${encodeURIComponent(organizationId)}`,
      { signal },
    )
  },

  catalogs(signal?: AbortSignal) {
    return apiClient.get<MarketplaceCatalogs>('marketplace/catalogs', {
      signal,
    })
  },
}
