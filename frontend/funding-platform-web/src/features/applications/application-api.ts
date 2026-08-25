import { apiClient } from '@/api/http-client'

export const applicationStatuses = [0, 1, 2, 3, 4, 5] as const
export type ApplicationStatus = typeof applicationStatuses[number]

export const applicationStatusNames: Record<ApplicationStatus, string> = {
  0: 'Interesado',
  1: 'Preparando postulación',
  2: 'Presentada',
  3: 'Adjudicada',
  4: 'No adjudicada',
  5: 'Descartada',
}

export interface FundingApplication {
  publicId: string
  project: {
    publicId: string
    slug: string
    title: string
  }
  fundingOpportunity: {
    publicId: string
    slug: string
    title: string
    sponsorName: string
    closeDate: string | null
    closeAtUtc: string | null
    deadlinePrecision: number
  }
  status: ApplicationStatus
  notes: string | null
  applicationDate: string | null
  requestedAmount: number | null
  currency: string | null
  resultDate: string | null
  ownerUserPublicId: string
  canEdit: boolean
  createdAtUtc: string
  updatedAtUtc: string
  eTag: string
}

export interface FundingApplicationPage {
  items: FundingApplication[]
  totalCount: number
  pageNumber: number
  pageSize: number
}

export interface FundingApplicationSearch {
  status?: ApplicationStatus
  projectId?: string
  fundingOpportunityId?: string
  page?: number
  pageSize?: number
}

export interface FundingApplicationCreate {
  projectId: string
  fundingOpportunityId: string
  notes: string | null
  applicationDate: string | null
  requestedAmount: number | null
  currency: string | null
  resultDate: string | null
}

export interface FundingApplicationUpdate {
  status: ApplicationStatus
  notes: string | null
  applicationDate: string | null
  requestedAmount: number | null
  currency: string | null
  resultDate: string | null
}

function path(organizationId: string, suffix = '') {
  return `organizations/${encodeURIComponent(organizationId)}/applications${suffix}`
}

export function serializeApplicationSearch(input: FundingApplicationSearch) {
  const parameters = new URLSearchParams({
    page: String(input.page ?? 1),
    pageSize: String(input.pageSize ?? 12),
  })
  if (input.status !== undefined && applicationStatuses.includes(input.status)) {
    parameters.set('status', String(input.status))
  }
  if (input.projectId) parameters.set('projectId', input.projectId)
  if (input.fundingOpportunityId) parameters.set('fundingOpportunityId', input.fundingOpportunityId)
  return parameters
}

export const applicationApi = {
  list(organizationId: string, input: FundingApplicationSearch, signal?: AbortSignal) {
    return apiClient.get<FundingApplicationPage>(
      `${path(organizationId)}?${serializeApplicationSearch(input).toString()}`,
      { cache: 'no-store', signal },
    )
  },

  get(organizationId: string, applicationId: string, signal?: AbortSignal) {
    return apiClient.get<FundingApplication>(
      path(organizationId, `/${encodeURIComponent(applicationId)}`),
      { cache: 'no-store', signal },
    )
  },

  create(
    organizationId: string,
    input: FundingApplicationCreate,
    idempotencyKey: string,
  ) {
    return apiClient.post<FundingApplication>(path(organizationId), input, {
      cache: 'no-store',
      headers: { 'Idempotency-Key': idempotencyKey },
    })
  },

  update(
    organizationId: string,
    applicationId: string,
    eTag: string,
    input: FundingApplicationUpdate,
  ) {
    return apiClient.patch<FundingApplication>(
      path(organizationId, `/${encodeURIComponent(applicationId)}`),
      input,
      { cache: 'no-store', headers: { 'If-Match': eTag } },
    )
  },
}

export function createApplicationCommandId() {
  return crypto.randomUUID()
}
