import { apiClient } from '@/api/http-client'
import type { OrganizationCatalogs } from '@/features/organizations/organization-api'

export interface PartnerGeography { scope: 0 | 1 | 2; countryIds: number[]; regionCodes: string[]; catalogVersion?: string | null }
export type FundingDiscoveryCatalogs = Pick<OrganizationCatalogs, 'countries' | 'regions' | 'currencies' | 'fundingCategories' | 'fundingTypes' | 'organizationTypes' | 'languages'> & {
  partnerRegions?: { code: string }[]; partnerGeographyVersion?: string
}
export interface DiscoveryClassification { funderKind: number | null; requiresConsortium: boolean | null; requiresInternationalPartner: boolean | null; evidenceUrl: string | null; partnerGeography?: PartnerGeography | null }
export interface ClassificationAdmin { opportunityId: string; title: string; contentVersion: number; reviewedContentVersion: number | null; data: DiscoveryClassification | null; eTag: string | null; sourceUrls: string[] }
export interface FundingExplorerPage { items: { id: string; title: string; slug: string; summary: string | null; sourceName: string; sourceUrl: string; lastVerifiedAtUtc: string | null;
  minimumAmount: number | null; maximumAmount: number | null; currency: string | null; closeDate: string | null; classification: DiscoveryClassification | null }[]; totalCount: number; page: number; pageSize: number }
export const fundingDiscoveryApi = {
  catalogs: (signal?: AbortSignal) => apiClient.get<FundingDiscoveryCatalogs>('funding-discovery/catalogs', { signal }),
  search: (params: URLSearchParams, signal?: AbortSignal) => apiClient.get<FundingExplorerPage>(`funding-discovery?${params}`, { signal }),
  get: (id: string, signal?: AbortSignal) => apiClient.get<ClassificationAdmin>(`admin/funding-discovery/${encodeURIComponent(id)}`, { signal, cache: 'no-store' }),
  review: (id: string, contentVersion: number, data: DiscoveryClassification, eTag: string | null, key: string) => apiClient.put<{ eTag: string }>(`admin/funding-discovery/${encodeURIComponent(id)}`, { contentVersion, data },
    { cache: 'no-store', headers: { ...(eTag ? { 'If-Match': eTag } : { 'If-None-Match': '*' }), 'Idempotency-Key': key } }),
}
