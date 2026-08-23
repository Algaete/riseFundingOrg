import { apiClient } from '@/api/http-client'

export interface CatalogOption<TId extends number | string> {
  id: TId
  code: string
  name: string
}

export interface RegionOption extends CatalogOption<number> {
  countryId: number
}

export interface LegalEntityTypeOption extends CatalogOption<number> {
  countryId: number | null
}

export interface CurrencyOption {
  code: string
  name: string
  minorUnits: number
}

export interface OrganizationCatalogs {
  countries: CatalogOption<number>[]
  regions: RegionOption[]
  currencies: CurrencyOption[]
  fundingCategories: CatalogOption<number>[]
  fundingTypes: CatalogOption<number>[]
  organizationTypes: CatalogOption<number>[]
  legalEntityTypes: LegalEntityTypeOption[]
  organizationSizes: CatalogOption<number>[]
  beneficiaryTypes: CatalogOption<number>[]
  projectTypes: CatalogOption<number>[]
  tags: CatalogOption<number>[]
  languages: CatalogOption<number>[]
}

export interface OrganizationSummary {
  publicId: string
  name: string
  membershipRole: 'admin' | 'member'
  profileStatus: number
  profileCompleteness: number
  profileVersion: number
  updatedAtUtc: string
}

export interface OrganizationLanguage {
  languageId: number
  proficiency: number | null
}

export interface OrganizationProfile {
  publicId: string
  name: string
  legalName: string | null
  taxIdentifier: string | null
  homeCountryId: number
  organizationTypeId: number
  legalEntityTypeId: number | null
  organizationSizeId: number | null
  establishedYear: number | null
  websiteUrl: string | null
  description: string | null
  previousFundingExperience: number
  experienceSummary: string | null
  annualBudgetMin: number | null
  annualBudgetMax: number | null
  annualBudgetCurrency: string | null
  desiredFundingMin: number | null
  desiredFundingMax: number | null
  desiredFundingCurrency: string | null
  profileStatus: number
  profileCompleteness: number
  profileVersion: number
  membershipRole: 'admin' | 'member'
  canEdit: boolean
  eTag: string
  countryIds: number[]
  regionIds: number[]
  categoryIds: number[]
  beneficiaryTypeIds: number[]
  projectTypeIds: number[]
  tagIds: number[]
  languages: OrganizationLanguage[]
}

export type OrganizationProfileUpdate = Omit<
  OrganizationProfile,
  'publicId' | 'profileStatus' | 'profileCompleteness' | 'profileVersion' |
  'membershipRole' | 'canEdit' | 'eTag'
>

export const organizationApi = {
  catalogs(signal?: AbortSignal) {
    return apiClient.get<OrganizationCatalogs>('catalogs', { signal })
  },
  list(signal?: AbortSignal) {
    return apiClient.get<OrganizationSummary[]>('organizations', { signal })
  },
  create(input: { name: string; homeCountryId: number; organizationTypeId: number }) {
    return apiClient.post<{ publicId: string; profileVersion: number; eTag: string }>(
      'organizations', input,
    )
  },
  profile(organizationId: string, signal?: AbortSignal) {
    return apiClient.get<OrganizationProfile>(
      `organizations/${encodeURIComponent(organizationId)}/profile`, { signal },
    )
  },
  update(organizationId: string, eTag: string, input: OrganizationProfileUpdate) {
    return apiClient.put<OrganizationProfile>(
      `organizations/${encodeURIComponent(organizationId)}/profile`, input,
      { headers: { 'If-Match': eTag } },
    )
  },
}
