import { apiClient } from '@/api/http-client'

export interface AdminOrganizationSummary {
  publicId: string
  name: string
  countryCode: string
  countryName: string
  organizationTypeName: string
  profileStatus: number
  profileCompleteness: number
  verificationStatus?: OrganizationVerificationStatus
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
  verificationStatus?: OrganizationVerificationStatus
  isActive?: boolean
  page: number
  pageSize: number
}

export type OrganizationVerificationStatus = 0 | 1 | 2

export interface OrganizationVerificationDecision {
  status: OrganizationVerificationStatus
  reason: string
  expectedRevision: number
  expectedProfileVersion: number
}

export interface OrganizationVerificationHistoryItem {
  revision: number
  status: OrganizationVerificationStatus
  profileVersion: number
  reason: string
  reviewedAtUtc: string
  reviewedByUserPublicId: string
  reviewedByName: string | null
}

export interface OrganizationVerification {
  organizationPublicId: string
  name: string
  status: OrganizationVerificationStatus
  recordedStatus: OrganizationVerificationStatus
  revision: number
  profileVersion: number
  reviewedProfileVersion: number | null
  reviewedAtUtc: string | null
  reviewedByUserPublicId: string | null
  reviewedByName: string | null
  reason: string | null
  needsReverification: boolean
  history: OrganizationVerificationHistoryItem[] | null
}

export const adminOrganizationsApi = {
  list(filters: AdminOrganizationFilters, signal?: AbortSignal) {
    const parameters = new URLSearchParams({
      page: String(filters.page),
      pageSize: String(filters.pageSize),
    })
    if (filters.q?.trim()) parameters.set('q', filters.q.trim())
    if (filters.profileStatus !== undefined) parameters.set('profileStatus', String(filters.profileStatus))
    if (filters.verificationStatus !== undefined) parameters.set('verificationStatus', String(filters.verificationStatus))
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
  getVerification(organizationId: string, signal?: AbortSignal) {
    return apiClient.get<OrganizationVerification>(
      `admin/organizations/${encodeURIComponent(organizationId)}/verification`,
      { cache: 'no-store', signal },
    )
  },
  decideVerification(organizationId: string, decision: OrganizationVerificationDecision) {
    return apiClient.post<OrganizationVerification>(
      `admin/organizations/${encodeURIComponent(organizationId)}/verification`, decision,
      { cache: 'no-store' },
    )
  },
}
