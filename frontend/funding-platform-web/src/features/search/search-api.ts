import { apiClient } from '@/api/http-client'
import type { MarketplaceProjectListResponse } from '@/features/marketplace/marketplace-api'
import type { FundingExplorerPage } from '@/features/funding-discovery/funding-discovery-api'
import type { NetworkDirectoryPage } from '@/features/network/network-api'
import type { Page, Professional } from '@/features/collaboration/collaboration-api'
import { searchRequest, type SearchCriteria, type SearchSource } from './search-model'

export interface SearchItem { id: string; title: string; summary: string | null; subtitle?: string; href?: string; biography?: string | null; skills?: string[] }
export interface SearchPage { items: SearchItem[]; totalCount: number; page: number; pageSize: number }

/** Federation of existing read-only projections; never an administrative or new public directory. */
export async function searchSource(source: SearchSource, criteria: SearchCriteria, signal: AbortSignal, organizationId?: string): Promise<SearchPage> {
  const path = searchRequest(source, criteria, organizationId)
  const options = { signal, cache: 'no-store' as const }
  if (source === 'projects') {
    const page = await apiClient.get<MarketplaceProjectListResponse>(path, options)
    return { page: page.pageNumber, pageSize: page.pageSize, totalCount: page.totalCount,
      items: page.items.filter(item => item.publicationStatus === undefined || item.publicationStatus === 2).map(item => ({
        id: item.publicId, title: item.title, summary: item.summary, subtitle: item.organization.name,
        href: `/marketplace/projects/${encodeURIComponent(item.slug)}`,
      })) }
  }
  if (source === 'funding') {
    const page = await apiClient.get<FundingExplorerPage>(path, options)
    return { page: page.page, pageSize: page.pageSize, totalCount: page.totalCount, items: page.items.map(item => ({
      id: item.id, title: item.title, summary: item.summary, subtitle: item.sourceName,
      href: `/funding/${encodeURIComponent(item.slug)}`,
    })) }
  }
  if (source === 'organizations') {
    const page = await apiClient.get<NetworkDirectoryPage>(path, options)
    return { page: page.page, pageSize: page.pageSize, totalCount: page.totalCount, items: page.items.map(item => ({
      id: item.id, title: item.name, summary: item.description,
      href: `/marketplace/organizations/${encodeURIComponent(item.id)}`,
    })) }
  }
  const page = await apiClient.get<Page<Professional>>(path, options)
  return { page: page.page, pageSize: page.pageSize, totalCount: page.totalCount,
    items: page.items.filter(item => item.data.isDiscoverable).map(item => ({
      id: item.profileId, title: item.data.displayName, summary: item.data.headline,
      biography: item.data.biography, skills: item.data.skills,
    })) }
}
