import { apiClient } from '@/api/http-client'

export type PublicationStatus = 0 | 1 | 2 | 3 | 4
export type ReviewDecision = 'approve' | 'reject'
export type AmountStatus = 0 | 1 | 2
export type DeadlineType = 0 | 1 | 2
export type DeadlinePrecision = 0 | 1 | 2
export type GeographicScope = 0 | 1 | 2
export type RemoteApplication = 0 | 1 | 2

export interface AdminPage<T> {
  items: T[]
  totalCount: number
  page: number
  pageSize: number
}

export interface EditorialWorkflowResponse {
  entityId: string
  publicationStatus: PublicationStatus
  contentVersion: number
  eTag: string
  wasReplay: boolean
}

export interface AdminFundingSource {
  id: number
  name: string
  providerType: number
  baseUrl: string | null
  isEnabled: boolean
}

export interface AdminFunderSummary {
  funderId: string
  slug: string
  name: string
  description: string | null
  websiteUrl: string | null
  countryId: number | null
  countryCode: string | null
  countryName: string | null
  publicationStatus: PublicationStatus
  isActive: boolean
  contentVersion: number
  updatedAtUtc: string
  eTag: string
}

export interface AdminFunderDetail extends AdminFunderSummary {
  createdAtUtc: string
  aliases: string[]
  submittedAtUtc: string | null
  reviewedAtUtc: string | null
  reviewedByUserId: string | null
  publishedAtUtc: string | null
  rejectionReason: string | null
  opportunities: Array<{
    opportunityId: string
    slug: string
    title: string
    role: 1 | 2 | 3
    publicationStatus: PublicationStatus
    isActive: boolean
  }>
}

export interface FunderWriteInput {
  name: string
  description: string | null
  websiteUrl: string | null
  countryId: number | null
  aliases: string[]
}

export interface AdminFunderReference {
  funderId: string
  slug: string
  name: string
  role: 1 | 2 | 3
}

export interface AdminFundingOpportunitySummary {
  opportunityId: string
  slug: string
  title: string
  summary: string | null
  sponsorName: string
  isActive: boolean
  currency: string | null
  minimumAmount: number | null
  maximumAmount: number | null
  openDate: string | null
  closeDate: string | null
  sourceName: string | null
  sourceUrl: string | null
  publishedAtUtc: string | null
  lastVerifiedAtUtc: string | null
  dataQualityScore: number
  publicationStatus: PublicationStatus
  contentVersion: number
  updatedAtUtc: string
  eTag: string
}

export interface AdminFundingOpportunityDetail {
  opportunityId: string
  slug: string
  title: string
  summary: string | null
  description: string | null
  sponsorName: string
  sponsorUrl: string | null
  applicationUrl: string | null
  externalId: string | null
  fundingSourceId: number
  issuerCountryId: number | null
  fundingTypeId: number | null
  currency: string | null
  minimumAmount: number | null
  maximumAmount: number | null
  amountStatus: AmountStatus
  openDate: string | null
  closeDate: string | null
  closeAtUtc: string | null
  deadlineTimeZoneId: string | null
  deadlineType: DeadlineType
  deadlinePrecision: DeadlinePrecision
  eligibilityDescription: string | null
  requirements: string | null
  objectives: string | null
  allowedActivities: string | null
  excludedActivities: string | null
  restrictions: string | null
  targetOrganizationsDescription: string | null
  targetPopulationsDescription: string | null
  minimumOperatingYears: number | null
  requiresLegalEntity: boolean | null
  requiresPriorExperience: boolean | null
  requiresCofunding: boolean | null
  cofundingPercentage: number | null
  geographicScope: GeographicScope
  remoteApplication: RemoteApplication
  sourceUrl: string
  lastVerifiedAtUtc: string | null
  funders: AdminFunderReference[]
  countryIds: number[]
  regionIds: number[]
  categoryIds: number[]
  beneficiaryTypeIds: number[]
  projectTypeIds: number[]
  evidence: Array<{
    evidenceId: string
    fieldPath: string
    valueJson: string
    extractionMethod: number
    evidenceText: string | null
    sourceLocator: string | null
    confidence: number | null
    isSelected: boolean
    isManualLock: boolean
    createdByUserId: string | null
    createdAtUtc: string
  }>
  sources: Array<{
    fundingSourceId: number
    sourceName: string
    externalId: string | null
    sourceUrl: string
    firstSeenAtUtc: string
    lastSeenAtUtc: string
    isPrimary: boolean
    isActive: boolean
  }>
  publicationStatus: PublicationStatus
  isActive: boolean
  contentVersion: number
  dataQualityScore: number
  createdAtUtc: string
  updatedAtUtc: string
  eTag: string
  submittedAtUtc: string | null
  reviewedAtUtc: string | null
  reviewedByUserId: string | null
  publishedAtUtc: string | null
  rejectionReason: string | null
}

export interface FundingOpportunityWriteInput {
  title: string
  summary: string | null
  description: string | null
  sponsorName: string
  sponsorUrl: string | null
  applicationUrl: string | null
  funders: Array<{ funderId: string; role: 1 | 2 | 3 }>
  fundingSourceId: number
  externalId: string | null
  issuerCountryId: number | null
  fundingTypeId: number | null
  currency: string | null
  minimumAmount: number | null
  maximumAmount: number | null
  amountStatus: AmountStatus
  openDate: string | null
  closeDate: string | null
  closeAtUtc: string | null
  deadlineTimeZoneId: string | null
  deadlineType: DeadlineType
  deadlinePrecision: DeadlinePrecision
  eligibilityDescription: string | null
  requirements: string | null
  objectives: string | null
  allowedActivities: string | null
  excludedActivities: string | null
  restrictions: string | null
  targetOrganizationsDescription: string | null
  targetPopulationsDescription: string | null
  minimumOperatingYears: number | null
  requiresLegalEntity: boolean | null
  requiresPriorExperience: boolean | null
  requiresCofunding: boolean | null
  cofundingPercentage: number | null
  geographicScope: GeographicScope
  remoteApplication: RemoteApplication
  sourceUrl: string
  lastVerifiedAtUtc: string | null
  countryIds: number[]
  regionIds: number[]
  categoryIds: number[]
  beneficiaryTypeIds: number[]
  projectTypeIds: number[]
}

interface AdminListFilters {
  query?: string
  status?: PublicationStatus | null
  includeInactive?: boolean
  page?: number
  pageSize?: number
}

function listQuery({ query, status, includeInactive = false, page = 1, pageSize = 20 }: AdminListFilters) {
  const parameters = new URLSearchParams({ page: String(page), pageSize: String(pageSize) })
  if (query?.trim()) parameters.set('query', query.trim())
  if (status !== null && status !== undefined) parameters.set('status', String(status))
  if (includeInactive) parameters.set('includeInactive', 'true')
  return parameters.toString()
}

function commandHeaders(eTag: string, idempotencyKey: string) {
  return { 'If-Match': eTag, 'Idempotency-Key': idempotencyKey }
}

function entityPath(prefix: string, id: string, suffix = '') {
  return `${prefix}/${encodeURIComponent(id)}${suffix}`
}

function editorialApi(prefix: string) {
  return {
    submitReview(id: string, eTag: string, idempotencyKey: string) {
      return apiClient.post<EditorialWorkflowResponse>(
        entityPath(prefix, id, '/submit-review'),
        undefined,
        { headers: commandHeaders(eTag, idempotencyKey) },
      )
    },
    review(
      id: string,
      eTag: string,
      idempotencyKey: string,
      decision: ReviewDecision,
      reason?: string,
    ) {
      return apiClient.post<EditorialWorkflowResponse>(
        entityPath(prefix, id, '/reviews'),
        { decision, ...(reason ? { reason } : {}) },
        { headers: commandHeaders(eTag, idempotencyKey) },
      )
    },
    deactivate(id: string, eTag: string, idempotencyKey: string, reason?: string) {
      return apiClient.post<EditorialWorkflowResponse>(
        entityPath(prefix, id, '/deactivate'),
        reason ? { reason } : {},
        { headers: commandHeaders(eTag, idempotencyKey) },
      )
    },
    startCorrection(id: string, eTag: string, idempotencyKey: string, reason: string) {
      return apiClient.post<EditorialWorkflowResponse>(
        entityPath(prefix, id, '/start-correction'),
        { reason },
        { headers: commandHeaders(eTag, idempotencyKey) },
      )
    },
  }
}

const funderPrefix = 'admin/funders'
const opportunityPrefix = 'admin/funding-opportunities'

export const adminFundersApi = {
  list(filters: AdminListFilters, signal?: AbortSignal) {
    return apiClient.get<AdminPage<AdminFunderSummary>>(
      `${funderPrefix}?${listQuery(filters)}`,
      { signal },
    )
  },
  get(id: string, signal?: AbortSignal) {
    return apiClient.get<AdminFunderDetail>(entityPath(funderPrefix, id), { signal })
  },
  create(input: FunderWriteInput, idempotencyKey: string) {
    return apiClient.post<EditorialWorkflowResponse>(funderPrefix, input, {
      headers: { 'Idempotency-Key': idempotencyKey },
    })
  },
  update(id: string, eTag: string, input: FunderWriteInput, idempotencyKey: string) {
    return apiClient.put<EditorialWorkflowResponse>(entityPath(funderPrefix, id), input, {
      headers: commandHeaders(eTag, idempotencyKey),
    })
  },
  ...editorialApi(funderPrefix),
}

export const adminFundingOpportunitiesApi = {
  list(filters: AdminListFilters, signal?: AbortSignal) {
    return apiClient.get<AdminPage<AdminFundingOpportunitySummary>>(
      `${opportunityPrefix}?${listQuery(filters)}`,
      { signal },
    )
  },
  get(id: string, signal?: AbortSignal) {
    return apiClient.get<AdminFundingOpportunityDetail>(entityPath(opportunityPrefix, id), { signal })
  },
  create(input: FundingOpportunityWriteInput, idempotencyKey: string) {
    return apiClient.post<EditorialWorkflowResponse>(opportunityPrefix, input, {
      headers: { 'Idempotency-Key': idempotencyKey },
    })
  },
  update(id: string, eTag: string, input: FundingOpportunityWriteInput, idempotencyKey: string) {
    return apiClient.put<EditorialWorkflowResponse>(entityPath(opportunityPrefix, id), input, {
      headers: commandHeaders(eTag, idempotencyKey),
    })
  },
  ...editorialApi(opportunityPrefix),
}

export const adminFundingSourcesApi = {
  list(signal?: AbortSignal) {
    return apiClient.get<AdminFundingSource[]>('admin/funding-sources', {
      cache: 'no-store',
      signal,
    })
  },
}
