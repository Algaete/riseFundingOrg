import { apiClient } from '@/api/http-client'

export interface AdminOrganizationSummary {
  publicId: string
  name: string
  countryCode: string
  countryName: string
  organizationTypeName: string
  profileStatus: number
  profileCompleteness: number
  isActive: boolean
  memberCount: number
  projectCount: number
  planCode: string
  planName: string
  subscriptionStatus: number | null
  createdAtUtc: string
  updatedAtUtc: string
}

export interface AdminOrganizationDetail extends AdminOrganizationSummary {
  legalName: string | null
  legalEntityTypeName: string | null
  organizationSizeName: string | null
  establishedYear: number | null
  websiteUrl: string | null
  description: string | null
  profileVersion: number
  adminMemberCount: number
  publishedProjectCount: number
  currentPeriodEndUtc: string | null
}

export interface AdminOrganizationPage {
  items: AdminOrganizationSummary[]
  totalCount: number
  page: number
  pageSize: number
}

export interface AdminOrganizationFilters {
  q?: string
  profileStatus?: number
  isActive?: boolean
  page: number
  pageSize: number
}

export const adminOrganizationsApi = {
  list(filters: AdminOrganizationFilters, signal?: AbortSignal) {
    const parameters = new URLSearchParams({
      page: String(filters.page),
      pageSize: String(filters.pageSize),
    })
    if (filters.q?.trim()) parameters.set('q', filters.q.trim())
    if (filters.profileStatus !== undefined) parameters.set('profileStatus', String(filters.profileStatus))
    if (filters.isActive !== undefined) parameters.set('isActive', String(filters.isActive))
    return apiClient.get<AdminOrganizationPage>(`admin/organizations?${parameters}`, {
      cache: 'no-store', signal,
    })
  },
  get(organizationId: string, signal?: AbortSignal) {
    return apiClient.get<AdminOrganizationDetail>(
      `admin/organizations/${encodeURIComponent(organizationId)}`,
      { cache: 'no-store', signal },
    )
  },
}
